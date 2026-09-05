import 'package:flutter_test/flutter_test.dart';
import 'package:kouyu/pinyin/syllable.dart';
import 'package:kouyu/pinyin/tone.dart';
import 'package:kouyu/translation/dictionary.dart';
import 'package:kouyu/translation/dictionary_translator.dart';
import 'package:kouyu/translation/translator.dart';

Syllable syllable(String initial, String rime, Tone tone) =>
    Syllable(initial: initial, rime: rime, tone: tone);

/// A stand-in for the sharded assets, so these tests do not depend on the
/// 109,000-entry build.
Dictionary fakeDictionary(Map<String, List<String>> shards) => Dictionary(
  loadShard: (letter) async {
    final rows = shards[letter];
    if (rows == null) throw Exception('no shard $letter');
    return rows.join('\n');
  },
);

void main() {
  final dictionary = fakeDictionary({
    'n': [
      'ni3\t你\t-\tyou',
      'ni3\t拟\t-\tto plan to/to draft',
      'ni3 hao3\t你好\t-\thello; hi',
      'nu:3\t女\t-\tfemale/woman/daughter',
    ],
    'h': ['hao3\t好\t-\tgood/appropriate'],
    's': [
      'shi4 jie4\t世界\t-\tworld',
      'shi4\t是\t-\tto be',
      'shi4\t世\t-\tlife/age',
      'shi4\t視界報\tp\ta newspaper',
    ],
  });

  group('the dictionary', () {
    test('finds a word by its tone-numbered key', () async {
      final entries = await dictionary.lookUp('ni3 hao3');
      expect(entries.single.glosses, ['hello; hi']);
      expect(entries.single.simplified, '你好');
    });

    // The ü key is written `u:` in CC-CEDICT, and the syllable model emits it.
    test('keys ü as u:', () async {
      expect(syllable('n', 'ü', Tone.third).numbered, 'nu:3');
      final entries = await dictionary.lookUp('nu:3');
      expect(entries.single.glosses.first, 'female');
    });

    test('returns every homophone, names last', () async {
      final entries = await dictionary.lookUp('shi4');
      expect(entries.length, 3);
      expect(
        entries.last.properNoun,
        isTrue,
        reason: 'a newspaper should not outrank a verb',
      );
    });

    test('has nothing for a key that is not a word', () async {
      expect(await dictionary.lookUp('ni3 zzz9'), isEmpty);
      expect(await dictionary.lookUp(''), isEmpty);
    });

    // Pinyin never starts a syllable with i, u or v, so those shards are not
    // built and asking for one must not throw.
    test('survives a missing shard', () async {
      expect(await dictionary.lookUp('vvv1'), isEmpty);
    });

    // A missing Flutter asset raises FlutterError, which is an Error rather
    // than an Exception, so catching Exception alone let it escape.
    test('survives a loader that raises an Error, not an Exception', () async {
      final broken = Dictionary(
        loadShard: (letter) async => throw AssertionError('Unable to load'),
      );
      expect(await broken.lookUp('ni3'), isEmpty);
    });

    test('reads each shard once', () async {
      var reads = 0;
      final counted = Dictionary(
        loadShard: (letter) async {
          reads++;
          return 'ni3\t你\t-\tyou';
        },
      );
      await counted.lookUp('ni3');
      await counted.lookUp('ni3');
      await counted.lookUp('nu:3');
      expect(reads, 1);
    });
  });

  group('the dictionary translator', () {
    final translator = DictionaryTranslator(dictionary);

    test('translates a word, spacing or none', () async {
      // shìjiè typed as one word.
      final oneWord = TranslationRequest([
        [syllable('sh', 'i', Tone.fourth), syllable('j', 'ie', Tone.fourth)],
      ]);
      expect(await translator.translate(oneWord), const Translation('world'));

      // And typed as two, which is still one dictionary entry.
      final twoWords = TranslationRequest([
        [syllable('sh', 'i', Tone.fourth)],
        [syllable('j', 'ie', Tone.fourth)],
      ]);
      expect(await translator.translate(twoWords), const Translation('world'));
    });

    test(
      'glosses word by word when the whole phrase is not an entry',
      () async {
        final request = TranslationRequest([
          [syllable('h', 'ao', Tone.third)],
          [syllable('h', 'ao', Tone.third)],
        ]);
        final result = await translator.translate(request);
        expect(result!.text, 'good · good');
        expect(result.wordByWord, isTrue);
      },
    );

    // Only 17% of one-syllable keys are a single word, so saying which one it
    // is would usually be a guess dressed up as an answer.
    test(
      'offers candidates, and admits to it, when the pinyin is ambiguous',
      () async {
        final request = TranslationRequest([
          [syllable('sh', 'i', Tone.fourth)],
        ]);
        final result = await translator.translate(request);
        expect(result!.uncertain, isTrue);
        expect(result.text, 'to be / life / a newspaper');
      },
    );

    test('is certain when the pinyin is unambiguous', () async {
      final request = TranslationRequest([
        [syllable('sh', 'i', Tone.fourth), syllable('j', 'ie', Tone.fourth)],
      ]);
      expect((await translator.translate(request))!.uncertain, isFalse);
    });

    test('gives up rather than glossing half a phrase', () async {
      final request = TranslationRequest([
        [syllable('n', 'i', Tone.third)],
        [syllable('z', 'ai', Tone.fourth)],
      ]);
      expect(await translator.translate(request), isNull);
    });

    test('has nothing to say about empty input', () async {
      expect(await translator.translate(const TranslationRequest([])), isNull);
    });
  });

  group('the composite', () {
    test('takes the first answer offered', () async {
      final request = TranslationRequest([
        [syllable('n', 'i', Tone.third)],
      ]);
      final chain = CompositeTranslator([
        DictionaryTranslator(fakeDictionary({})),
        DictionaryTranslator(dictionary),
      ]);
      final result = await chain.translate(request);
      expect(result!.text, 'you / to plan to');
    });

    test('returns null when nobody has an answer', () async {
      final chain = CompositeTranslator([
        DictionaryTranslator(fakeDictionary({})),
      ]);
      expect(
        await chain.translate(
          TranslationRequest([
            [syllable('n', 'i', Tone.third)],
          ]),
        ),
        isNull,
      );
    });
  });
}
