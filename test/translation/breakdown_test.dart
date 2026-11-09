import 'package:flutter_test/flutter_test.dart';
import 'package:kouyu/translation/breakdown.dart';
import 'package:kouyu/translation/dictionary.dart';
import 'package:kouyu/translation/translator.dart';

/// A dictionary over a handful of rows, laid out as the build tool writes them.
Dictionary _over(List<String> rows) => Dictionary(
  loadShard: (letter) async {
    final found = rows.where((row) => row.startsWith(letter)).toList();
    if (found.isEmpty) throw StateError('no shard $letter');
    return found.join('\n');
  },
);

List<String> _read(List<WordGloss> parts) => [
  for (final part in parts) '${part.pinyin} ${part.english}',
];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('taking a word apart', () {
    final breakdown = Breakdown(
      _over([
        'mi3\t米\t-\t900\t2\tuncooked rice/meter (unit of length)',
        'fan4\t饭\t-\t800\t1\tcooked rice/meal',
        'dong1\t东\t-\t500\t1\teast',
        'xi1\t西\t-\t600\t1\twest',
        'piao1\t漂\t-\t7000\t-\tto float',
        'liang4\t亮\t-\t900\t2\tbright',
        'zhou1\t周\tp\t300\t-\tZhou Dynasty',
        'zhou1\t周\t-\t300\t2\tweek; cycle',
        'mo4\t末\t-\t2000\t3\ttip; end',
      ]),
    );

    test('gives each character in the reading it takes there', () async {
      expect(_read(await breakdown.charactersOf('米饭', 'mi3 fan4')), [
        'mǐ uncooked rice; meter (unit of length)',
        'fàn cooked rice; meal',
      ]);
    });

    test('reads a neutral tone as the same syllable in a full one', () async {
      // 西 in 东西 is xi with no tone, which the dictionary does not list on
      // its own. It is the weakened 西 xī, "west".
      expect(_read(await breakdown.charactersOf('东西', 'dong1 xi5')), [
        'dōng east',
        'xi west',
      ]);
    });

    test('leaves a full tone unglossed rather than guess another', () async {
      // 漂 in 漂亮 is piào. The 漂 the dictionary has is piāo, "to float",
      // which is a different word.
      expect(_read(await breakdown.charactersOf('漂亮', 'piao4 liang4')), [
        'piào not glossed on its own',
        'liàng bright',
      ]);
    });

    test('never glosses a character with a name', () async {
      expect(
        (await breakdown.charactersOf('周末', 'zhou1 mo4')).first.english,
        'week; cycle',
      );
    });

    test('has nothing to say about one character', () async {
      expect(await breakdown.charactersOf('米', 'mi3'), isEmpty);
    });

    test('has nothing to say where characters and syllables differ', () async {
      expect(await breakdown.charactersOf('卡拉OK', 'ka3 la1'), isEmpty);
      expect(await breakdown.charactersOf('米饭', 'mi3'), isEmpty);
    });

    test('glosses a whole word', () async {
      expect(await breakdown.glossOf('米', 'mi3'), contains('uncooked rice'));
      expect(await breakdown.glossOf('米', 'fan4'), isNull);
    });
  });

  group('a short gloss', () {
    test('keeps up to three senses', () {
      expect(
        Breakdown.shortGloss(['dialect', 'language', 'spoken words', 'talk']),
        'dialect; language; spoken words',
      );
    });

    test('counts senses inside a gloss, not glosses', () {
      // CC-CEDICT packs seven into the first gloss of 生.
      expect(
        Breakdown.shortGloss([
          'to grow; to give birth; to produce; to be born',
        ]),
        'to grow; to give birth; to produce',
      );
    });

    test('stops before it becomes a definition', () {
      expect(
        Breakdown.shortGloss([
          'hand',
          'person engaged in certain types of work',
        ]),
        'hand',
      );
    });

    test('puts plain senses before marked ones', () {
      expect(
        Breakdown.shortGloss(['(slang) Chinese yuan', 'uncooked rice']),
        'uncooked rice; (slang) Chinese yuan',
      );
    });

    test('carries a marker to every synonym in its sense', () {
      // "devotee" on its own would read as something 饭 plainly means.
      expect(
        Breakdown.shortGloss([
          'cooked rice',
          'meal',
          '(loanword) fan; devotee',
        ]),
        'cooked rice; meal; (loanword) fan',
      );
    });

    test('keeps "(bound form)" where it falls', () {
      expect(
        Breakdown.shortGloss(['(bound form) machine; mechanism']),
        '(bound form) machine; mechanism',
      );
    });

    test('drops housekeeping and anything in characters', () {
      expect(
        Breakdown.shortGloss(['CL:个', 'see also 米饭', 'used in 葡萄', 'rice']),
        'rice',
      );
      expect(Breakdown.shortGloss(['CL:个']), isNull);
    });
  });

  group('the real dictionary', () {
    final real = Breakdown(Dictionary.bundled());

    test('takes mǐfàn apart', () async {
      final parts = await real.charactersOf('米饭', 'mi3 fan4');
      expect(parts.map((p) => p.pinyin), ['mǐ', 'fàn']);
      expect(parts.first.english, startsWith('uncooked rice'));
      expect(parts.last.english, startsWith('cooked rice'));
    });

    test('finds the west in dōngxi', () async {
      final parts = await real.charactersOf('东西', 'dong1 xi5');
      expect(_read(parts), ['dōng east', 'xi west']);
    });
  });
}
