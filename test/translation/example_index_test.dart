import 'package:flutter_test/flutter_test.dart';
import 'package:kouyu/pinyin/word.dart';
import 'package:kouyu/translation/character_index.dart';
import 'package:kouyu/translation/dictionary.dart';
import 'package:kouyu/translation/english_dictionary_translator.dart';
import 'package:kouyu/translation/english_index.dart';
import 'package:kouyu/translation/example_index.dart';

/// Shards over a handful of rows, named the way the real ones are.
Future<String> Function(String) _shards(Map<String, String> rows) =>
    (name) async {
      final found = [
        for (final MapEntry(:key, :value) in rows.entries)
          if (CharacterIndex.shardFor(key) == name) value,
      ];
      if (found.isEmpty) throw StateError('no shard $name');
      return found.join('\n');
    };

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('the example index', () {
    test('finds the sentence chosen for a word', () async {
      final index = ExampleIndex(
        loadShard: _shards({
          '会员': '会员\t1\t您有会员卡吗？\tDo you have a points card?',
        }),
      );
      final found = await index.find('会员');
      expect(found?.chinese, '您有会员卡吗？');
      expect(found?.offset, 1);
      expect(found?.english, 'Do you have a points card?');
      expect(await index.find('成员'), isNull);
      expect(await index.find(''), isNull);
    });
  });

  group('an example beside a candidate', () {
    // 还 is read huán as a verb and hái as an adverb. The character index
    // says huán; the candidate offered for "still" is hái. Reading the whole
    // sentence would have put a different tone on the word than the row it
    // sits under.
    final characters = CharacterIndex(
      loadShard: _shards({
        '我': '我\two3\t3',
        '还': '还\thuan2\t20',
        '没': '没\tmei2\t30',
        '吃': '吃\tchi1\t142',
      }),
    );
    final translator = EnglishDictionaryTranslator(
      index: EnglishIndex(
        loadShard: (letter) async =>
            letter == 's' ? 'still\thai2|还' : throw StateError('no shard'),
      ),
      dictionary: Dictionary(
        loadShard: (letter) async => letter == 'h'
            ? 'hai2\t还\t-\t20\t1\tstill; yet'
            : throw StateError('no shard'),
      ),
      examples: ExampleIndex(
        loadShard: _shards({'还': '还\t1\t我还没吃。\tI haven\'t eaten yet.'}),
      ),
      characters: characters,
    );

    test('reads the sentence into pinyin, with its English', () async {
      final example = (await translator.say('still'))!.best.example!;
      expect(example.english, "I haven't eaten yet.");
      expect(
        example.words.map((word) => word.written).join(' '),
        'wǒ hái méi chī',
      );
    });

    test('keeps the word in the reading it was offered with', () async {
      final example = (await translator.say('still'))!.best.example!;
      final word = example.words[example.target] as Spoken;
      expect(
        word.key,
        'hai2',
        reason: 'not huan2, which the sentence alone gives',
      );
    });

    test('offers none where a part of the sentence cannot be read', () async {
      final unreadable = EnglishDictionaryTranslator(
        index: translator.index,
        dictionary: translator.dictionary,
        examples: ExampleIndex(
          loadShard: _shards({'还': '还\t1\t我还沒吃。\tI haven\'t eaten yet.'}),
        ),
        characters: characters,
      );
      final said = await unreadable.say('still');
      expect(said!.best.example, isNull);
      // The answer itself is unaffected: an example is extra, never a
      // reason to offer less.
      expect(said.best.written, 'hái');
    });

    test('offers none where the row does not point at the word', () async {
      final wrong = EnglishDictionaryTranslator(
        index: translator.index,
        dictionary: translator.dictionary,
        examples: ExampleIndex(
          loadShard: _shards({'还': '还\t0\t我还没吃。\tI haven\'t eaten yet.'}),
        ),
        characters: characters,
      );
      expect((await wrong.say('still'))!.best.example, isNull);
    });
  });

  group('the real examples', () {
    final real = EnglishDictionaryTranslator(
      index: EnglishIndex.bundled(),
      dictionary: Dictionary.bundled(),
      examples: ExampleIndex.bundled(),
      characters: CharacterIndex.bundled(),
    );

    test('show the difference between the two "member"s', () async {
      final options = (await real.say('member'))!.options;
      String? englishOf(String pinyin) => options
          .firstWhere((option) => option.written == pinyin)
          .example
          ?.english;
      expect(englishOf('huìyuán'), contains('card'));
      expect(englishOf('chéngyuán'), contains('committee'));
    });

    test('mark the word itself in every example', () async {
      for (final word in const ['lunch', 'member', 'tea', 'hot', 'summer']) {
        for (final option in (await real.say(word))!.options) {
          final example = option.example;
          if (example == null) continue;
          expect(
            example.words[example.target],
            option.words.single,
            reason: '${option.written} in its own example',
          );
        }
      }
    });

    test('are never about the corpus itself', () async {
      // Untagged, and once offered as the example of 例如.
      final english = [
        for (final option in (await real.say('for example'))!.options)
          ?option.example?.english,
      ];
      expect(english, isNotEmpty);
      for (final sentence in english) {
        expect(sentence.toLowerCase(), isNot(contains('tatoeba')));
      }
    });
  });
}
