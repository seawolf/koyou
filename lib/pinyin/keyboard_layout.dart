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

/// The starting points, in the order pinyin is usually taught: grouped by where
/// each is articulated, then the two glides, then the bare vowels.
final List<InitialKey> initialKeys = _buildInitialKeys();

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

/// The label for the key that starts a syllable with no consonant at all.
const String bareVowelLabel = '–';

List<InitialKey> _buildInitialKeys() {
  final bare = syllableInventory['']!;

  /// Splits the initial-less rimes by the letter they are actually written
  /// with, which is how they reach the learner.
  List<String> writtenWith(String letter) => [
    for (final rime in bare)
      if (Syllable(rime: rime, tone: Tone.neutral).written.startsWith(letter))
        rime,
  ];

  final glided = {...writtenWith('y'), ...writtenWith('w')};

  return [
    for (final consonant in _consonantOrder)
      InitialKey(
        label: consonant,
        spelling: consonant,
        initial: consonant,
        rimes: syllableInventory[consonant]!,
      ),
    InitialKey(label: 'y', spelling: 'y', initial: '', rimes: writtenWith('y')),
    InitialKey(label: 'w', spelling: 'w', initial: '', rimes: writtenWith('w')),
    InitialKey(
      label: bareVowelLabel,
      spelling: '',
      initial: '',
      rimes: [
        for (final rime in bare)
          if (!glided.contains(rime)) rime,
      ],
    ),
  ];
}
