import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kouyu/pinyin/keyboard_layout.dart';
import 'package:kouyu/screens/compose_screen.dart';
import 'package:kouyu/theme.dart';
import 'package:kouyu/translation/translator.dart';
import 'package:kouyu/widgets/blinking_cursor.dart';
import 'package:kouyu/widgets/pinyin_keyboard.dart';
import 'package:kouyu/translation/model_store_absent.dart';

/// Records what it was asked, so the screen's use of the seam can be checked
/// without depending on any translator's contents.
class _RecordingTranslator implements Translator {
  final List<String> asked = [];
  final List<String> keys = [];
  Translation? reply;

  @override
  Future<Translation?> translate(TranslationRequest request) async {
    asked.add(request.written);
    keys.add(request.key);
    return reply;
  }
}

/// A translator that answers only when told to, for testing lookup latency.
class _SlowTranslator implements Translator {
  Completer<Translation?>? pending;

  @override
  Future<Translation?> translate(TranslationRequest request) {
    return (pending = Completer<Translation?>()).future;
  }
}

void main() {
  // A repeating animation means pumpAndSettle never returns, so the caret is
  // held still for every test except the one that checks it blinks.
  setUp(() => BlinkingCursor.debugStatic = true);

  /// Pumps at phone size, which is what the keyboard is designed against. The
  /// default 800x600 test window is shorter than any phone and pushes the last
  /// row of the initial bank out of reach.
  Future<void> pump(
    WidgetTester tester, {
    Translator? translator,
    Translator? phraseTranslator,
    Brightness brightness = Brightness.light,
    Size size = const Size(375, 812),
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: brightness == Brightness.light ? kLightTheme : kDarkTheme,
        home: ComposeScreen(
          translator: translator ?? _RecordingTranslator(),
          phraseTranslator: phraseTranslator,
          // The web implementation, imported directly: it reports
          // "no model on this platform" and touches no plugin, which
          // is what a widget test wants.
          modelStore: modelStore(),
        ),
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
    // Placeholders excluded: the caret is a WidgetSpan and would otherwise
    // show up as U+FFFC in the middle of the pinyin.
    return text.textSpan!.toPlainText(includePlaceholders: false);
  }

  // Nothing is looked up until something is typed, so a 6.5MB dictionary
  // cannot slow the app down before the learner has asked it anything.
  testWidgets('asks the translator nothing at startup', (tester) async {
    final translator = _RecordingTranslator();
    await pump(tester, translator: translator);

    expect(translator.asked, isEmpty);
  });

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

  // Reported as "how do I type ai?" — it was behind a key labelled `–`, and in
  // the QWERTY arrangement `sh` sat exactly where a hand reaches for `a`.
  testWidgets('a is offered, and reaches ài', (tester) async {
    await pump(tester);

    expect(find.byKey(const Key('initial-a')), findsOneWidget);
    await type(tester, 'a', 'ai', 4);
    expect(composed(tester), 'ài');
  });

  testWidgets('the prompt stays up while nothing is spelled yet', (
    tester,
  ) async {
    await pump(tester);
    expect(find.text('Your pinyin appears here'), findsOneWidget);

    // A vowel key contributes no letters, so there is still nothing to show.
    await tap(tester, 'initial-a');
    expect(find.text('Your pinyin appears here'), findsOneWidget);

    await tap(tester, 'rime-ai');
    expect(find.text('Your pinyin appears here'), findsNothing);
    expect(composed(tester), 'ai');
  });

  testWidgets('a sits at its home position in the QWERTY arrangement', (
    tester,
  ) async {
    await pump(tester);

    // Home row, first key — where a hand reaching for `a` actually lands.
    final a = tester.getRect(find.byKey(const Key('initial-a')));
    final s = tester.getRect(find.byKey(const Key('initial-s')));
    expect(a.top, s.top, reason: 'a is not on the home row');
    expect(a.left, lessThan(s.left), reason: 'a is not left of s');

    await type(tester, 'a', 'ai', 4);
    expect(composed(tester), 'ài');
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

  // Three candidate meanings shown plainly read as one confident answer.
  testWidgets('says when the pinyin matched several words', (tester) async {
    final translator = _RecordingTranslator()
      ..reply = const Translation(
        'life / matter / to serve as an official',
        uncertain: true,
      );
    await pump(tester, translator: translator);

    await type(tester, 'sh', 'i', 4);
    expect(
      find.text('life / matter / to serve as an official'),
      findsOneWidget,
    );
    expect(find.text('several words sound like this'), findsOneWidget);
  });

  testWidgets('sends the tone-numbered key, not just the marks', (
    tester,
  ) async {
    final translator = _RecordingTranslator();
    await pump(tester, translator: translator);

    await type(tester, 'sh', 'i', 4);
    expect(translator.asked.last, 'shì');
    expect(translator.keys.last, 'shi4', reason: 'the dictionary key is wrong');
  });

  // A word-by-word answer is a list, not a sentence. Joined on one line,
  // "you · good" invites being read as a translation of the phrase, which is
  // the one thing it is not.
  testWidgets('a word-by-word gloss is a list, one word per line', (
    tester,
  ) async {
    final translator = _RecordingTranslator()
      ..reply = const Translation(
        'you · good',
        wordByWord: true,
        words: [
          WordGloss(pinyin: 'nǐ', english: 'you'),
          WordGloss(pinyin: 'hǎo', english: 'good'),
        ],
      );
    await pump(tester, translator: translator);

    await type(tester, 'n', 'i', 3);

    // Each word on its own line, labelled with the pinyin it came from.
    expect(find.byKey(const Key('word-list')), findsOneWidget);
    for (final part in ['nǐ', 'you', 'hǎo', 'good']) {
      expect(find.text(part), findsOneWidget, reason: part);
    }
    // And not as one run-together line, nor with a headline pretending to be
    // a translation of the whole.
    expect(find.text('you · good'), findsNothing);
    expect(find.byKey(const Key('headline')), findsNothing);
  });

  group('the considered tier', () {
    /// Counts calls and answers when told to, so the wait can be inspected.
    Translation phrase(String text) => Translation(
      text,
      words: const [
        WordGloss(pinyin: 'wǒ', english: 'I; me'),
        WordGloss(pinyin: 'mài', english: 'to sell'),
      ],
    );

    // The defect this exists to prevent: woken on every keystroke, the model
    // spends a second of a phone's CPU per syllable translating a phrase
    // nobody has finished writing — and on a shared engine those calls
    // corrupt each other.
    testWidgets('is not asked while typing continues', (tester) async {
      final slow = _RecordingTranslator()..reply = phrase('I sell');
      await pump(tester, phraseTranslator: slow);

      await type(tester, 'w', 'o', 3);
      // A space, so these are two words: a single word, however many
      // syllables, is the dictionary's job and never reaches this tier.
      await tap(tester, 'space');
      await type(tester, 'm', 'ai', 4);
      expect(slow.asked, isEmpty, reason: 'nothing until typing pauses');

      await tester.pump(const Duration(milliseconds: 700));
      await tester.pumpAndSettle();
      expect(slow.asked, ['wǒ mài'], reason: 'asked once, for the whole thing');
    });

    testWidgets('is never asked about a single word', (tester) async {
      final slow = _RecordingTranslator()..reply = phrase('I');
      await pump(tester, phraseTranslator: slow);

      await type(tester, 'w', 'o', 3);
      await tester.pump(const Duration(milliseconds: 700));
      await tester.pumpAndSettle();

      expect(slow.asked, isEmpty);
    });

    testWidgets('shows a spinner while it works', (tester) async {
      final slow = _SlowTranslator();
      await pump(tester, phraseTranslator: slow);

      await type(tester, 'w', 'o', 3);
      // A space, so these are two words: a single word, however many
      // syllables, is the dictionary's job and never reaches this tier.
      await tap(tester, 'space');
      await type(tester, 'm', 'ai', 4);
      expect(find.byKey(const Key('thinking')), findsNothing);

      await tester.pump(const Duration(milliseconds: 700));
      expect(find.byKey(const Key('thinking')), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      slow.pending!.complete(phrase('I sell books'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('thinking')), findsNothing);
      expect(find.text('I sell books'), findsOneWidget);
    });

    // What the phrase means, and what each word in it means, are both worth
    // seeing — the second is how a learner checks the first.
    testWidgets('shows the parts beside the whole', (tester) async {
      final quick = _RecordingTranslator()
        ..reply = const Translation(
          'I; me · to sell',
          wordByWord: true,
          words: [
            WordGloss(pinyin: 'wǒ', english: 'I; me'),
            WordGloss(pinyin: 'mài', english: 'to sell'),
          ],
        );
      final slow = _RecordingTranslator()..reply = phrase('I sell books');
      await pump(tester, translator: quick, phraseTranslator: slow);

      await type(tester, 'w', 'o', 3);
      // A space, so these are two words: a single word, however many
      // syllables, is the dictionary's job and never reaches this tier.
      await tap(tester, 'space');
      await type(tester, 'm', 'ai', 4);
      await tester.pump(const Duration(milliseconds: 700));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('headline')), findsOneWidget);
      expect(find.text('I sell books'), findsOneWidget);
      expect(find.byKey(const Key('word-list')), findsOneWidget);
      expect(find.text('to sell'), findsOneWidget);
      expect(find.text('word by word'), findsOneWidget);
    });

    // An answer about words the learner has since changed is worse than none.
    testWidgets('a further edit drops the answer it was about', (tester) async {
      final slow = _SlowTranslator();
      await pump(tester, phraseTranslator: slow);

      await type(tester, 'w', 'o', 3);
      // A space, so these are two words: a single word, however many
      // syllables, is the dictionary's job and never reaches this tier.
      await tap(tester, 'space');
      await type(tester, 'm', 'ai', 4);
      await tester.pump(const Duration(milliseconds: 700));
      final answering = slow.pending!;

      await tap(tester, 'backspace');
      answering.complete(phrase('I sell books'));
      await tester.pumpAndSettle();

      expect(find.text('I sell books'), findsNothing);
      expect(find.byKey(const Key('thinking')), findsNothing);
    });

    testWidgets('leaves no timer running when the screen goes away', (
      tester,
    ) async {
      await pump(tester, phraseTranslator: _SlowTranslator());
      await type(tester, 'w', 'o', 3);
      // A space, so these are two words: a single word, however many
      // syllables, is the dictionary's job and never reaches this tier.
      await tap(tester, 'space');
      await type(tester, 'm', 'ai', 4);
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 1));
      expect(tester.takeException(), isNull);
    });
  });

  // A word list is the widest thing the reading area ever holds: an ambiguous
  // syllable offers three candidate meanings, and there is one line per word.
  testWidgets('a long word list fits, in both orientations', (tester) async {
    const crowded = Translation(
      'x',
      wordByWord: true,
      uncertain: true,
      words: [
        WordGloss(pinyin: 'shì', english: 'to be / life / matter / to serve'),
        WordGloss(pinyin: 'jiè', english: 'boundary / to introduce / world'),
        WordGloss(pinyin: 'zhuāng', english: 'to install / village / solemn'),
        WordGloss(pinyin: 'nǚ', english: 'female / woman / daughter'),
        WordGloss(pinyin: 'lǜ', english: 'law / rate / green / to consider'),
      ],
    );

    for (final size in [const Size(375, 667), const Size(812, 375)]) {
      final translator = _RecordingTranslator()..reply = crowded;
      await pump(tester, translator: translator, size: size);
      // A first-row rime, because the rime bank scrolls in landscape and `i`
      // sits below the fold there.
      await type(tester, 'n', 'a', 3);
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('word-list')), findsOneWidget);
      expect(tester.takeException(), isNull, reason: '$size');
      // Every line inside the screen, not merely un-crashed.
      for (final gloss in crowded.words) {
        final rect = tester.getRect(find.text(gloss.english));
        expect(rect.right, lessThanOrEqualTo(size.width), reason: gloss.pinyin);
      }
    }
  });

  // Staging exists partly to keep the banks small enough to fit a phone.
  testWidgets('every bank fits phone width without clipping', (tester) async {
    await pump(tester);

    for (final id in ['space', 'backspace']) {
      expect(tester.getRect(find.byKey(Key(id))).right, lessThanOrEqualTo(375));
    }
    // Walk all three stages; a RenderFlex overflow would surface here.
    await tap(tester, 'initial-zh');
    await tap(tester, 'rime-uang');
    expect(tester.takeException(), isNull);
    await tap(tester, 'tone-1');
    expect(composed(tester), 'zhuāng');
  });

  group('arrangements', () {
    testWidgets('the app bar switches between them', (tester) async {
      await pump(tester);

      // QWERTY to begin with.
      expect(find.byKey(const Key('initial-zh')), findsOneWidget);
      final qwerty = tester.getRect(find.byKey(const Key('initial-b')));

      await tap(tester, 'arrangement');
      final grouped = tester.getRect(find.byKey(const Key('initial-b')));
      expect(grouped, isNot(qwerty), reason: 'b did not move');

      await tap(tester, 'arrangement');
      expect(tester.getRect(find.byKey(const Key('initial-b'))), qwerty);
    });

    // Both banks must be fully usable without scrolling: a key you have to
    // scroll to is a key that moves, and one that is easy to miss entirely.
    testWidgets('every key is reachable on a phone, in either', (tester) async {
      await pump(tester);

      for (final arrangement in KeyArrangement.values) {
        for (final row in initialRows(arrangement)) {
          for (final key in row) {
            final finder = find.byKey(Key('initial-${key.label}'));
            expect(finder, findsOneWidget, reason: '${key.label} missing');

            final rect = tester.getRect(finder);
            expect(
              rect.bottom,
              lessThanOrEqualTo(812),
              reason: '${key.label} is below the fold in $arrangement',
            );
            expect(
              rect.right,
              lessThanOrEqualTo(375),
              reason: '${key.label} runs off the edge in $arrangement',
            );
            // Narrow is fine for a dense keyboard: a ten-across row on a
            // 375pt screen is about 30pt, which is what iOS's own top row
            // gives. A collapse below that is not.
            expect(rect.width, greaterThanOrEqualTo(28), reason: key.label);
            expect(rect.height, greaterThanOrEqualTo(44), reason: key.label);
          }
        }
        await tap(tester, 'arrangement');
      }
    });

    // A digraph is one sound. If its key wraps, it reads as two letters, which
    // is exactly the confusion this app should not be creating.
    testWidgets('digraph keys stay on one line at phone width', (tester) async {
      await pump(tester);

      double labelHeight(String label) => tester
          .getRect(
            find.descendant(
              of: find.byKey(Key('initial-$label')),
              matching: find.byType(Text),
            ),
          )
          .height;

      final oneLine = labelHeight('z');
      for (final digraph in ['zh', 'ch', 'sh']) {
        expect(
          labelHeight(digraph),
          lessThanOrEqualTo(oneLine),
          reason: '$digraph wrapped onto a second line',
        );
      }
    });

    testWidgets('switching mid-syllable does not disturb the draft', (
      tester,
    ) async {
      await pump(tester);

      await tap(tester, 'initial-n');
      await tap(tester, 'arrangement');
      // Still on the rime bank, still under n.
      expect(find.text('then what follows it'), findsOneWidget);
      await tap(tester, 'rime-i');
      await tap(tester, 'tone-3');
      expect(composed(tester), 'nǐ');
    });
  });

  group('layout', () {
    Rect keyboard(WidgetTester tester) =>
        tester.getRect(find.byType(PinyinKeyboard));

    // The keyboard is anchored to the bottom edge and only as tall as the stage
    // on show, so everything left over goes to what has been typed.
    testWidgets('portrait pins the keyboard to the bottom, height per stage', (
      tester,
    ) async {
      await pump(tester);

      final heights = <double>[];
      for (final step in [null, 'initial-n', 'rime-i']) {
        if (step != null) await tap(tester, step);
        expect(
          keyboard(tester).bottom,
          moreOrLessEquals(812, epsilon: 1),
          reason: 'came away from the bottom edge at ${step ?? "the start"}',
        );
        expect(keyboard(tester).width, moreOrLessEquals(375, epsilon: 1));
        heights.add(keyboard(tester).height);
      }

      // Fluid, not fixed: the three stages need different amounts of room.
      expect(heights.toSet().length, greaterThan(1), reason: '$heights');
      // And none of them may swallow the screen.
      for (final height in heights) {
        expect(height, lessThanOrEqualTo(812 * 0.75 + 1));
      }
    });

    testWidgets('landscape puts a full-height panel down the right', (
      tester,
    ) async {
      await pump(tester, size: const Size(812, 375));

      final panel = keyboard(tester);
      expect(panel.right, moreOrLessEquals(812, epsilon: 1));
      expect(panel.bottom, moreOrLessEquals(375, epsilon: 1));
      // Full height, below the app bar.
      expect(panel.top, lessThan(60));
      // A panel, not the whole screen.
      expect(panel.left, greaterThan(812 * 0.3));
      expect(panel.width, lessThanOrEqualTo(812 * 0.5 + 1));

      // The controls travel with it rather than staying on the main area.
      expect(
        tester.getRect(find.byKey(const Key('space'))).left,
        greaterThanOrEqualTo(panel.left),
      );
    });

    // Only the default arrangement is held to this. Articulation order's seven
    // short rows need about 400pt of height, and a landscape phone leaves 319
    // under the app bar, so it scrolls there — the price of grouping by sound
    // rather than by keyboard shape.
    testWidgets('every key stays reachable in landscape', (tester) async {
      await pump(tester, size: const Size(812, 375));

      for (final row in initialRows(KeyArrangement.qwerty)) {
        for (final initial in row) {
          final rect = tester.getRect(
            find.byKey(Key('initial-${initial.label}')),
          );
          expect(rect.right, lessThanOrEqualTo(812), reason: initial.label);
          expect(rect.bottom, lessThanOrEqualTo(375), reason: initial.label);
          expect(rect.width, greaterThanOrEqualTo(26), reason: initial.label);
        }
      }
    });
  });

  // The plus is the mnemonic: reaching for "the falling one" means reaching
  // down, rather than counting to the fourth item in a row.
  group('the tone grid', () {
    Rect toneKey(WidgetTester tester, int tone) =>
        tester.getRect(find.byKey(Key('tone-$tone')));

    /// Reaches the tone stage. Takes the rime because landscape's rime bank
    /// scrolls, and a tap on a key below the fold silently misses.
    Future<void> openToneStage(WidgetTester tester, {String rime = 'i'}) async {
      await tap(tester, 'initial-n');
      await tap(tester, 'rime-$rime');
    }

    testWidgets('lays the five tones out in the shape of their pitch', (
      tester,
    ) async {
      await pump(tester);
      await openToneStage(tester);

      final dipping = toneKey(tester, 3).center;

      expect(
        toneKey(tester, 2).center.dy,
        lessThan(dipping.dy),
        reason: 'the rising tone is not above',
      );
      expect(
        toneKey(tester, 4).center.dy,
        greaterThan(dipping.dy),
        reason: 'the falling tone is not below',
      );
      expect(
        toneKey(tester, 1).center.dx,
        lessThan(dipping.dx),
        reason: 'the level tone is not to the left',
      );
      expect(
        toneKey(tester, 5).center.dx,
        greaterThan(dipping.dx),
        reason: 'the neutral tone is not to the right',
      );

      // Rising and falling share the middle column; level and neutral share
      // the middle row. Otherwise it is a scatter, not a plus.
      for (final tone in [2, 4]) {
        expect(toneKey(tester, tone).center.dx, moreOrLessEquals(dipping.dx));
      }
      for (final tone in [1, 5]) {
        expect(toneKey(tester, tone).center.dy, moreOrLessEquals(dipping.dy));
      }
    });

    // These keys were allowed up to 104pt against a 52pt letter key, which read
    // as a different kind of control rather than a bigger one.
    testWidgets('stays close in size to the other keys', (tester) async {
      await pump(tester);
      final letter = tester.getRect(find.byKey(const Key('initial-n')));

      await openToneStage(tester);
      final tone = toneKey(tester, 3);

      expect(
        tone.height,
        greaterThanOrEqualTo(letter.height),
        reason: 'the committing keys should not be the smallest ones',
      );
      expect(
        tone.height,
        lessThanOrEqualTo(letter.height * 1.4),
        reason: 'tone ${tone.height} against letter ${letter.height}',
      );
      expect(tone.width, lessThanOrEqualTo(letter.height * 1.4));
    });

    testWidgets('sits centred in the keyboard', (tester) async {
      await pump(tester);
      await openToneStage(tester);

      final panel = tester.getRect(find.byType(PinyinKeyboard));
      expect(
        toneKey(tester, 3).center.dx,
        moreOrLessEquals(panel.center.dx, epsilon: 1),
      );
    });

    // The falling tone was falling off the bottom of the landscape panel: the
    // grid was inside a scroll view, so it sized its cells from the width alone
    // and asked for more height than a landscape phone has.
    testWidgets('fits the landscape panel, all five of it', (tester) async {
      await pump(tester, size: const Size(812, 375));
      await openToneStage(tester, rime: 'a');

      final panel = tester.getRect(find.byType(PinyinKeyboard));
      for (var tone = 1; tone <= 5; tone++) {
        final rect = toneKey(tester, tone);
        expect(
          rect.bottom,
          lessThanOrEqualTo(panel.bottom),
          reason: 'tone $tone runs below the panel',
        );
        expect(rect.top, greaterThanOrEqualTo(panel.top), reason: 'tone $tone');
        expect(
          rect.left,
          greaterThanOrEqualTo(panel.left),
          reason: 'tone $tone',
        );
        expect(
          rect.right,
          lessThanOrEqualTo(panel.right),
          reason: 'tone $tone',
        );
        // Still a usable target after shrinking to fit.
        expect(rect.width, greaterThanOrEqualTo(44), reason: 'tone $tone');
      }
    });

    testWidgets('still commits the right tone', (tester) async {
      await pump(tester);
      await openToneStage(tester);
      await tap(tester, 'tone-4');
      expect(composed(tester), 'nì');
    });
  });

  // Pressing space and then starting the next syllable looked exactly like
  // forgetting to press space, because a trailing space renders as nothing.
  group('the caret', () {
    testWidgets('marks the end of what has been typed', (tester) async {
      await pump(tester);
      // Nothing typed yet, so the prompt has the space instead.
      expect(find.byType(BlinkingCursor), findsNothing);

      await type(tester, 'w', 'o', 3);
      expect(find.byType(BlinkingCursor), findsOneWidget);
    });

    testWidgets('shows the space once a word break is pending', (tester) async {
      await pump(tester);
      await type(tester, 'w', 'o', 3);
      expect(composed(tester), 'wǒ');

      await tap(tester, 'space');
      expect(
        composed(tester),
        'wǒ ',
        reason: 'the pending break is not drawn, so wǒài looks like wǒ ài',
      );

      // And it is not drawn twice once the next syllable starts.
      await tap(tester, 'initial-a');
      await tap(tester, 'rime-ai');
      expect(composed(tester), 'wǒ ai');
    });

    testWidgets('backspacing the break takes the space with it', (
      tester,
    ) async {
      await pump(tester);
      await type(tester, 'w', 'o', 3);
      await tap(tester, 'space');
      expect(composed(tester), 'wǒ ');

      await tap(tester, 'backspace');
      expect(composed(tester), 'wǒ');
    });

    testWidgets('blinks', (tester) async {
      // The one test that lets it run, so pumpAndSettle is off limits here.
      BlinkingCursor.debugStatic = false;
      await pump(tester);
      for (final id in ['initial-n', 'rime-i', 'tone-3']) {
        await tester.tap(find.byKey(Key(id)));
        await tester.pump(const Duration(milliseconds: 16));
      }

      double opacity() => tester
          .widget<Opacity>(
            find
                .descendant(
                  of: find.byType(BlinkingCursor),
                  matching: find.byType(Opacity),
                )
                .first,
          )
          .opacity;

      final shown = opacity();
      await tester.pump(const Duration(milliseconds: 600));
      expect(opacity(), isNot(shown), reason: 'the caret never went off');
      await tester.pump(const Duration(milliseconds: 600));
      expect(opacity(), shown, reason: 'the caret never came back');
    });
  });

  // Reading a dictionary shard costs 1-24ms from local assets, but over the
  // web it is an HTTP fetch with no upper bound.
  group('a slow lookup', () {
    testWidgets('goes unmentioned when it is quick', (tester) async {
      final translator = _SlowTranslator();
      await pump(tester, translator: translator);

      await tester.tap(find.byKey(const Key('initial-n')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('rime-i')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('tone-3')));
      await tester.pump(const Duration(milliseconds: 50));

      // Faster than the threshold, so nothing should have flashed up.
      expect(find.byKey(const Key('looking-up')), findsNothing);
      translator.pending!.complete(const Translation('you'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('looking-up')), findsNothing);
      expect(find.text('you'), findsOneWidget);
    });

    testWidgets('says so once it drags on', (tester) async {
      final translator = _SlowTranslator();
      await pump(tester, translator: translator);

      await tester.tap(find.byKey(const Key('initial-n')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('rime-i')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('tone-3')));
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.byKey(const Key('looking-up')), findsOneWidget);
      // The pinyin is still readable while it waits.
      expect(composed(tester), 'nǐ');

      translator.pending!.complete(const Translation('you'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('looking-up')), findsNothing);
      expect(find.text('you'), findsOneWidget);
    });

    testWidgets('stops saying so if the answer is nothing', (tester) async {
      final translator = _SlowTranslator();
      await pump(tester, translator: translator);

      await tester.tap(find.byKey(const Key('initial-n')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('rime-i')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('tone-3')));
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byKey(const Key('looking-up')), findsOneWidget);

      translator.pending!.complete(null);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('looking-up')), findsNothing);
    });

    testWidgets('leaves no timer running when the screen goes away', (
      tester,
    ) async {
      final translator = _SlowTranslator();
      await pump(tester, translator: translator);

      await tester.tap(find.byKey(const Key('initial-n')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('rime-i')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('tone-3')));
      await tester.pump();

      // Replacing the screen mid-lookup: a pending timer would fail the test.
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(milliseconds: 500));
      translator.pending!.complete(const Translation('you'));
      await tester.pumpAndSettle();
    });
  });

  // A keyboard whose keys move while you use it is worse than a cramped one.
  testWidgets('the keys do not move as text is composed', (tester) async {
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

  // A fourth action went into the app bar for the model screen. Four buttons
  // plus the title is where an app bar starts to overflow on a small phone.
  testWidgets('the app bar fits its actions on a narrow screen', (
    tester,
  ) async {
    await pump(tester, size: const Size(320, 568));

    for (final id in ['model', 'arrangement', 'credits', 'clear']) {
      final rect = tester.getRect(find.byKey(Key(id)));
      expect(rect.right, lessThanOrEqualTo(320), reason: id);
      expect(rect.left, greaterThanOrEqualTo(0), reason: id);
    }
    expect(find.text('Kǒuyǔ'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the model button opens the model screen', (tester) async {
    await pump(tester);
    await tester.tap(find.byKey(const Key('model')));
    await tester.pumpAndSettle();

    expect(find.text('Whole phrases'), findsOneWidget);
    expect(find.byKey(const Key('model-status')), findsOneWidget);
  });

  testWidgets('renders in both light and dark themes', (tester) async {
    for (final brightness in Brightness.values) {
      await pump(tester, brightness: brightness);
      await type(tester, 'n', 'i', 3);
      expect(tester.takeException(), isNull);
    }
  });
}
