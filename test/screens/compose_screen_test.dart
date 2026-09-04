import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kouyu/pinyin/keyboard_layout.dart';
import 'package:kouyu/screens/compose_screen.dart';
import 'package:kouyu/theme.dart';
import 'package:kouyu/translation/translator.dart';

/// Records what it was asked, so the screen's use of the seam can be checked
/// without depending on any translator's contents.
class _RecordingTranslator implements Translator {
  final List<String> asked = [];
  Translation? reply;

  @override
  Future<Translation?> translate(String pinyin) async {
    asked.add(pinyin);
    return reply;
  }
}

void main() {
  Future<void> pump(
    WidgetTester tester, {
    Translator? translator,
    Brightness brightness = Brightness.light,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: brightness == Brightness.light ? kLightTheme : kDarkTheme,
        home: ComposeScreen(translator: translator ?? _RecordingTranslator()),
      ),
    );
  }

  /// Taps a key by the key the widget carries, so a label appearing in two
  /// places cannot confuse it.
  Future<void> tap(WidgetTester tester, String id) async {
    await tester.tap(find.byKey(Key(id)));
    await tester.pumpAndSettle();
  }

  /// Types one syllable through all three stages.
  Future<void> type(
    WidgetTester tester,
    String initial,
    String rime,
    int tone,
  ) async {
    await tap(tester, 'initial-$initial');
    await tap(tester, 'rime-$rime');
    await tap(tester, 'tone-$tone');
  }

  /// The composed line, read off the keyed rich text at the top of the screen.
  String composed(WidgetTester tester) {
    final text = tester.widget<Text>(find.byKey(const Key('composed')));
    return text.textSpan!.toPlainText();
  }

  testWidgets('opens on the initial bank', (tester) async {
    await pump(tester);

    expect(find.text('Start a syllable'), findsOneWidget);
    expect(find.byKey(const Key('initial-b')), findsOneWidget);
    // Later stages are not on screen yet — that is the point of staging.
    expect(find.byKey(const Key('rime-a')), findsNothing);
    expect(find.byKey(const Key('tone-1')), findsNothing);
  });

  // The complaint that prompted the staged design: wǒ was unreachable, because
  // it has no initial consonant and nothing on screen said w.
  testWidgets('w is offered, and reaches wǒ', (tester) async {
    await pump(tester);

    expect(find.byKey(const Key('initial-w')), findsOneWidget);
    await type(tester, 'w', 'o', 3);
    expect(composed(tester), 'wǒ');
  });

  testWidgets('each stage replaces the last', (tester) async {
    await pump(tester);

    await tap(tester, 'initial-n');
    expect(find.text('then what follows it'), findsOneWidget);
    expect(find.byKey(const Key('initial-b')), findsNothing);
    expect(find.byKey(const Key('rime-i')), findsOneWidget);

    await tap(tester, 'rime-i');
    expect(find.text('then its tone'), findsOneWidget);
    expect(find.byKey(const Key('rime-i')), findsNothing);
    expect(find.byKey(const Key('tone-3')), findsOneWidget);
  });

  // Only rimes that actually follow the chosen initial, so the keyboard cannot
  // be used to build a syllable Mandarin does not have.
  testWidgets('the rime bank is filtered to the chosen initial', (
    tester,
  ) async {
    await pump(tester);

    await tap(tester, 'initial-j');
    // j takes the i and ü series; ü after j is written u.
    expect(find.byKey(const Key('rime-ing')), findsOneWidget);
    expect(find.byKey(const Key('rime-un')), findsOneWidget);
    // There is no jong, and no jа-series rime spelled `ong`.
    expect(find.byKey(const Key('rime-ong')), findsNothing);
    expect(find.byKey(const Key('rime-uang')), findsNothing);
  });

  testWidgets('the tone bank shows the candidates, not bare marks', (
    tester,
  ) async {
    await pump(tester);

    await tap(tester, 'initial-n');
    await tap(tester, 'rime-i');

    // Read each key by its id: `find.text` also matches the rich text in the
    // reading area, where the untoned draft `ni` is on screen too.
    const expected = {1: 'nī', 2: 'ní', 3: 'nǐ', 4: 'nì', 5: 'ni'};
    for (final entry in expected.entries) {
      final label = tester.widget<Text>(
        find.descendant(
          of: find.byKey(Key('tone-${entry.key}')),
          matching: find.byType(Text),
        ),
      );
      expect(label.data, entry.value, reason: 'tone ${entry.key}');
    }
  });

  group('the trail', () {
    testWidgets('shows what was chosen, as it was pressed', (tester) async {
      await pump(tester);

      await tap(tester, 'initial-w');
      expect(
        tester
            .widget<Text>(
              find.descendant(
                of: find.byKey(const Key('trail-initial')),
                matching: find.byType(Text),
              ),
            )
            .data,
        'w',
      );

      await tap(tester, 'rime-o');
      // Pressed as `o`, even though the rime is phonologically `uo`.
      expect(
        tester
            .widget<Text>(
              find.descendant(
                of: find.byKey(const Key('trail-rime')),
                matching: find.byType(Text),
              ),
            )
            .data,
        'o',
      );
    });

    testWidgets('goes back to a choice without losing earlier ones', (
      tester,
    ) async {
      await pump(tester);

      await tap(tester, 'initial-n');
      await tap(tester, 'rime-i');
      await tap(tester, 'trail-rime');
      // Back at the rime bank, still under n.
      expect(find.text('then what follows it'), findsOneWidget);
      expect(find.byKey(const Key('trail-initial')), findsOneWidget);

      await tap(tester, 'trail-initial');
      expect(find.text('Start a syllable'), findsOneWidget);
      expect(find.byKey(const Key('trail-initial')), findsNothing);
    });
  });

  testWidgets('space separates words, and syllables otherwise run on', (
    tester,
  ) async {
    await pump(tester);

    await type(tester, 'n', 'i', 3);
    await tap(tester, 'space');
    await type(tester, 'h', 'ao', 3);
    expect(composed(tester), 'nǐ hǎo');

    // No space this time, so it joins the current word.
    await type(tester, 'sh', 'i', 4);
    expect(composed(tester), 'nǐ hǎoshì');
  });

  testWidgets('backspace and clear undo typing', (tester) async {
    await pump(tester);

    await type(tester, 'n', 'i', 3);
    await tap(tester, 'backspace');
    expect(find.byKey(const Key('composed')), findsNothing);

    await type(tester, 'h', 'ao', 3);
    await tap(tester, 'clear');
    expect(find.byKey(const Key('composed')), findsNothing);
  });

  testWidgets('sends the toned text to the translator and shows the reply', (
    tester,
  ) async {
    final translator = _RecordingTranslator()..reply = const Translation('you');
    await pump(tester, translator: translator);

    await type(tester, 'n', 'i', 3);

    // Tone marks must survive the trip: they are what disambiguates.
    expect(translator.asked.last, 'nǐ');
    expect(find.text('you'), findsOneWidget);
  });

  testWidgets('labels a word-by-word gloss as such', (tester) async {
    final translator = _RecordingTranslator()
      ..reply = const Translation('you · good', wordByWord: true);
    await pump(tester, translator: translator);

    await type(tester, 'n', 'i', 3);

    expect(find.text('you · good'), findsOneWidget);
    expect(find.text('word by word'), findsOneWidget);
  });

  // Staging exists partly to keep the banks small enough to fit a phone.
  testWidgets('every bank fits phone width without clipping', (tester) async {
    tester.view.physicalSize = const Size(375, 812);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await pump(tester);

    for (final id in ['space', 'backspace', 'clear']) {
      expect(tester.getRect(find.byKey(Key(id))).right, lessThanOrEqualTo(375));
    }
    // Walk all three stages; a RenderFlex overflow would surface here.
    await tap(tester, 'initial-zh');
    await tap(tester, 'rime-uang');
    expect(tester.takeException(), isNull);
    await tap(tester, 'tone-1');
    expect(composed(tester), 'zhuāng');
  });

  // A keyboard whose keys move while you use it is worse than a cramped one.
  testWidgets('the keys do not move as text is composed', (tester) async {
    tester.view.physicalSize = const Size(375, 812);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final translator = _RecordingTranslator()..reply = const Translation('you');
    await pump(tester, translator: translator);

    final before = tester.getRect(find.byKey(const Key('initial-b')));
    await type(tester, 'n', 'i', 3);
    expect(find.text('you'), findsOneWidget);

    expect(tester.getRect(find.byKey(const Key('initial-b'))), before);
  });

  testWidgets('every initial leads to a usable bank', (tester) async {
    await pump(tester);

    for (final initial in initialKeys) {
      await tap(tester, 'initial-${initial.label}');
      expect(
        find.byType(OutlinedButton),
        findsWidgets,
        reason: 'no rimes offered under ${initial.label}',
      );
      expect(tester.takeException(), isNull, reason: initial.label);
      await tap(tester, 'trail-initial');
    }
  });

  testWidgets('renders in both light and dark themes', (tester) async {
    for (final brightness in Brightness.values) {
      await pump(tester, brightness: brightness);
      await type(tester, 'n', 'i', 3);
      expect(tester.takeException(), isNull);
    }
  });
}
