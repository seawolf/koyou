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
      containsAll(['b', 'zh', 'x', 'w', 'y', 'a', 'o', 'e']),
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

  // The second thing that was unreachable in practice: ài was only behind a key
  // labelled with a dash, so nothing on screen said `a`.
  test('a, o and e are offered, and lead to their own syllables', () {
    expect(
      initialKeys.map((initial) => initial.label),
      containsAll(bareVowelStarts),
    );

    expect(rimeKeysFor(key('a')).map((rime) => rime.label), [
      'a',
      'ai',
      'ao',
      'an',
      'ang',
    ]);
    expect(rimeKeysFor(key('o')).map((rime) => rime.label), ['o', 'ou']);
    expect(rimeKeysFor(key('e')).map((rime) => rime.label), [
      'e',
      'er',
      'ei',
      'en',
      'eng',
    ]);

    final ai = rimeKeysFor(key('a')).firstWhere((rime) => rime.label == 'ai');
    expect(Syllable(rime: ai.rime, tone: Tone.fourth).written, 'ài');
  });

  test('every vowel-initial syllable sits under its own first letter', () {
    for (final vowel in bareVowelStarts) {
      for (final rime in rimeKeysFor(key(vowel))) {
        expect(
          rime.label.startsWith(vowel),
          isTrue,
          reason: '${rime.label} is not under $vowel',
        );
      }
    }
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

  group('rime groups', () {
    // Same class of bug as a missing key: a grouping that quietly drops one.
    test('account for every rime, once each', () {
      for (final initial in initialKeys) {
        final grouped = [
          for (final group in rimeRowsFor(initial))
            for (final rime in group) rime.label,
        ];
        expect(
          grouped,
          unorderedEquals(rimeKeysFor(initial).map((rime) => rime.label)),
          reason: 'grouping lost or duplicated a rime under ${initial.label}',
        );
      }
    });

    test('each group shares one starting vowel', () {
      for (final initial in initialKeys) {
        for (final group in rimeRowsFor(initial)) {
          final vowel = group.first.label[0];
          for (final rime in group) {
            expect(
              rime.label.startsWith(vowel),
              isTrue,
              reason: '${rime.label} is grouped under $vowel',
            );
          }
        }
      }
    });

    test('no group is empty, and none is left out', () {
      for (final initial in initialKeys) {
        final groups = rimeRowsFor(initial);
        expect(groups, isNotEmpty, reason: initial.label);
        for (final group in groups) {
          expect(group, isNotEmpty, reason: initial.label);
        }
        // Distinct starting vowels, so a vowel is never split across groups.
        final vowels = groups.map((group) => group.first.label[0]).toList();
        expect(vowels.length, vowels.toSet().length, reason: initial.label);
      }
    });

    test('read as the learner would list them', () {
      expect(
        rimeRowsFor(key('a')).map((g) => g.map((r) => r.label).join(' ')),
        ['a ai ao an ang'],
      );
      expect(
        rimeRowsFor(key('e')).map((g) => g.map((r) => r.label).join(' ')),
        ['e er ei en eng'],
      );
      expect(
        rimeRowsFor(key('n')).map((g) => g.map((r) => r.label).join(' ')),
        [
          'a ai ao an ang',
          'ou ong',
          'e ei en eng',
          'i ie iao iu ian in iang ing',
          'u uo uan',
          'ü üe',
        ],
      );
    });
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

    // Each digraph sits immediately after the letter it extends, which is the
    // point of this arrangement.
    test('qwerty puts each digraph right after its base letter', () {
      final flat = [
        for (final row in initialRows(KeyArrangement.qwerty))
          for (final key in row) key.label,
      ];
      for (final pair in [('zh', 'z'), ('sh', 's'), ('ch', 'c')]) {
        expect(
          flat.indexOf(pair.$1) - flat.indexOf(pair.$2),
          1,
          reason: '${pair.$1} does not follow ${pair.$2}',
        );
      }
    });

    // Columns shift because the digraphs are inline, but the reading order of
    // each row is still its QWERTY row, minus the letters pinyin never uses.
    test('qwerty keeps each row in keyboard order', () {
      const withoutDigraphs = ['qwertyop', 'asdfghjkl', 'zxcbnm'];
      final rows = initialRows(KeyArrangement.qwerty);
      expect(rows.length, withoutDigraphs.length);

      for (var row = 0; row < rows.length; row++) {
        final letters = [
          for (final key in rows[row])
            if (key.label.length == 1) key.label,
        ].join();
        expect(
          letters,
          withoutDigraphs[row],
          reason: 'row $row is out of order',
        );
      }
    });

    test('qwerty drops only the letters pinyin never starts with', () {
      final present = {
        for (final row in initialRows(KeyArrangement.qwerty))
          for (final key in row)
            if (key.label.length == 1) key.label,
      };
      const alphabet = 'abcdefghijklmnopqrstuvwxyz';
      expect(alphabet.split('').where((letter) => !present.contains(letter)), [
        'i',
        'u',
        'v',
      ]);
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
