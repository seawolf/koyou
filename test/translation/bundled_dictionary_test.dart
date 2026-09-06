import 'package:flutter_test/flutter_test.dart';
import 'package:kouyu/pinyin/inventory.dart';
import 'package:kouyu/pinyin/syllable.dart';
import 'package:kouyu/pinyin/tone.dart';
import 'package:kouyu/translation/dictionary.dart';
import 'package:kouyu/translation/dictionary_translator.dart';
import 'package:kouyu/translation/tone_suggestion.dart';
import 'package:kouyu/translation/translator.dart';

Syllable syllable(String initial, String rime, Tone tone) =>
    Syllable(initial: initial, rime: rime, tone: tone);

/// Checks the real generated assets, not a stand-in.
///
/// The keys are built by the syllable model and the shards by
/// `tool/build_dictionary.dart`, so nothing else proves the two agree — a
/// mistake in either would leave every lookup quietly empty.
void main() {
  // rootBundle needs the binding before it can read an asset.
  TestWidgetsFlutterBinding.ensureInitialized();

  final dictionary = Dictionary.bundled();

  test('resolves words built from the keyboard', () async {
    final expected = {
      // nǐ hǎo
      'ni3 hao3': 'hello',
      // shìjiè
      'shi4 jie4': 'world',
      // xièxie, whose second syllable is neutral
      'xie4 xie5': 'thank',
      // nǚ, which is keyed nu:3
      'nu:3': 'female',
      // zhōngguó
      'zhong1 guo2': 'China',
    };

    for (final entry in expected.entries) {
      final found = await dictionary.lookUp(entry.key);
      expect(found, isNotEmpty, reason: '${entry.key} is missing');
      expect(
        found.first.glosses.join('/'),
        contains(entry.value),
        reason: '${entry.key} gave ${found.first.glosses}',
      );
    }
  });

  test(
    'the keys the syllable model emits are the keys the shards use',
    () async {
      // shìjiè, built exactly as the keyboard builds it.
      final request = TranslationRequest([
        [syllable('sh', 'i', Tone.fourth), syllable('j', 'ie', Tone.fourth)],
      ]);
      expect(request.key, 'shi4 jie4');
      expect(request.written, 'shìjiè');

      final result = await DictionaryTranslator(dictionary).translate(request);
      expect(result, isNotNull);
      expect(result!.text, contains('world'));
    },
  );

  test('every shard the keyboard can reach exists and parses', () async {
    // Every letter a syllable can start with, per the keyboard's own layout.
    const letters = 'abcdefghjklmnopqrstwxyz';
    for (final letter in letters.split('')) {
      final entries = await Dictionary.bundled().lookUp('${letter}a1');
      // Most of these are not words; the point is that the shard loaded and
      // parsed without throwing.
      expect(entries, isA<List<DictionaryEntry>>(), reason: letter);
    }
  });

  // Each of these was wrong before the frequency data went in, and each is a
  // word a beginner types in their first lesson.
  test('offers the word a learner actually meant', () async {
    final expected = {
      'ni3': '你', // was 拟, "doubtful"
      'shi4': '是', // was 世, "life"
      'you3': '有', // was 卣, "wine container"
      'xie4': '谢', // was 亵, "obscene"
      'ai4': '爱', // was 僾, "indistinct"
      'wo3': '我',
      'hao3': '好',
      'ma5': '吗',
      'le5': '了',
      'bu4': '不',
      'ta1': '他',
      'zai4': '在',
    };

    for (final entry in expected.entries) {
      final found = await dictionary.lookUp(entry.key);
      expect(found, isNotEmpty, reason: entry.key);
      expect(
        found.first.simplified,
        entry.value,
        reason: '${entry.key} offered ${found.first.glosses.first}',
      );
    }
  });

  // The HSK source gives one frequency per word and lists every reading of it
  // underneath, so a rank credited to all of them hands the commonest word's
  // standing to its rarest reading. 的 is rank 1 as `de5` and carried that
  // into `di4`, offering "bull's-eye; target" to anyone typing dì.
  test('a rank belongs to the reading that earned it', () async {
    final byReading = {
      'di4': '地', // was 的, "(bound form) bull's-eye; target"
      'kuai4': '快', // was 会, "to reckon accounts"
      'shui4': '睡', // was 说, "to persuade"
      'la4': '辣', // was 落, "to leave out"
      'ba4': '爸', // was 把, "handle"
      'di1': '低', // was 的, "a taxi; a cab"
      // Common alone but rare inside compounds, so the HSK signal alone gave
      // 喝 to hè "to shout" and 都 to the capital city.
      'he1': '喝',
      'du1': '都',
      'chang2': '长',
      'zhi1': '只',
    };
    for (final entry in byReading.entries) {
      final found = await dictionary.lookUp(entry.key);
      expect(
        found.first.simplified,
        entry.value,
        reason: '${entry.key} offered ${found.first.glosses.first}',
      );
    }

    // 的 keeps rank 1 where it earned it, and loses it everywhere else.
    final particle = (await dictionary.lookUp('de5'))
        .firstWhere((e) => e.simplified == '的');
    expect(particle.rank, 1);
    expect(particle.hskLevel, 1);

    final bullseye = (await dictionary.lookUp('di4'))
        .firstWhere((e) => e.simplified == '的');
    expect(bullseye.rank, greaterThan(1000));
    // The band is attributed the same way, so it is not labelled HSK 1 either.
    expect(bullseye.hskLevel, isNull);
  });

  // 你 was dropped by the build entirely: its gloss is "you (informal, as
  // opposed to courteous 您[nin2])", and discarding any gloss that mentions a
  // character discarded the commonest word for "you" along with it.
  test('keeps words whose gloss merely mentions another word', () async {
    final you = await dictionary.lookUp('ni3');
    expect(you.first.simplified, '你');
    expect(you.first.glosses.first, 'you');

    final courteous = await dictionary.lookUp('nin2');
    expect(courteous.first.glosses.first, contains('you'));
  });

  test('ranks and HSK bands survive the round trip', () async {
    final beMost = (await dictionary.lookUp('shi4')).first;
    expect(beMost.rank, isNotNull);
    expect(beMost.rank, lessThan(100));
    expect(beMost.hskLevel, 1);

    // And an obscure homophone carries no rank at all.
    final obscure = (await dictionary.lookUp('shi4')).last;
    expect(obscure.rank, isNull);
  });

  // Against the real data rather than a stand-in, because the whole value of
  // the tone suggester is that it stays quiet on ordinary input, and only the
  // real frequency ranks can show that.
  group('suggesting a mistyped tone', () {
    late Suggester suggester;

    setUp(() => suggester = DictionarySuggester(dictionary));

    Future<String?> check(String written) async {
      final request = TranslationRequest([_parse(written)]);
      return (await suggester.check(request))?.written;
    }

    test('offers the word that was meant', () async {
      expect(await check('ni3 hao1'), 'nǐhǎo');
      expect(await check('zai4 jian1'), 'zàijiàn');
      expect(await check('shi4 jie2'), 'shìjiè');
      expect(await check('lao3 shi2'), 'lǎoshī');
      // 泄泻 is a real word, so this one needs the unranked signal.
      expect(await check('xie4 xie4'), 'xièxie');
    });

    test('stays quiet on ordinary input', () async {
      for (final right in [
        'ni3 hao3',
        'shi4 jie4',
        'peng2 you5',
        'xie4 xie5',
        'lao3 shi1',
        'zai4 jian4',
        'mei2 guan1 xi5',
      ]) {
        expect(await check(right), isNull, reason: right);
      }
    });

    test('stays quiet on a single syllable, however obscure', () async {
      // 呢 is rank 96 against 你 at rank 5; a ratio rule would nag here.
      for (final one in ['ni2', 'shi2', 'ma1', 'mai2', 'wo3']) {
        expect(await check(one), isNull, reason: one);
      }
    });
  });

  test('characters are carried but never the only thing offered', () async {
    final entries = await dictionary.lookUp('ni3 hao3');
    // Kept for a future translation service, which needs characters.
    expect(entries.first.simplified, isNotEmpty);
    // But there is always an English gloss to show instead.
    expect(entries.first.glosses.first, isNotEmpty);
  });
}

/// Turns `ni3 hao1` into syllables, using the inventory to split each one.
List<Syllable> _parse(String numbered) => [
  for (final part in numbered.split(' ')) _syllable(part),
];

Syllable _syllable(String part) {
  final tone = Tone.values.firstWhere(
    (tone) => tone.number == int.parse(part.substring(part.length - 1)),
  );
  final letters = part.substring(0, part.length - 1);
  for (final entry in syllableInventory.entries) {
    for (final rime in entry.value) {
      final candidate = Syllable(
        initial: entry.key,
        rime: rime,
        tone: Tone.neutral,
      );
      if (candidate.letters == letters) {
        return Syllable(initial: entry.key, rime: rime, tone: tone);
      }
    }
  }
  throw ArgumentError('not a syllable: $part');
}
