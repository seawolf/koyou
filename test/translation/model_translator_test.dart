import 'package:flutter_test/flutter_test.dart';
import 'package:kouyu/pinyin/syllable.dart';
import 'package:kouyu/pinyin/word.dart';
import 'package:kouyu/pinyin/tone.dart';
import 'package:kouyu/translation/dictionary.dart';
import 'package:kouyu/translation/model_translator.dart';
import 'package:kouyu/translation/translation_backend.dart';
import 'package:kouyu/translation/translator.dart';

/// Records what it was asked, so the tests can assert on the characters the
/// dictionary resolved rather than on a model's wording.
class _Spy implements TranslationBackend {
  _Spy([this.reply = 'some English']);

  final String? reply;
  String? asked;

  @override
  Future<String?> translate(String chinese) async {
    asked = chinese;
    return reply;
  }
}

Syllable _syllable(String initial, String rime, Tone tone) =>
    Syllable(initial: initial, rime: rime, tone: tone);

/// `wǒ` — the one syllable every example below starts with.
final _wo = _syllable('w', 'o', Tone.third);

void main() {
  late Dictionary dictionary;

  setUp(() {
    // A stand-in shard, so these tests describe behaviour rather than the
    // contents of CC-CEDICT. Real data is covered by bundled_dictionary_test.
    dictionary = Dictionary(
      loadShard: (letter) async => switch (letter) {
        'w' => 'wo3\t我\t-\t3\t1\tI; me\n',
        'm' =>
          'mai3\t买\t-\t500\t1\tto buy\n'
              'mai4\t卖\t-\t600\t1\tto sell\n',
        's' => 'shu1\t书\t-\t560\t1\tbook\n',
        _ => throw AssertionError('no shard $letter'),
      },
    );
  });

  TranslationRequest request(List<Word> words) => TranslationRequest(words);

  test('a single word is left to the dictionary', () async {
    final spy = _Spy();
    final translator = ModelTranslator(dictionary: dictionary, backend: spy);

    expect(
      await translator.translate(
        request([
          Spoken([_wo]),
        ]),
      ),
      isNull,
    );
    expect(spy.asked, isNull, reason: 'the backend should not be troubled');
  });

  test(
    'a phrase is resolved to characters before the backend sees it',
    () async {
      final spy = _Spy('I sell books.');
      final translator = ModelTranslator(dictionary: dictionary, backend: spy);

      final result = await translator.translate(
        request([
          Spoken([_wo]),
          Spoken([_syllable('m', 'ai', Tone.fourth)]),
          Spoken([_syllable('sh', 'u', Tone.first)]),
        ]),
      );

      expect(spy.asked, '我卖书');
      expect(result?.text, 'I sell books.');
      // The model is answering a whole phrase, so neither label applies.
      expect(result?.wordByWord, isFalse);
      expect(result?.uncertain, isFalse);
      expect(result?.hskLevel, isNull);
    },
  );

  // The reason this layer exists at all: the tone has to survive the trip to
  // the backend, and a model handed pinyin loses it.
  test('the tone decides which character the backend is given', () async {
    final buying = _Spy();
    await ModelTranslator(dictionary: dictionary, backend: buying).translate(
      request([
        Spoken([_wo]),
        Spoken([_syllable('m', 'ai', Tone.third)]),
      ]),
    );

    final selling = _Spy();
    await ModelTranslator(dictionary: dictionary, backend: selling).translate(
      request([
        Spoken([_wo]),
        Spoken([_syllable('m', 'ai', Tone.fourth)]),
      ]),
    );

    expect(buying.asked, '我买');
    expect(selling.asked, '我卖');
  });

  // The whole point of a literal: Chinese writes foreign names in Latin
  // letters as a matter of course, so 我叫Steve is ordinary text and the model
  // needs telling nothing. Measured against the real model, it answers "My
  // name is Steve."
  test('a name goes to the backend as written', () async {
    final spy = _Spy('My name is Steve.');
    final translator = ModelTranslator(dictionary: dictionary, backend: spy);

    final result = await translator.translate(
      request([
        Spoken([_wo]),
        const Literal('Steve'),
      ]),
    );

    expect(spy.asked, '我Steve');
    expect(result?.text, 'My name is Steve.');
    // And it appears among the parts as itself, with nothing invented for it.
    expect(result?.words.last.pinyin, 'Steve');
  });

  test('a name does not make the line unresolvable', () async {
    final spy = _Spy('My name is Steve.');
    final translator = ModelTranslator(dictionary: dictionary, backend: spy);

    // mai2 is absent from the stand-in shard, so this would decline — but a
    // name must not be what causes that.
    final onlyName = await translator.translate(
      request([
        Spoken([_wo]),
        const Literal('Steve'),
      ]),
    );
    expect(onlyName, isNotNull);
  });

  // The invariant that used to be implicit. The screen once decided "this is
  // an entry for the whole line" from the absence of a word-by-word flag,
  // which a model's answer also lacks — so a model in the quick chain would
  // have outranked the dictionary it exists to defer to.
  test('never claims to have matched the whole line', () async {
    final translator = ModelTranslator(
      dictionary: dictionary,
      backend: _Spy('I sell books.'),
    );

    final result = await translator.translate(
      request([
        Spoken([_wo]),
        Spoken([_syllable('m', 'ai', Tone.fourth)]),
      ]),
    );

    expect(result?.text, 'I sell books.');
    expect(
      result?.matchedWhole,
      isFalse,
      reason: 'it generated an answer, it did not look one up',
    );
  });

  test('a word the dictionary cannot place falls through', () async {
    final spy = _Spy();
    final translator = ModelTranslator(dictionary: dictionary, backend: spy);

    final result = await translator.translate(
      request([
        Spoken([_wo]),
        Spoken([
          _syllable('m', 'ai', Tone.second),
        ]), // mai2, not in the stand-in shard
      ]),
    );

    expect(result, isNull);
    expect(spy.asked, isNull, reason: 'never translate around a hole');
  });

  test(
    'a backend with nothing to say leaves the dictionary in charge',
    () async {
      for (final reply in [null, '', '   ']) {
        final translator = ModelTranslator(
          dictionary: dictionary,
          backend: _Spy(reply),
        );
        final result = await translator.translate(
          request([
            Spoken([_wo]),
            Spoken([_syllable('m', 'ai', Tone.fourth)]),
          ]),
        );
        expect(
          result,
          isNull,
          reason: 'reply was ${reply == null ? 'null' : '"$reply"'}',
        );
      }
    },
  );
}
