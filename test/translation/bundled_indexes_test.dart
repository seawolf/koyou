import 'package:flutter_test/flutter_test.dart';
import 'package:kouyu/pinyin/word.dart';
import 'package:kouyu/translation/character_index.dart';
import 'package:kouyu/translation/english_index.dart';

/// Checks the real generated indexes, not stand-ins.
///
/// Both are written by `tool/build_dictionary.dart` and read here, and the two
/// halves have to agree on the shard names and the row format. Nothing else
/// proves they do: a mismatch would leave every lookup quietly empty rather
/// than failing.
void main() {
  // rootBundle needs the binding before it can read an asset.
  TestWidgetsFlutterBinding.ensureInitialized();

  final english = EnglishIndex.bundled();
  final characters = CharacterIndex.bundled();

  group('English index', () {
    test('answers the words a beginner reaches for', () async {
      final expected = {
        'water': '水',
        'tea': '茶',
        'beer': '啤酒',
        'friend': '朋友',
        'dog': '狗',
        'tomorrow': '明天',
        'toilet': '厕所',
        'weather': '天气',
        'hospital': '医院',
        'please': '请',
        'thank you': '谢谢',
      };

      for (final entry in expected.entries) {
        final found = await english.lookUp(entry.key);
        expect(
          found.first.simplified,
          entry.value,
          reason: '"${entry.key}" should be ${entry.value} first',
        );
      }
    });

    test('offers alternatives where English is vaguer than Chinese', () async {
      // "hot" is 热 or 辣 and there is no way to tell from the English which
      // was meant, so both have to be on offer.
      final found = await english.lookUp('hot');
      expect(
        found.map((meaning) => meaning.simplified),
        containsAll(<String>['热', '辣']),
      );
    });

    test('offers alternatives only where they are real', () async {
      // Unfiltered, "thank you" came with 三克油 (a joke transliteration)
      // and 雅教 (archaic formal) beside 谢谢, and nothing on screen would
      // tell a beginner not to pick one.
      expect(await english.lookUp('thank you'), hasLength(1));
      expect(await english.lookUp('water'), hasLength(1));
      expect(await english.lookUp('goodbye'), hasLength(1));
      // While the genuine ambiguity survives it.
      expect((await english.lookUp('hot')).length, greaterThan(1));
    });

    test('takes English as a learner would write it', () async {
      // Verbs are glossed "to eat", so both forms have to land on 吃.
      for (final query in const ['eat', 'to eat', 'Eat', ' eat ']) {
        final found = await english.lookUp(query);
        expect(found.first.simplified, '吃', reason: query);
      }
      // An article is never a headword, and most plurals are not either.
      expect((await english.lookUp('the toilet')).first.simplified, '厕所');
      expect((await english.lookUp('dogs')).first.simplified, '狗');
      // Where the plural *is* a headword it wins, because it was asked for:
      // "books" is 图书 in a way "book" is not.
      expect((await english.lookUp('books')).first.simplified, '图书');
    });

    test('is empty for English it has no word for', () async {
      expect(await english.lookUp('where is the nearest toilet'), isEmpty);
      expect(await english.lookUp(''), isEmpty);
      expect(await english.lookUp('!!!'), isEmpty);
    });
  });

  group('character index', () {
    test('reads a sentence back as tone-marked pinyin', () async {
      final expected = {
        '你好': 'nǐhǎo',
        '我爱你': 'wǒ ài nǐ',
        '明天我要去北京': 'míngtiān wǒ yào qù běijīng',
        '今天天气非常好': 'jīntiān tiānqì fēicháng hǎo',
        '厕所在哪里': 'cèsuǒ zài nǎlǐ',
        '这是我的书': 'zhè shì wǒ de shū',
        // 得 standing alone is the particle, not the verb — an equal-rank tie
        // that used to be settled by the export's own ordering.
        '你能说得慢一点吗': 'nǐ néng shuō de màn yīdiǎn ma',
      };

      for (final entry in expected.entries) {
        final words = await characters.read(entry.key);
        expect(words, isNotNull, reason: entry.key);
        expect(
          words!.map((word) => word.written).join(' '),
          entry.value,
          reason: entry.key,
        );
      }
    });

    test('breaks the line where the dictionary does', () async {
      // The model writes no spaces at all. These word breaks are the whole
      // reason the answer can be edited a word at a time.
      final words = await characters.read('明天我要去北京');
      expect(words!.map((word) => word.written).toList(), [
        'míngtiān',
        'wǒ',
        'yào',
        'qù',
        'běijīng',
      ]);
    });

    test('carries a Latin name through as itself', () async {
      final words = await characters.read('我叫Steve');
      expect(words, isNotNull);
      expect(words!.last, const Literal('Steve'));
      expect(words.first.written, 'wǒ');
    });

    test('drops punctuation, which this app has none of', () async {
      final words = await characters.read('你好，世界！');
      expect(words!.map((word) => word.written).join(' '), 'nǐhǎo shìjiè');
    });

    test('reads a piece of a sentence, which may hold no Chinese', () async {
      // The pieces either side of a word in an example: one may be empty, or
      // only punctuation, and that is not a failure.
      expect(await characters.readPart(''), isEmpty);
      expect(await characters.readPart('。'), isEmpty);
      expect((await characters.readPart('我'))!.single.written, 'wǒ');
      expect(await characters.readPart('我\u{2f81a}'), isNull);
    });

    test('declines rather than leave a hole', () async {
      // A character no dictionary entry covers. Half a line of pinyin is not
      // a line anyone can say.
      expect(await characters.read('我\u{2f81a}你'), isNull);
      // A model that replies in English rather than translating. Handing that
      // back as the pinyin to say would be worse than offering nothing.
      expect(await characters.read('hello'), isNull);
    });

    test('agrees with the build tool about shard names', () async {
      // The two copies of this are in different languages and cannot import
      // one another, so this is what keeps them in step.
      expect(CharacterIndex.shardFor('你'), '4f');
      expect(CharacterIndex.shardFor('好'), '59');
      expect((await characters.read('你'))!.first.written, 'nǐ');
    });
  });
}
