import 'package:flutter_test/flutter_test.dart';
import 'package:kouyu/pinyin/inventory.dart';
import 'package:kouyu/pinyin/keyboard_layout.dart';
import 'package:kouyu/pinyin/syllable.dart';
import 'package:kouyu/pinyin/tone.dart';

void main() {
  InitialKey key(String label) =>
      initialKeys.firstWhere((initial) => initial.label == label);

  /// Every syllable the keyboard can build, written and untoned.
  Set<String> reachableSyllables() => {
    for (final initial in initialKeys)
      for (final rime in rimeKeysFor(initial))
        Syllable(
          initial: initial.initial,
          rime: rime.rime,
          tone: Tone.neutral,
        ).written,
  };

  test('offers every initial a learner would look for, w and y included', () {
    expect(
      initialKeys.map((initial) => initial.label),
      containsAll(['b', 'zh', 'x', 'w', 'y', bareVowelLabel]),
    );
  });

  // The complaint that prompted this: wǒ was unreachable, because it is
  // phonologically the rime `uo` with no initial, and nothing said `w`.
  test('w leads to wo, spelled the way it is written', () {
    final rimes = rimeKeysFor(key('w'));
    expect(rimes.map((rime) => rime.label), contains('o'));

    final wo = rimes.firstWhere((rime) => rime.label == 'o');
    expect(
      Syllable(initial: '', rime: wo.rime, tone: Tone.third).written,
      'wǒ',
    );
  });

  test('rime labels read as the finished syllable, not the phonology', () {
    // `iu` with no initial is written `you`, so under y it must say `ou`.
    expect(rimeKeysFor(key('y')).map((rime) => rime.label), contains('ou'));
    // `ui` with no initial is written `wei`, so under w it must say `ei`.
    expect(rimeKeysFor(key('w')).map((rime) => rime.label), contains('ei'));
    // ü after j is written u, so ün must say un, not ün.
    final jRimes = rimeKeysFor(key('j')).map((rime) => rime.label);
    expect(jRimes, contains('un'));
    expect(jRimes, isNot(contains('ün')));
    // ...but n keeps its diaeresis, because there the contrast is real.
    expect(rimeKeysFor(key('n')).map((rime) => rime.label), contains('ü'));
  });

  test('initial label plus rime label spells the syllable', () {
    for (final initial in initialKeys) {
      for (final rime in rimeKeysFor(initial)) {
        final spelled = initial.spelling + rime.label;
        final written = Syllable(
          initial: initial.initial,
          rime: rime.rime,
          tone: Tone.neutral,
        ).written;
        expect(spelled, written, reason: '${initial.label} + ${rime.label}');
      }
    }
  });

  test('no bank offers the same label twice', () {
    for (final initial in initialKeys) {
      final labels = rimeKeysFor(initial).map((rime) => rime.label).toList();
      expect(
        labels.length,
        labels.toSet().length,
        reason: 'duplicate rime label under ${initial.label}',
      );
    }
    final initialLabels = initialKeys.map((initial) => initial.label).toList();
    expect(initialLabels.length, initialLabels.toSet().length);
  });

  test('every syllable in the inventory stays reachable', () {
    final reachable = reachableSyllables();
    final expected = {
      for (final entry in syllableInventory.entries)
        for (final rime in entry.value)
          Syllable(initial: entry.key, rime: rime, tone: Tone.neutral).written,
    };
    expect(reachable, expected);

    // Equal sizes means no two initial/rime pairs spell the same syllable, so
    // a written syllable always has exactly one route through the keyboard.
    var pairs = 0;
    for (final entry in syllableInventory.entries) {
      pairs += entry.value.length;
    }
    expect(reachable.length, pairs);
    expect(pairs, 403);
  });

  test('common syllables are all there', () {
    final reachable = reachableSyllables();
    expect(
      reachable,
      containsAll([
        'wo', 'ni', 'hao', 'shi', 'jie', 'you', 'wei', 'wen', 'weng', //
        'yi', 'wu', 'yu', 'yue', 'yuan', 'yun', 'er', 'ai', 'ou', //
        'ju', 'jun', 'juan', 'que', 'xu', 'nü', 'lüe', 'zhi', 'ci', //
        'zei', 'shei', 'gei', 'dei', 'lia', 'miu', 'diu', 'zhua', //
      ]),
    );
  });

  // A keyboard that lets you build syllables Mandarin does not have is
  // teaching the wrong thing.
  test('syllables Mandarin does not have are not offered', () {
    final reachable = reachableSyllables();
    for (final impossible in [
      'qong', 'zü', 'fai', 'jua', 'bou', 'ten', 'ra', 'shong', //
      'nia', 'lün', 'zi̇', 'wi', 'ya̋', 'chua', 'rua', 'den', //
    ]) {
      expect(reachable, isNot(contains(impossible)), reason: impossible);
    }
  });

  // How `w` went missing the first time: a hand-written layout that quietly
  // omits a key. Every arrangement has to account for every initial.
  group('arrangements', () {
    test('each holds every initial exactly once', () {
      for (final arrangement in KeyArrangement.values) {
        final laid = [
          for (final row in initialRows(arrangement))
            for (final key in row) key.label,
        ];
        expect(
          laid..sort(),
          initialKeys.map((key) => key.label).toList()..sort(),
          reason: '$arrangement does not match the available initials',
        );
      }
    });

    test('each lays out the same keys, not copies of them', () {
      for (final arrangement in KeyArrangement.values) {
        for (final row in initialRows(arrangement)) {
          for (final key in row) {
            expect(initialKeys, contains(key), reason: key.label);
          }
        }
      }
    });

    test('qwerty puts the single letters at their home positions', () {
      final rows = initialRows(KeyArrangement.qwerty);
      String row(int index) => rows[index].map((key) => key.label).join(' ');

      expect(row(0), 'q w r t y p $bareVowelLabel');
      expect(row(1), 'sh s d f g h j k l');
      expect(row(2), 'zh z x c ch b n m');
    });

    test('qwerty keeps each digraph beside the letter it extends', () {
      final flat = [
        for (final row in initialRows(KeyArrangement.qwerty))
          for (final key in row) key.label,
      ];
      for (final pair in [('zh', 'z'), ('ch', 'c'), ('sh', 's')]) {
        expect(
          (flat.indexOf(pair.$1) - flat.indexOf(pair.$2)).abs(),
          1,
          reason: '${pair.$1} is not next to ${pair.$2}',
        );
      }
    });

    test('articulation order keeps the confusable sets together', () {
      final rows = initialRows(KeyArrangement.articulatory);
      expect(
        rows.map((row) => row.map((key) => key.label).join()),
        containsAll(['zhchshr', 'zcs']),
      );
    });
  });

  test('the tone bank offers the five real candidates', () {
    final candidates = tonedCandidates(key('n'), 'i');
    expect(candidates.map((syllable) => syllable.written), [
      'nī',
      'ní',
      'nǐ',
      'nì',
      'ni',
    ]);
  });
}
