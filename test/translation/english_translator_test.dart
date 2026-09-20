import 'package:flutter_test/flutter_test.dart';
import 'package:kouyu/pinyin/word.dart';
import 'package:kouyu/translation/character_index.dart';
import 'package:kouyu/translation/dictionary.dart';
import 'package:kouyu/translation/english_dictionary_translator.dart';
import 'package:kouyu/translation/english_index.dart';
import 'package:kouyu/translation/english_model_translator.dart';
import 'package:kouyu/translation/english_translator.dart';
import 'package:kouyu/translation/phrasebook_translator.dart';
import 'package:kouyu/translation/translation_backend.dart';

/// Answers whatever it is told to, and records which direction it was asked.
class _Fake implements TranslationBackend {
  _Fake({this.chinese, this.english});

  final String? chinese;
  final String? english;

  final List<String> askedForChinese = [];
  final List<String> askedForEnglish = [];

  @override
  Future<String?> intoChinese(String english) async {
    askedForChinese.add(english);
    return chinese;
  }

  @override
  Future<String?> intoEnglish(String chinese) async {
    askedForEnglish.add(chinese);
    return english;
  }
}

/// A character index over a handful of rows, laid out exactly as the build
/// tool writes them.
CharacterIndex _characters(Map<String, String> readings) => CharacterIndex(
  loadShard: (shard) async {
    final rows = readings.entries
        .where((entry) => CharacterIndex.shardFor(entry.key) == shard)
        .map((entry) => '${entry.key}\t${entry.value}\t-')
        .join('\n');
    if (rows.isEmpty) throw StateError('no shard $shard');
    return rows;
  },
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('the phrasebook, read backwards', () {
    const book = EnglishPhrasebook();

    test('answers the greeting a dictionary inversion cannot', () async {
      final said = await book.say('hello');
      expect(said, isNotNull);
      expect(said!.best.written, 'nǐ hǎo');
      expect(said.phrasing, Phrasing.entry);
    });

    test('takes it as anyone would type it', () async {
      for (final asked in const ['Hello', 'hello!', ' hello ']) {
        expect((await book.say(asked))?.best.written, 'nǐ hǎo', reason: asked);
      }
    });

    test('keeps the word breaks the phrase is written with', () async {
      final said = await book.say('I love you');
      expect(said!.best.written, 'wǒ ài nǐ');
      expect(said.best.words, hasLength(3));
    });

    test('leaves anything else to the index behind it', () async {
      expect(await book.say('tea'), isNull);
      expect(await book.say(''), isNull);
    });

    test('says the same thing in both columns', () async {
      // The written pinyin is there to be read by whoever edits the list and
      // the keys are what the app uses, so a typo in either would show up
      // only in one direction. This is what stops them drifting.
      for (final phrase in phrasebook) {
        expect(
          phrase.words.map((word) => word.written).join(' '),
          phrase.pinyin,
          reason: '"${phrase.english}" is written one way and keyed another',
        );
      }
    });
  });

  group('the dictionary, read backwards', () {
    final translator = EnglishDictionaryTranslator(
      index: EnglishIndex.bundled(),
      dictionary: Dictionary.bundled(),
    );

    test('answers a word with its pinyin and what it means', () async {
      final said = await translator.say('tea');
      expect(said, isNotNull);
      expect(said!.best.written, 'chá');
      expect(said.best.meaning, contains('tea'));
      expect(said.phrasing, Phrasing.entry);
    });

    test('offers the alternatives rather than picking', () async {
      final said = await translator.say('hot');
      expect(said!.options.length, greaterThan(1));
      // Each has to carry its own meaning, or the choice is between two
      // strings of pinyin a learner cannot tell apart.
      for (final option in said.options) {
        expect(option.meaning, isNotNull, reason: option.written);
      }
    });

    test('says which band a word is in, where it is in one', () async {
      final said = await translator.say('water');
      expect(said!.best.hskLevel, isNotNull);
    });

    test('declines a sentence rather than guessing at one', () async {
      expect(await translator.say('where is the toilet?'), isNull);
      expect(await translator.say('I would like two beers please'), isNull);
    });

    test('gives back words the keyboard could have built', () async {
      // The whole reason an answer is words and not text: it has to be
      // editable the moment it lands in the input area.
      final said = await translator.say('thank you');
      expect(said!.best.words.single, isA<Spoken>());
      final word = said.best.words.single as Spoken;
      expect(word.syllables, hasLength(2));
      expect(word.key, 'xie4 xie5');
    });
  });

  group('the model, composing a phrase', () {
    final characters = _characters({
      '我': 'wo3',
      '爱': 'ai4',
      '你': 'ni3',
      '我爱你': 'wo3 ai4 ni3',
    });

    test('renders what the model wrote and checks it reads back', () async {
      final backend = _Fake(chinese: '我爱你。', english: 'I love you');
      final translator = EnglishModelTranslator(
        characters: characters,
        backend: backend,
      );

      final said = await translator.say('I love you');
      expect(said, isNotNull);
      expect(said!.best.written, 'wǒàinǐ');
      expect(said.phrasing, Phrasing.generated);
      // The check that makes this direction safe to show: the learner cannot
      // read the characters, so the only thing that can catch a fluent answer
      // to the wrong question is the direction that is reliable.
      expect(said.readsBackAs, 'I love you');
      expect(backend.askedForChinese, ['I love you']);
      expect(backend.askedForEnglish, ['我爱你。']);
    });

    test('still answers when the check cannot be made', () async {
      final backend = _Fake(chinese: '我爱你');
      final said = await EnglishModelTranslator(
        characters: characters,
        backend: backend,
      ).say('I love you');
      expect(said!.readsBackAs, isNull);
      expect(said.best.written, isNotEmpty);
    });

    test('declines when the model has nothing', () async {
      final said = await EnglishModelTranslator(
        characters: characters,
        backend: _Fake(),
      ).say('I love you');
      expect(said, isNull);
    });

    test('declines what cannot be read back as pinyin', () async {
      // A model that stopped translating and started talking. Its English
      // would otherwise be handed back as the pinyin to say aloud.
      final said = await EnglishModelTranslator(
        characters: characters,
        backend: _Fake(chinese: 'Sure! Here is the translation:'),
      ).say('I love you');
      expect(said, isNull);
    });

    test('declines a character it cannot read', () async {
      final said = await EnglishModelTranslator(
        characters: characters,
        backend: _Fake(chinese: '我恨你'),
      ).say('I hate you');
      expect(said, isNull);
    });

    test('is not asked about nothing', () async {
      final backend = _Fake(chinese: '我爱你');
      expect(
        await EnglishModelTranslator(
          characters: characters,
          backend: backend,
        ).say('   '),
        isNull,
      );
      expect(backend.askedForChinese, isEmpty);
    });
  });

  group('the chain', () {
    test('takes the first answer and asks no further', () async {
      final chain = CompositeEnglishTranslator([
        const EnglishPhrasebook(),
        EnglishDictionaryTranslator(
          index: EnglishIndex.bundled(),
          dictionary: Dictionary.bundled(),
        ),
      ]);
      // An entry beats a paraphrase, and a hand-checked phrase beats both.
      expect((await chain.say('hello'))!.best.written, 'nǐ hǎo');
      expect((await chain.say('tea'))!.best.written, 'chá');
      expect(await chain.say('I would like two beers please'), isNull);
    });
  });
}
