import 'package:flutter_test/flutter_test.dart';
import 'package:kouyu/translation/dictionary.dart';
import 'package:kouyu/translation/english_dictionary_translator.dart';
import 'package:kouyu/translation/english_index.dart';

/// A translator over a handful of hand-written entries, laid out exactly as
/// the build tool writes them, so each rule below is tested on purpose rather
/// than on whatever CC-CEDICT happens to say this year.
EnglishDictionaryTranslator _over({
  required Map<String, List<String>> english,
  required List<String> entries,
}) {
  final index = EnglishIndex(
    loadShard: (letter) async {
      final rows = [
        for (final MapEntry(:key, :value) in english.entries)
          if (EnglishIndex.queriesFor(key).first[0] == letter)
            [key, ...value].join('\t'),
      ];
      if (rows.isEmpty) throw StateError('no shard $letter');
      return rows.join('\n');
    },
  );
  final dictionary = Dictionary(
    loadShard: (letter) async {
      final rows = entries.where((row) => row.startsWith(letter)).toList();
      if (rows.isEmpty) throw StateError('no shard $letter');
      return rows.join('\n');
    },
  );
  return EnglishDictionaryTranslator(index: index, dictionary: dictionary);
}

Future<List<String?>> _notes(
  EnglishDictionaryTranslator t,
  String word,
) async => [
  for (final option in (await t.say(word))!.options) option.distinction,
];

void main() {
  test('says what only one of them also means', () async {
    final t = _over(
      english: {
        'lunch': ['wu3 can1|午餐', 'zhong1 can1|中餐'],
      },
      entries: [
        'wu3 can1\t午餐\t-\t4296\t2\tlunch/luncheon/CL:',
        'zhong1 can1\t中餐\t-\t14640\t2\tlunch/Chinese meal; Chinese food/CL:',
      ],
    );
    expect(await _notes(t, 'lunch'), [
      'also: luncheon',
      'also: Chinese meal; Chinese food',
    ]);
  });

  test('marks the plain one by elimination', () async {
    // 午饭 means lunch and nothing else, and that is exactly what sets it
    // apart once the other two are accounted for.
    final t = _over(
      english: {
        'lunch': ['wu3 can1|午餐', 'wu3 fan4|午饭'],
      },
      entries: [
        'wu3 can1\t午餐\t-\t4296\t2\tlunch/luncheon',
        'wu3 fan4\t午饭\t-\t4986\t1\tlunch/CL:',
      ],
    );
    expect(await _notes(t, 'lunch'), ['also: luncheon', 'only this meaning']);
  });

  test('ignores senses the others share', () async {
    // A sense every candidate has does not tell any of them apart.
    final t = _over(
      english: {
        'tea': ['cha2|茶', 'cha2 ye4|茶叶'],
      },
      entries: [
        'cha2\t茶\t-\t1910\t1\ttea/tea leaves/tea plant',
        'cha2 ye4\t茶叶\t-\t11593\t2\ttea/tea leaves',
      ],
    );
    expect(await _notes(t, 'tea'), ['also: tea plant', 'only this meaning']);
  });

  test('says which is commoner, and no more, where nothing else differs', () {
    // The dictionary records no difference between 湖 and 湖泊. Frequency is
    // true; a difference invented to fill the gap would not be — see the
    // measurements in docs/local-model.md.
    final t = _over(
      english: {
        'lake': ['hu2|湖', 'hu2 po1|湖泊'],
      },
      entries: ['hu2\t湖\t-\t2100\t2\tlake', 'hu2 po1\t湖泊\t-\t9000\t6\tlake'],
    );
    expect(
      _notes(t, 'lake'),
      completion(['the commoner word', 'rarer — no difference recorded']),
    );
  });

  test('claims nothing where even frequency cannot tell them apart', () {
    final t = _over(
      english: {
        'bowl': ['wan3|碗', 'bo1|钵'],
      },
      entries: ['wan3\t碗\t-\t-\t-\tbowl', 'bo1\t钵\t-\t-\t-\tbowl'],
    );
    expect(
      _notes(t, 'bowl'),
      completion(['no difference recorded', 'no difference recorded']),
    );
  });

  test('leaves alone candidates whose meanings already differ', () async {
    final t = _over(
      english: {
        'hot': ['la4|辣', 're4|热'],
      },
      entries: [
        'la4\t辣\t-\t2791\t4\thot (spicy)/pungent',
        're4\t热\t-\t938\t1\tto warm up/hot (of weather)',
      ],
    );
    expect(await _notes(t, 'hot'), [null, null]);
  });

  test('never offers the dictionary\'s housekeeping as a difference', () async {
    final t = _over(
      english: {
        'lunch': ['wu3 can1|午餐', 'wu3 fan4|午饭'],
      },
      entries: [
        'wu3 can1\t午餐\t-\t4296\t2\tlunch/CL:/see also 午饭',
        'wu3 fan4\t午饭\t-\t4986\t1\tlunch/variant of 午餐',
      ],
    );
    expect(await _notes(t, 'lunch'), [
      'the commoner word',
      'rarer — no difference recorded',
    ]);
  });

  group('when the English says noun or verb', () {
    final t = _over(
      english: {
        'leak': ['tou4|透', 'lou4 dong4|漏洞', 'lou4|漏'],
      },
      entries: [
        'tou4\t透\t-\t900\t3\tto tell secretly; to leak',
        'lou4 dong4\t漏洞\t-\t3000\t5\tleak/loophole',
        'lou4\t漏\t-\t2000\t4\t(bound form) to leak',
      ],
    );
    Future<List<String>> order(String english) async => [
      for (final option in (await t.say(english))!.options) option.written,
    ];

    test('"to leak" puts the verbs first', () async {
      // An aside before the verb does not hide it: "(bound form) to leak".
      expect(await order('to leak'), ['tòu', 'lòu', 'lòudòng']);
    });

    test('"a leak" puts the nouns first', () async {
      expect(await order('a leak'), ['lòudòng', 'tòu', 'lòu']);
      expect(await order('the leak'), ['lòudòng', 'tòu', 'lòu']);
    });

    test('plain "leak" keeps the dictionary\'s own order', () async {
      expect(await order('leak'), ['tòu', 'lòudòng', 'lòu']);
    });
  });

  group('the real dictionary', () {
    TestWidgetsFlutterBinding.ensureInitialized();
    final real = EnglishDictionaryTranslator(
      index: EnglishIndex.bundled(),
      dictionary: Dictionary.bundled(),
    );

    test('tells the three lunches apart', () async {
      final said = await real.say('lunch');
      expect(said!.options.map((o) => o.written), [
        'wǔcān',
        'wǔfàn',
        'zhōngcān',
      ]);
      expect(said.options.map((o) => o.distinction), [
        'also: luncheon',
        'only this meaning',
        'also: Chinese meal; Chinese food',
      ]);
    });

    test('"to land" is the verb and "the land" the noun', () async {
      expect((await real.say('to land'))!.best.written, 'dēnglù');
      expect((await real.say('the land'))!.best.written, 'dì');
    });

    test(
      'every candidate sharing a meaning says something different',
      () async {
        for (final word in const ['lunch', 'lady', 'late', 'language', 'tea']) {
          final options = (await real.say(word))!.options;
          final shared = <String, List<String?>>{};
          for (final option in options) {
            shared
                .putIfAbsent(option.meaning!.toLowerCase(), () => [])
                .add(option.distinction);
          }
          for (final notes in shared.values.where((n) => n.length > 1)) {
            expect(notes, everyElement(isNotNull), reason: word);
            expect(notes.toSet(), hasLength(notes.length), reason: word);
          }
        }
      },
    );
  });
}
