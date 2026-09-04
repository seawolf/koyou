import 'inventory.dart';
import 'syllable.dart';
import 'tone.dart';

/// One key in the initial bank.
///
/// Learner-facing, so these are not quite pinyin's initials. `wǒ` is
/// phonologically the rime `uo` with no initial at all, but nobody learning to
/// speak thinks of it that way — they know the word starts with a w. So `w` and
/// `y` are offered as starting points, both standing for "no initial" with the
/// rimes that happen to be written that way.
class InitialKey {
  const InitialKey({
    required this.label,
    required this.spelling,
    required this.initial,
    required this.rimes,
  });

  /// What the key says.
  final String label;

  /// The letters this key contributes to the written syllable. Usually the same
  /// as [label], but empty for the vowel-initial key, whose label is only a
  /// mark standing for "nothing in front".
  final String spelling;

  /// The phonological initial, which is `''` for `w`, `y` and the vowel key.
  final String initial;

  /// The rimes reachable from this key, phonologically.
  final List<String> rimes;

  /// Whether this key stands for a syllable with no initial consonant.
  bool get isBare => initial.isEmpty;
}

/// One key in the rime bank, labelled as the learner would spell it.
///
/// Under `w`, the rime `uo` is labelled `o`, because the syllable is written
/// `wo`. Under `y`, `iu` is labelled `ou`, because it is written `you`. The
/// label is always the written syllable minus what the initial key spelled, so
/// initial + rime always reads as the finished word.
class RimeKey {
  const RimeKey({required this.label, required this.rime});

  final String label;
  final String rime;
}

/// How the initial bank is laid out on screen.
///
/// Only the arrangement of the initial bank varies. The rime bank cannot follow
/// suit: its keys are things like `iang` and `üe`, which have no position on a
/// Latin keyboard.
enum KeyArrangement {
  /// Grouped by where in the mouth each sound is made — the order pinyin is
  /// taught in, and the one that keeps the confusable sets side by side:
  /// `zh ch sh r` together, `z c s` together.
  articulatory,

  /// QWERTY positions, for hands that already know them.
  ///
  /// The fit is exact: 20 of QWERTY's letters are pinyin initials, and there
  /// are exactly 20 single-letter initials, so each sits at its home position.
  /// That leaves the vowel and `v` gaps for the digraphs, which are placed
  /// beside the letter they extend — `zh` by `z`, `ch` in the `v` slot next to
  /// `c`, `sh` at the head of the home row — so a hand reaching for `z` lands
  /// next to `zh`.
  qwerty,
}

/// The starting points available, in articulation order.
final List<InitialKey> initialKeys = _buildInitialKeys();

/// The initial bank as rows, in [arrangement].
///
/// Rows are explicit rather than packed, because in both arrangements the rows
/// carry meaning: one groups sounds that are made alike, the other reproduces
/// the shape of a keyboard.
List<List<InitialKey>> initialRows(KeyArrangement arrangement) {
  final byLabel = {for (final key in initialKeys) key.label: key};
  return [
    for (final row in _rowLabels[arrangement]!)
      [for (final label in row) byLabel[label]!],
  ];
}

const Map<KeyArrangement, List<List<String>>> _rowLabels = {
  KeyArrangement.articulatory: [
    ['b', 'p', 'm', 'f'],
    ['d', 't', 'n', 'l'],
    ['g', 'k', 'h'],
    ['j', 'q', 'x'],
    ['zh', 'ch', 'sh', 'r'],
    ['z', 'c', 's'],
    // Everything that starts without an initial consonant.
    ['y', 'w', 'a', 'o', 'e'],
  ],
  // A true QWERTY, 10/9/7, every single letter at its own home position. Only
  // u, i and v are unused by pinyin, and there are exactly three digraphs to
  // put in them: ch takes v, beside the c it extends; zh and sh take u and i,
  // where they at least sit beside each other.
  KeyArrangement.qwerty: [
    ['q', 'w', 'e', 'r', 't', 'y', 'zh', 'sh', 'o', 'p'],
    ['a', 's', 'd', 'f', 'g', 'h', 'j', 'k', 'l'],
    ['z', 'x', 'c', 'ch', 'b', 'n', 'm'],
  ],
};

/// The rimes that legitimately follow [initial], labelled for spelling.
List<RimeKey> rimeKeysFor(InitialKey initial) {
  return [
    for (final rime in initial.rimes)
      RimeKey(label: _spellRime(initial, rime), rime: rime),
  ];
}

/// The five toned forms of [initial] + [rime], for the tone bank.
///
/// The learner picks from the actual candidates rather than from abstract tone
/// marks, which is the whole point of a tone-first app: `nī ní nǐ nì ni` is a
/// choice you can hear, `ˉ ˊ ˇ ˋ ·` is a puzzle you have to decode.
List<Syllable> tonedCandidates(InitialKey initial, String rime) {
  return [
    for (final tone in Tone.values)
      Syllable(initial: initial.initial, rime: rime, tone: tone),
  ];
}

/// The written syllable minus the letters the initial key already spelled.
String _spellRime(InitialKey initial, String rime) {
  final written = Syllable(
    initial: initial.initial,
    rime: rime,
    tone: Tone.neutral,
  ).written;
  return written.substring(initial.spelling.length);
}

const List<String> _consonantOrder = [
  'b', 'p', 'm', 'f', //
  'd', 't', 'n', 'l', //
  'g', 'k', 'h', //
  'j', 'q', 'x', //
  'zh', 'ch', 'sh', 'r', //
  'z', 'c', 's', //
];

/// The vowels a syllable can start with when it has no initial consonant.
///
/// One key each, rather than a single key meaning "nothing in front". A learner
/// typing `ài` looks for an `a`; being asked to recognise that the syllable has
/// no initial is the same demand that made `wǒ` unfindable.
///
/// These are the one kind of key whose label is not part of the spelling — they
/// are a way in, and the rime carries the whole syllable, so under `a` the keys
/// read `a`, `ai`, `ao`, `an`, `ang`.
const List<String> bareVowelStarts = ['a', 'o', 'e'];

List<InitialKey> _buildInitialKeys() {
  final bare = syllableInventory['']!;

  /// Splits the initial-less rimes by the letter they are actually written
  /// with, which is how they reach the learner.
  List<String> writtenWith(String letter) => [
    for (final rime in bare)
      if (Syllable(rime: rime, tone: Tone.neutral).written.startsWith(letter))
        rime,
  ];

  return [
    for (final consonant in _consonantOrder)
      InitialKey(
        label: consonant,
        spelling: consonant,
        initial: consonant,
        rimes: syllableInventory[consonant]!,
      ),
    // y and w spell themselves; the vowels only filter.
    InitialKey(label: 'y', spelling: 'y', initial: '', rimes: writtenWith('y')),
    InitialKey(label: 'w', spelling: 'w', initial: '', rimes: writtenWith('w')),
    for (final vowel in bareVowelStarts)
      InitialKey(
        label: vowel,
        spelling: '',
        initial: '',
        rimes: writtenWith(vowel),
      ),
  ];
}
