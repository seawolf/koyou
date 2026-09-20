import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kouyu/pinyin/syllable.dart';
import 'package:kouyu/pinyin/tone.dart';
import 'package:kouyu/pinyin/word.dart';
import 'package:kouyu/screens/translate_screen.dart';
import 'package:kouyu/theme.dart';
import 'package:kouyu/translation/english_translator.dart';
import 'package:kouyu/translation/model_asset.dart';
import 'package:kouyu/translation/model_store.dart';

Syllable _syllable(String initial, String rime, Tone tone) =>
    Syllable(initial: initial, rime: rime, tone: tone);

/// `chá` — tea, the one-word answer these tests ask for.
final _cha = Spoken([_syllable('ch', 'a', Tone.second)]);

/// `wǒ ài nǐ`, as three words.
final _iLoveYou = [
  Spoken([_syllable('w', 'o', Tone.third)]),
  Spoken([_syllable('', 'ai', Tone.fourth)]),
  Spoken([_syllable('n', 'i', Tone.third)]),
];

/// Answers whatever it was given, after however long it was told to take.
class _Canned implements EnglishTranslator {
  _Canned(this.answers, {this.delay = Duration.zero});

  final Map<String, Said> answers;
  final Duration delay;
  final List<String> asked = [];

  @override
  Future<Said?> say(String english) async {
    asked.add(english);
    if (delay != Duration.zero) await Future<void>.delayed(delay);
    return answers[english];
  }
}

/// Reports one state and does nothing else.
class _Store implements ModelStore {
  _Store(ModelState state) : status = ValueNotifier(ModelStatus(state));

  @override
  final ModelAsset asset = ModelAsset.qwen08b;

  @override
  final ValueNotifier<ModelStatus> status;

  @override
  Future<void> download() async {}
  @override
  void cancel() {}
  @override
  Future<void> remove() async {}
  @override
  Future<void> setEnabled(bool enabled) async {}
  @override
  void dispose() => status.dispose();
}

Said _word(List<Word> words, {String? meaning, int? hskLevel}) => Said(
  options: [Rendering(words: words, meaning: meaning, hskLevel: hskLevel)],
  phrasing: Phrasing.entry,
);

/// Pushes the screen from a host route, so popping has somewhere to go, and
/// reports what it popped with.
Future<List<Word>?> _show(
  WidgetTester tester, {
  required EnglishTranslator translator,
  EnglishTranslator? phrases,
  ModelStore? store,
  String? initial,
  ThemeData? theme,
}) async {
  final popped = <List<Word>?>[];
  await tester.pumpWidget(
    MaterialApp(
      theme: theme ?? kLightTheme,
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () async {
                popped.add(
                  await Navigator.of(context).push<List<Word>>(
                    MaterialPageRoute<List<Word>>(
                      builder: (context) => TranslateScreen(
                        translator: translator,
                        phraseTranslator: phrases,
                        modelStore: store,
                        initial: initial,
                      ),
                    ),
                  ),
                );
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  _popped = popped;
  return null;
}

/// What the route above came back with, once it has been popped.
List<List<Word>?> _popped = [];

List<Word>? get _answer => _popped.isEmpty ? null : _popped.single;

/// Types something and asks for it, which is now two separate acts.
Future<void> _askFor(WidgetTester tester, String text) async {
  await tester.enterText(find.byKey(const Key('english')), text);
  await tester.pump();
  await tester.tap(find.byKey(const Key('translate-it')));
  await _waitForTheModel(tester);
}

/// Long enough for a slow translator to answer.
///
/// Explicit pumps rather than `pumpAndSettle`, which stops as soon as no
/// frame is scheduled and so never reaches a pending future.
Future<void> _waitForTheModel(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(seconds: 1));
  await tester.pump(const Duration(seconds: 2));
  await tester.pump();
}

void main() {
  testWidgets('says what it can do before it is asked', (tester) async {
    await _show(tester, translator: _Canned(const {}));
    expect(find.byKey(const Key('about')), findsOne);
    expect(find.byKey(const Key('pinyin')), findsNothing);
  });

  testWidgets('says it does words only without a model', (tester) async {
    await _show(tester, translator: _Canned(const {}));
    expect(
      tester.widget<Text>(find.byKey(const Key('about'))).data,
      contains('Turn on whole phrases'),
    );
  });

  testWidgets('looks nothing up until it is asked', (tester) async {
    // The reason the button exists. A phone keyboard offers corrections and
    // completions while a sentence is half written, and looking up every
    // intermediate state both fights that and wakes the model for a sentence
    // nobody has finished.
    final dictionary = _Canned({
      'tea': _word([_cha]),
    });
    final phrases = _Canned(const {});
    await _show(tester, translator: dictionary, phrases: phrases);

    await tester.enterText(find.byKey(const Key('english')), 't');
    await tester.pump();
    await tester.enterText(find.byKey(const Key('english')), 'te');
    await tester.pump();
    await tester.enterText(find.byKey(const Key('english')), 'tea');
    await _waitForTheModel(tester);

    expect(dictionary.asked, isEmpty);
    expect(phrases.asked, isEmpty);
    expect(find.byKey(const Key('pinyin')), findsNothing);

    await tester.tap(find.byKey(const Key('translate-it')));
    await _waitForTheModel(tester);
    expect(dictionary.asked, ['tea']);
    expect(find.text('chá'), findsOne);
  });

  testWidgets('the button is off until there is something to ask', (
    tester,
  ) async {
    await _show(
      tester,
      translator: _Canned({
        'tea': _word([_cha]),
      }),
    );
    Finder button() => find.byKey(const Key('translate-it'));
    expect(tester.widget<FilledButton>(button()).onPressed, isNull);

    await tester.enterText(find.byKey(const Key('english')), 'tea');
    await tester.pump();
    expect(tester.widget<FilledButton>(button()).onPressed, isNotNull);

    // And off again once that question has been answered, so the model is not
    // asked the same thing twice.
    await tester.tap(button());
    await _waitForTheModel(tester);
    expect(tester.widget<FilledButton>(button()).onPressed, isNull);
  });

  testWidgets('the keyboard can ask, without reaching for the button', (
    tester,
  ) async {
    final dictionary = _Canned({
      'tea': _word([_cha]),
    });
    await _show(tester, translator: dictionary);
    await tester.enterText(find.byKey(const Key('english')), 'tea');
    await tester.testTextInput.receiveAction(TextInputAction.go);
    await _waitForTheModel(tester);
    expect(find.text('chá'), findsOne);
  });

  testWidgets('an answer does not outlive the question', (tester) async {
    await _show(
      tester,
      translator: _Canned({
        'tea': _word([_cha]),
      }),
    );
    await _askFor(tester, 'tea');
    expect(find.text('chá'), findsOne);

    // Edit the box and what is on screen is about something else, which is
    // worse than showing nothing.
    await tester.enterText(find.byKey(const Key('english')), 'teapot');
    await tester.pump();
    expect(find.text('chá'), findsNothing);
    expect(find.byKey(const Key('about')), findsOne);
  });

  testWidgets('opens with what it was handed, ready to be typed over', (
    tester,
  ) async {
    await _show(
      tester,
      translator: _Canned({
        'tea': _word([_cha]),
      }),
      initial: 'hello',
    );
    final field = tester.widget<TextField>(find.byKey(const Key('english')));
    expect(field.controller!.text, 'hello');
    // Selected, so replacing it is one keystroke rather than five backspaces.
    expect(field.controller!.selection.baseOffset, 0);
    expect(field.controller!.selection.extentOffset, 5);
    // A suggestion, not a submission: nothing has been looked up.
    expect(find.byKey(const Key('about')), findsOne);
  });

  testWidgets('answers a word when asked', (tester) async {
    final dictionary = _Canned({
      'tea': _word([_cha], meaning: 'the drink'),
    });
    await _show(tester, translator: dictionary);
    await _askFor(tester, 'tea');

    expect(find.text('chá'), findsOne);
    expect(find.text('the drink'), findsOne);
    expect(dictionary.asked, ['tea']);
  });

  testWidgets('asks about the text, not the whitespace', (tester) async {
    await _show(
      tester,
      translator: _Canned({
        'tea': _word([_cha]),
      }),
    );
    await _askFor(tester, '  tea  ');
    expect(find.text('chá'), findsOne);
  });

  testWidgets('offers the candidates where there are several', (tester) async {
    final hot = Said(
      options: [
        Rendering(words: [_cha], meaning: 'hot (of weather)'),
        Rendering(words: _iLoveYou, meaning: 'hot (spicy)'),
      ],
      phrasing: Phrasing.entry,
    );
    await _show(tester, translator: _Canned({'hot': hot}));
    await _askFor(tester, 'hot');

    expect(find.byKey(const Key('pinyin')), findsExactly(2));
    expect(find.byKey(const Key('ambiguous')), findsOne);
    // The first is chosen until somebody says otherwise.
    expect(find.byIcon(Icons.radio_button_checked), findsOne);
  });

  testWidgets('practises the candidate that was picked', (tester) async {
    final hot = Said(
      options: [
        Rendering(words: [_cha]),
        Rendering(words: _iLoveYou),
      ],
      phrasing: Phrasing.entry,
    );
    await _show(tester, translator: _Canned({'hot': hot}));
    await _askFor(tester, 'hot');

    await tester.tap(find.byKey(const Key('pinyin')).last);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('practise')));
    await tester.pumpAndSettle();

    expect(_answer, _iLoveYou);
  });

  testWidgets('hands the answer back to be practised', (tester) async {
    await _show(
      tester,
      translator: _Canned({
        'tea': _word([_cha]),
      }),
    );
    await _askFor(tester, 'tea');
    await tester.tap(find.byKey(const Key('practise')));
    await tester.pumpAndSettle();

    // Words, not text. The whole point: it lands in the input area already
    // broken into syllables, with nothing to parse.
    expect(_answer, isNotNull);
    expect(_answer!.single, _cha);
  });

  testWidgets('shows the round trip on a generated answer', (tester) async {
    final phrases = _Canned({
      'I love you': Said(
        options: [Rendering(words: _iLoveYou)],
        phrasing: Phrasing.generated,
        readsBackAs: 'I love you',
      ),
    });
    await _show(tester, translator: _Canned(const {}), phrases: phrases);
    await _askFor(tester, 'I love you');

    expect(find.text('wǒ ài nǐ'), findsOne);
    expect(
      tester.widget<Text>(find.byKey(const Key('reads-back'))).data,
      'Reads back as: I love you',
    );
  });

  testWidgets('says so when the round trip could not be made', (tester) async {
    final phrases = _Canned({
      'I love you': Said(
        options: [Rendering(words: _iLoveYou)],
        phrasing: Phrasing.generated,
      ),
    });
    await _show(tester, translator: _Canned(const {}), phrases: phrases);
    await _askFor(tester, 'I love you');
    expect(
      tester.widget<Text>(find.byKey(const Key('reads-back'))).data,
      contains('not checked back'),
    );
  });

  testWidgets('does not wake the model for a word it knows', (tester) async {
    final phrases = _Canned(const {});
    await _show(
      tester,
      translator: _Canned({
        'tea': _word([_cha]),
      }),
      phrases: phrases,
    );
    await _askFor(tester, 'tea');
    // An entry beats a paraphrase of it, so there is nothing to gain by
    // spending a second of a phone's CPU on one.
    expect(phrases.asked, isEmpty);
  });

  testWidgets('says it is working while the model is', (tester) async {
    final phrases = _Canned({
      'I love you': Said(
        options: [Rendering(words: _iLoveYou)],
        phrasing: Phrasing.generated,
      ),
    }, delay: const Duration(seconds: 1));
    await _show(tester, translator: _Canned(const {}), phrases: phrases);

    await tester.enterText(find.byKey(const Key('english')), 'I love you');
    await tester.pump();
    await tester.tap(find.byKey(const Key('translate-it')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byKey(const Key('thinking')), findsOne);

    await _waitForTheModel(tester);
    expect(find.byKey(const Key('thinking')), findsNothing);
    expect(find.text('wǒ ài nǐ'), findsOne);
  });

  testWidgets('says plainly when there is no answer', (tester) async {
    await _show(tester, translator: _Canned(const {}));
    await _askFor(tester, 'antidisestab');
    expect(find.byKey(const Key('nothing')), findsOne);
  });

  testWidgets('a slow answer cannot land on a later question', (tester) async {
    // Asking, editing, and asking again while the first is still running.
    final slow = _Canned({
      'tea': _word([_cha]),
    }, delay: const Duration(seconds: 1));
    await _show(tester, translator: slow);

    await tester.enterText(find.byKey(const Key('english')), 'tea');
    await tester.pump();
    await tester.tap(find.byKey(const Key('translate-it')));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.enterText(find.byKey(const Key('english')), 'teapot');
    await tester.pump();
    await tester.tap(find.byKey(const Key('translate-it')));
    await _waitForTheModel(tester);

    expect(find.text('chá'), findsNothing);
    expect(find.byKey(const Key('nothing')), findsOne);
  });

  testWidgets('clears back to the explanation', (tester) async {
    await _show(
      tester,
      translator: _Canned({
        'tea': _word([_cha]),
      }),
    );
    await _askFor(tester, 'tea');
    await tester.tap(find.byKey(const Key('clear-english')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('about')), findsOne);
    expect(find.byKey(const Key('pinyin')), findsNothing);
  });

  // The model tier is always constructed and declines at run time, so a screen
  // that went by whether it exists would promise sentences to everybody,
  // including whoever has not downloaded 533MB.
  testWidgets('promises sentences only once the weights are there', (
    tester,
  ) async {
    await _show(
      tester,
      translator: _Canned(const {}),
      phrases: _Canned(const {}),
      store: _Store(ModelState.ready),
    );
    expect(
      tester.widget<Text>(find.byKey(const Key('about'))).data,
      contains('sentences from the model'),
    );
  });

  testWidgets('says it does words only until they are', (tester) async {
    await _show(
      tester,
      translator: _Canned(const {}),
      phrases: _Canned(const {}),
      store: _Store(ModelState.absent),
    );
    expect(
      tester.widget<Text>(find.byKey(const Key('about'))).data,
      contains('Turn on whole phrases'),
    );
  });

  testWidgets('renders in both light and dark themes', (tester) async {
    for (final theme in [kLightTheme, kDarkTheme]) {
      await tester.pumpWidget(
        MaterialApp(
          key: ValueKey(theme.brightness),
          theme: theme,
          home: TranslateScreen(
            translator: _Canned({
              'tea': _word([_cha], meaning: 'the drink'),
            }),
          ),
        ),
      );
      await _askFor(tester, 'tea');
      expect(tester.takeException(), isNull);
      expect(find.text('chá'), findsOne);
    }
  });
}
