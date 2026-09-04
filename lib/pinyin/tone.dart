/// The four Mandarin tones, plus the neutral tone.
///
/// Tone carries meaning in Mandarin, so this app has no concept of a syllable
/// without one. `ma` is not an incomplete `mā`; it is a different word.
enum Tone {
  first(1),
  second(2),
  third(3),
  fourth(4),

  /// The unstressed fifth tone, written with no diacritic at all.
  neutral(5);

  const Tone(this.number);

  /// The tone's number, as learners write it in ASCII pinyin (`ni3`).
  final int number;

  /// [vowel] carrying this tone's diacritic: `Tone.third.on('a')` is `'ǎ'`.
  ///
  /// Returns [vowel] unchanged for [Tone.neutral], and for any letter that
  /// cannot carry a tone mark.
  String on(String vowel) {
    final marked = _toneMarkedVowels[vowel];
    if (this == Tone.neutral || marked == null) return vowel;
    return marked[number - 1];
  }
}

/// Pinyin's six vowels in each of the four marked tones, in tone order.
const Map<String, List<String>> _toneMarkedVowels = {
  'a': ['ā', 'á', 'ǎ', 'à'],
  'e': ['ē', 'é', 'ě', 'è'],
  'i': ['ī', 'í', 'ǐ', 'ì'],
  'o': ['ō', 'ó', 'ǒ', 'ò'],
  'u': ['ū', 'ú', 'ǔ', 'ù'],
  'ü': ['ǖ', 'ǘ', 'ǚ', 'ǜ'],
};

/// The letters that can carry a tone mark.
const Set<String> pinyinVowels = {'a', 'e', 'i', 'o', 'u', 'ü'};
