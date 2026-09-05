import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kouyu/screens/compose_screen.dart';
import 'package:kouyu/theme.dart';
import 'package:kouyu/translation/translator.dart';
import 'package:kouyu/widgets/blinking_cursor.dart';

class _SilentTranslator implements Translator {
  @override
  Future<Translation?> translate(String pinyin) async => null;
}

/// WCAG's contrast ratio between two opaque colours.
double _contrast(Color a, Color b) {
  final first = a.computeLuminance();
  final second = b.computeLuminance();
  return (math.max(first, second) + 0.05) / (math.min(first, second) + 0.05);
}

void main() {
  // The caret's repeating animation would stop pumpAndSettle returning.
  setUp(() => BlinkingCursor.debugStatic = true);

  /// The colour the label is actually painted in, resolved rather than as
  /// written: the bug this guards against was a style whose colour was
  /// inherited from the text theme and silently beat the button's own.
  Color labelColour(WidgetTester tester, String id) => tester
      .renderObject<RenderParagraph>(
        find
            .descendant(
              of: find.byKey(Key(id)),
              matching: find.byType(RichText),
            )
            .first,
      )
      .text
      .style!
      .color!;

  /// The nearest opaque fill behind the label.
  ///
  /// Looks inside the key first, then outwards: an outlined key paints no
  /// background of its own, so what sits behind its label is the keyboard's
  /// own surface.
  Color fillColour(WidgetTester tester, String id) {
    final key = find.byKey(Key(id));
    for (final where in [
      find.descendant(of: key, matching: find.byType(Material)),
      find.ancestor(of: key, matching: find.byType(Material)),
    ]) {
      for (final material in tester.widgetList<Material>(where)) {
        final colour = material.color;
        if (colour != null && colour.a > 0) return colour;
      }
    }
    fail('nothing opaque behind $id');
  }

  Future<void> pump(WidgetTester tester, ThemeData theme) async {
    tester.view.physicalSize = const Size(375, 812);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: theme,
        home: ComposeScreen(translator: _SilentTranslator()),
      ),
    );
  }

  // 4.5:1 is WCAG AA for body text. The tone keys are large enough to qualify
  // for the 3:1 large-text allowance, but they are the most important keys on
  // the screen and the ones a learner reads a diacritic off, so hold them to
  // the stricter bar.
  const minimumRatio = 4.5;

  for (final theme in {'light': kLightTheme, 'dark': kDarkTheme}.entries) {
    group('${theme.key} theme', () {
      testWidgets('initial keys are legible', (tester) async {
        await pump(tester, theme.value);

        for (final id in ['initial-b', 'initial-zh', 'initial-a']) {
          final ratio = _contrast(
            labelColour(tester, id),
            fillColour(tester, id),
          );
          expect(
            ratio,
            greaterThanOrEqualTo(minimumRatio),
            reason: '$id is ${ratio.toStringAsFixed(2)}:1',
          );
        }
      });

      testWidgets('rime keys are legible', (tester) async {
        await pump(tester, theme.value);
        await tester.tap(find.byKey(const Key('initial-n')));
        await tester.pumpAndSettle();

        final ratio = _contrast(
          labelColour(tester, 'rime-iang'),
          fillColour(tester, 'rime-iang'),
        );
        expect(
          ratio,
          greaterThanOrEqualTo(minimumRatio),
          reason: 'rime-iang is ${ratio.toStringAsFixed(2)}:1',
        );
      });

      testWidgets('tone keys are legible', (tester) async {
        await pump(tester, theme.value);
        await tester.tap(find.byKey(const Key('initial-n')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('rime-i')));
        await tester.pumpAndSettle();

        for (var tone = 1; tone <= 5; tone++) {
          final id = 'tone-$tone';
          final ratio = _contrast(
            labelColour(tester, id),
            fillColour(tester, id),
          );
          expect(
            ratio,
            greaterThanOrEqualTo(minimumRatio),
            reason: '$id is ${ratio.toStringAsFixed(2)}:1',
          );
        }
      });

      testWidgets('the space and backspace keys are legible', (tester) async {
        await pump(tester, theme.value);

        for (final id in ['space', 'backspace']) {
          final icon = tester.widget<Icon>(
            find.descendant(
              of: find.byKey(Key(id)),
              matching: find.byType(Icon),
            ),
          );
          final resolved =
              icon.color ??
              IconTheme.of(tester.element(find.byKey(Key(id)))).color!;
          final ratio = _contrast(resolved, fillColour(tester, id));
          expect(
            ratio,
            greaterThanOrEqualTo(3.0),
            reason: '$id is ${ratio.toStringAsFixed(2)}:1',
          );
        }
      });
    });
  }
}
