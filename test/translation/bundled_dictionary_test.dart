import 'package:flutter_test/flutter_test.dart';
import 'package:kouyu/pinyin/syllable.dart';
import 'package:kouyu/pinyin/tone.dart';
import 'package:kouyu/translation/dictionary.dart';
import 'package:kouyu/translation/dictionary_translator.dart';
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

  test('characters are carried but never the only thing offered', () async {
    final entries = await dictionary.lookUp('ni3 hao3');
    // Kept for a future translation service, which needs characters.
    expect(entries.first.simplified, isNotEmpty);
    // But there is always an English gloss to show instead.
    expect(entries.first.glosses.first, isNotEmpty);
  });
}
