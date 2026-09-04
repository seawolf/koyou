import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kouyu/screens/compose_screen.dart';
import 'package:kouyu/theme.dart';
import 'package:kouyu/translation/translator.dart';

/// Records what it was asked, so the screen's use of the seam can be checked
/// without depending on the phrasebook's contents.
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
  /// places (`a` is both a rime and the neutral-tone key) cannot confuse it.
  Future<void> tap(WidgetTester tester, String id) async {
    await tester.tap(find.byKey(Key(id)));
    await tester.pumpAndSettle();
  }

  /// The composed line, read off the keyed rich text at the top of the screen.
  /// By key rather than by position, because several labels on this screen
  /// contain the same letters as the pinyin being typed.
  String composed(WidgetTester tester) {
    final text = tester.widget<Text>(find.byKey(const Key('composed')));
    return text.textSpan!.toPlainText();
  }

  testWidgets('prompts before anything is typed', (tester) async {
    await pump(tester);
    expect(find.textContaining('Tap an initial'), findsOneWidget);
  });

  testWidgets('initial, rime and tone compose a toned syllable', (
    tester,
  ) async {
    await pump(tester);

    await tap(tester, 'initial-n');
    await tap(tester, 'rime-i');
    // Untoned until a tone is chosen, and shown as a draft.
    expect(composed(tester), 'ni');

    await tap(tester, 'tone-3');
    expect(composed(tester), 'nǐ');
  });

  testWidgets('space separates words, and syllables otherwise run on', (
    tester,
  ) async {
    await pump(tester);

    await tap(tester, 'initial-n');
    await tap(tester, 'rime-i');
    await tap(tester, 'tone-3');
    await tap(tester, 'space');
    await tap(tester, 'initial-h');
    await tap(tester, 'rime-ao');
    await tap(tester, 'tone-3');
    expect(composed(tester), 'nǐ hǎo');

    // No space this time, so it joins the current word.
    await tap(tester, 'initial-sh');
    await tap(tester, 'rime-i');
    await tap(tester, 'tone-4');
    expect(composed(tester), 'nǐ hǎoshì');
  });

  testWidgets('tone keys are disabled until there is a rime to mark', (
    tester,
  ) async {
    await pump(tester);

    FilledButton toneKey() =>
        tester.widget<FilledButton>(find.byKey(const Key('tone-1')));

    expect(toneKey().onPressed, isNull);
    await tap(tester, 'initial-n');
    expect(toneKey().onPressed, isNull, reason: 'an initial is not a syllable');
    await tap(tester, 'rime-i');
    expect(toneKey().onPressed, isNotNull);
  });

  // The keys show which initial and rime are armed, so they must stop looking
  // armed the moment the tone commits the syllable.
  testWidgets('keys stop looking armed once the syllable is committed', (
    tester,
  ) async {
    await pump(tester);

    bool armed(String id) =>
        tester.widget<ChoiceChip>(find.byKey(Key(id))).selected;

    await tap(tester, 'initial-n');
    await tap(tester, 'rime-i');
    expect(armed('initial-n'), isTrue);
    expect(armed('rime-i'), isTrue);

    await tap(tester, 'tone-3');
    expect(armed('initial-n'), isFalse);
    expect(armed('rime-i'), isFalse);
  });

  testWidgets('backspace and clear undo typing', (tester) async {
    await pump(tester);

    await tap(tester, 'initial-n');
    await tap(tester, 'rime-i');
    await tap(tester, 'tone-3');
    await tap(tester, 'backspace');
    expect(find.textContaining('Tap an initial'), findsOneWidget);

    await tap(tester, 'initial-h');
    await tap(tester, 'rime-ao');
    await tap(tester, 'tone-3');
    await tap(tester, 'clear');
    expect(find.textContaining('Tap an initial'), findsOneWidget);
  });

  testWidgets('sends the toned text to the translator and shows the reply', (
    tester,
  ) async {
    final translator = _RecordingTranslator()..reply = const Translation('you');
    await pump(tester, translator: translator);

    await tap(tester, 'initial-n');
    await tap(tester, 'rime-i');
    await tap(tester, 'tone-3');

    // Tone marks must survive the trip: they are what disambiguates.
    expect(translator.asked.last, 'nǐ');
    expect(find.text('you'), findsOneWidget);
  });

  testWidgets('labels a word-by-word gloss as such', (tester) async {
    final translator = _RecordingTranslator()
      ..reply = const Translation('you · good', wordByWord: true);
    await pump(tester, translator: translator);

    await tap(tester, 'initial-n');
    await tap(tester, 'rime-i');
    await tap(tester, 'tone-3');

    expect(find.text('you · good'), findsOneWidget);
    expect(find.text('word by word'), findsOneWidget);
  });

  // The tone keys and the controls share one row, and at phone width the
  // controls were being pushed off the edge entirely - leaving no way to start
  // a second word or undo a mistake.
  testWidgets('every key stays reachable at phone width', (tester) async {
    tester.view.physicalSize = const Size(375, 812);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await pump(tester);

    for (final id in ['tone-1', 'tone-5', 'space', 'backspace', 'clear']) {
      expect(
        tester.getRect(find.byKey(Key(id))).right,
        lessThanOrEqualTo(375),
        reason: '$id runs off the right edge',
      );
    }
    // A RenderFlex overflow would surface here.
    expect(tester.takeException(), isNull);

    await tap(tester, 'initial-n');
    await tap(tester, 'rime-i');
    await tap(tester, 'tone-3');
    await tap(tester, 'space');
    await tap(tester, 'initial-h');
    await tap(tester, 'rime-ao');
    await tap(tester, 'tone-3');
    expect(composed(tester), 'nǐ hǎo');
  });

  // A keyboard whose keys move while you use it is worse than a cramped one.
  // The reading area above must not push the banks around as text appears.
  testWidgets('the keys do not move as text is composed', (tester) async {
    tester.view.physicalSize = const Size(375, 812);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final translator = _RecordingTranslator()..reply = const Translation('you');
    await pump(tester, translator: translator);

    final before = tester.getRect(find.byKey(const Key('initial-b')));

    await tap(tester, 'initial-n');
    await tap(tester, 'rime-i');
    await tap(tester, 'tone-3');
    // The prompt has been replaced by composed text and a translation, which
    // is the moment the layout used to jump.
    expect(find.text('you'), findsOneWidget);

    expect(tester.getRect(find.byKey(const Key('initial-b'))), before);
  });

  testWidgets('renders in both light and dark themes', (tester) async {
    for (final brightness in Brightness.values) {
      await pump(tester, brightness: brightness);
      await tap(tester, 'initial-n');
      await tap(tester, 'rime-i');
      await tap(tester, 'tone-3');
      expect(tester.takeException(), isNull);
    }
  });
}
