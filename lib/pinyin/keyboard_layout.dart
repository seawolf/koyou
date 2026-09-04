/// A labelled set of keys, so the keyboard can be grouped the way pinyin
/// charts are rather than as one undifferentiated grid.
class KeyGroup {
  const KeyGroup(this.label, this.keys);

  final String label;
  final List<String> keys;
}

/// The 21 initials, in the order pinyin charts and textbooks use — grouped by
/// where they are articulated, which is also the order they are usually
/// taught in.
const List<String> initials = [
  'b', 'p', 'm', 'f', //
  'd', 't', 'n', 'l', //
  'g', 'k', 'h', //
  'j', 'q', 'x', //
  'zh', 'ch', 'sh', 'r', //
  'z', 'c', 's', //
];

/// The rimes, grouped by medial. Spelled as charts list them, so `ü` groups
/// appear with the diaeresis even where they are written `u` after j, q and x
/// — writing a syllable handles that.
const List<KeyGroup> rimeGroups = [
  KeyGroup('plain', [
    'a', 'o', 'e', 'er', //
    'ai', 'ei', 'ao', 'ou', //
    'an', 'en', 'ang', 'eng', 'ong', //
  ]),
  KeyGroup('i-', [
    'i', 'ia', 'ie', 'iao', 'iu', //
    'ian', 'in', 'iang', 'ing', 'iong', //
  ]),
  KeyGroup('u-', [
    'u', 'ua', 'uo', 'uai', 'ui', //
    'uan', 'un', 'uang', 'ueng', //
  ]),
  KeyGroup('ü-', ['ü', 'üe', 'üan', 'ün']),
];
