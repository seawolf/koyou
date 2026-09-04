import 'tone.dart';

/// One pinyin syllable: an optional [initial], a [rime], and a [tone].
///
/// "Rime" is the linguistic name for the part pinyin charts label the "final" —
/// the vowel and anything closing the syllable. It is used here because
/// `final` is a Dart keyword.
class Syllable {
  const Syllable({this.initial = '', required this.rime, required this.tone});

  /// The opening consonant, or `''` for a syllable that begins with its rime.
  final String initial;

  /// The vowel-and-ending part, spelled as pinyin charts list it: `ao`, `iu`,
  /// `üe`. How it is actually written can differ — see [written].
  final String rime;

  final Tone tone;

  /// The syllable as it is written, tone mark included.
  ///
  /// Deliberately not just [initial] + [rime] + a mark. Pinyin respells some
  /// syllables, and the mark belongs on one particular vowel; both rules are
  /// applied here so callers cannot get them wrong.
  String get written {
    final letters = _spell(initial, rime);
    final carrier = _toneCarrier(letters);
    if (carrier < 0) return letters;
    return letters.replaceRange(
      carrier,
      carrier + 1,
      tone.on(letters[carrier]),
    );
  }

  @override
  String toString() => written;

  @override
  bool operator ==(Object other) =>
      other is Syllable &&
      other.initial == initial &&
      other.rime == rime &&
      other.tone == tone;

  @override
  int get hashCode => Object.hash(initial, rime, tone);
}

/// Applies pinyin's spelling rules, which change the letters themselves before
/// any tone mark is placed.
String _spell(String initial, String rime) {
  if (initial.isEmpty) return _standaloneRimes[rime] ?? rime;
  // After j, q and x there is no u/ü distinction to preserve, so ü loses its
  // diaeresis: jü is written ju.
  if (_dropDiaeresisAfter.contains(initial) && rime.startsWith('ü')) {
    return '$initial${rime.replaceFirst('ü', 'u')}';
  }
  return '$initial$rime';
}

const Set<String> _dropDiaeresisAfter = {'j', 'q', 'x'};

/// How each rime is written with no initial in front of it.
///
/// The medial becomes y or w, and several go further than that: `iu` is written
/// `you`, `ui` is `wei`, `un` is `wen`. Those irregulars are why this is a
/// table and not a substitution.
const Map<String, String> _standaloneRimes = {
  'i': 'yi',
  'ia': 'ya',
  'ie': 'ye',
  'iao': 'yao',
  'iu': 'you',
  'ian': 'yan',
  'in': 'yin',
  'iang': 'yang',
  'ing': 'ying',
  'iong': 'yong',
  'u': 'wu',
  'ua': 'wa',
  'uo': 'wo',
  'uai': 'wai',
  'ui': 'wei',
  'uan': 'wan',
  'un': 'wen',
  'uang': 'wang',
  'ueng': 'weng',
  'ü': 'yu',
  'üe': 'yue',
  'üan': 'yuan',
  'ün': 'yun',
};

/// The index of the vowel that carries the tone mark.
///
/// An `a` takes it; failing that an `o`, then an `e`; failing all three it goes
/// on the last vowel. That final clause is what puts the mark on the u of
/// `niù` and the i of `huì`, which is the part people get wrong by hand.
int _toneCarrier(String letters) {
  for (final vowel in const ['a', 'o', 'e']) {
    final index = letters.indexOf(vowel);
    if (index >= 0) return index;
  }
  for (var index = letters.length - 1; index >= 0; index--) {
    if (pinyinVowels.contains(letters[index])) return index;
  }
  return -1;
}
