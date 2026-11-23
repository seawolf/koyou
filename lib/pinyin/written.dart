/// Reads written pinyin — `nǐ hǎo`, as pasted — into the words the line is
/// made of.
///
/// Splitting written pinyin into syllables is ambiguous in general, which is
/// why the dictionary keys this app reads elsewhere carry their boundaries.
/// Written with its tones it very nearly is not, because pinyin spells itself
/// to be read: a syllable starting with a, o or e follows another only after
/// an apostrophe (`xī'ān`), so `fāngàn` can only be `fān gàn`, and no syllable
/// carries two tone marks, so `xīān` cannot be `xian`. Within those rules the
/// longest syllable is taken first, which is how pinyin is read by eye.
///
/// Without any tones at all it is refused rather than guessed: `ni hao` read
/// as neutral tones would put a confident wrong answer on the line, and tones
/// are what this app is for.
library;

import 'reading.dart';
import 'syllable.dart';
import 'tone.dart';
import 'word.dart';

/// The words of [text], or null when there is no toned pinyin in it.
///
/// Words are what spaces separate. One that is not pinyin at all — `Steve` —
/// comes back as a [Literal], so a line the app copied out reads back in
/// exactly, names and all. Punctuation around a word is dropped, since the
/// line has no place for it. Tone numbers are read as well as marks, so
/// `ni3 hao3` works, and `v` is ü as on any pinyin input method.
List<Word>? readWritten(String text) {
  final words = <Word>[];
  var toned = false;
  for (final raw in text.split(RegExp(r'\s+'))) {
    final word = raw.replaceAll(_edges, '');
    if (word.isEmpty) continue;
    final hasTone = _hasTone.hasMatch(word);
    final syllables = _syllablesOf(word);
    // A toneless word is pinyin only as a single syllable, which is what the
    // neutral-tone particles are — `ma`, `le`, `ne`. Longer, it is a name
    // that happens to spell syllables: `Anna` is not `an na`.
    if (syllables == null || (!hasTone && syllables.length > 1)) {
      words.add(Literal(word));
      continue;
    }
    toned = toned || hasTone;
    words.add(Spoken(syllables));
  }
  if (!toned || !words.any((word) => word is Spoken)) return null;
  return words;
}

/// Punctuation either side of a word, in either script.
/// Combining marks count as part of the word: a tone mark that arrives
/// decomposed often sits on the last letter, as in `hǎo`.
final _edges = RegExp(
  r"^[^\p{L}\p{M}\p{N}]+|[^\p{L}\p{M}\p{N}]+$",
  unicode: true,
);

/// A tone mark or a tone number, anywhere in a word.
final _hasTone = RegExp('[āáǎàēéěèīíǐìōóǒòūúǔùǖǘǚǜ1-5̀́̄̌]');

/// One letter of a word with any tone it carried, or a forced break.
typedef _Letter = ({String letter, Tone? tone});

const _break = (letter: "'", tone: null);

/// The syllables [word] spells, or null if it is not pinyin.
List<Syllable>? _syllablesOf(String word) {
  final letters = _lettersOf(word.toLowerCase());
  if (letters == null) return null;
  // Strictly first, by the rule pinyin is written to; then, only if that
  // reads nothing, without it, because `xīān` for `xī'ān` is a common slip
  // and its tone marks still say where it splits.
  return _split(letters, 0, first: true, strict: true) ??
      _split(letters, 0, first: true, strict: false);
}

/// [word] as plain letters, each with the tone marked on it, and tone numbers
/// carried onto the letter before them.
List<_Letter>? _lettersOf(String word) {
  final letters = <_Letter>[];
  for (final char in word.split('')) {
    final marked = _marked[char];
    // A number ends its syllable, and a combining mark (text that arrives
    // decomposed) sits on the vowel: both belong to the letter before them.
    final tone = _numbers[char] ?? _combining[char];
    final previous = letters.isEmpty ? null : letters.last;
    if (marked != null) {
      letters.add(marked);
    } else if (char == "'" || char == '’') {
      letters.add(_break);
    } else if (tone != null) {
      if (previous == null || previous == _break || previous.tone != null) {
        return null;
      }
      letters.last = (letter: previous.letter, tone: tone);
      if (_numbers.containsKey(char)) letters.add(_break);
    } else if (char == '̈' || char == ':') {
      // ü decomposed, or `u:` as dictionary keys write it.
      if (previous?.letter != 'u') return null;
      letters.last = (letter: 'ü', tone: previous!.tone);
    } else if (RegExp('[a-z]').hasMatch(char)) {
      letters.add((letter: char == 'v' ? 'ü' : char, tone: null));
    } else {
      return null;
    }
  }
  return letters;
}

/// The syllables [letters] spell from [at] on, longest first, backing off
/// where that leaves the rest unreadable.
List<Syllable>? _split(
  List<_Letter> letters,
  int at, {
  required bool first,
  required bool strict,
}) {
  if (at == letters.length) return const [];
  if (letters[at] == _break) {
    return at == 0
        ? null
        : _split(letters, at + 1, first: true, strict: strict);
  }
  for (var end = letters.length; end > at; end--) {
    final piece = letters.sublist(at, end);
    if (piece.contains(_break)) continue;
    final spelling = piece.map((letter) => letter.letter).join();
    // Pinyin's own rule: a syllable starting with a vowel follows another
    // only across an apostrophe, so without one this cannot be where it
    // starts.
    if (strict && !first && 'aoe'.contains(spelling[0])) continue;
    final tones = [for (final letter in piece) ?letter.tone];
    if (tones.length > 1) continue;
    final parts = spelt(spelling);
    if (parts == null) continue;
    final rest = _split(letters, end, first: false, strict: strict);
    if (rest == null) continue;
    return [
      Syllable(
        initial: parts.initial,
        rime: parts.rime,
        tone: tones.isEmpty ? Tone.neutral : tones.single,
      ),
      ...rest,
    ];
  }
  return null;
}

const Map<String, _Letter> _marked = {
  'ā': (letter: 'a', tone: Tone.first),
  'á': (letter: 'a', tone: Tone.second),
  'ǎ': (letter: 'a', tone: Tone.third),
  'à': (letter: 'a', tone: Tone.fourth),
  'ē': (letter: 'e', tone: Tone.first),
  'é': (letter: 'e', tone: Tone.second),
  'ě': (letter: 'e', tone: Tone.third),
  'è': (letter: 'e', tone: Tone.fourth),
  'ī': (letter: 'i', tone: Tone.first),
  'í': (letter: 'i', tone: Tone.second),
  'ǐ': (letter: 'i', tone: Tone.third),
  'ì': (letter: 'i', tone: Tone.fourth),
  'ō': (letter: 'o', tone: Tone.first),
  'ó': (letter: 'o', tone: Tone.second),
  'ǒ': (letter: 'o', tone: Tone.third),
  'ò': (letter: 'o', tone: Tone.fourth),
  'ū': (letter: 'u', tone: Tone.first),
  'ú': (letter: 'u', tone: Tone.second),
  'ǔ': (letter: 'u', tone: Tone.third),
  'ù': (letter: 'u', tone: Tone.fourth),
  'ǖ': (letter: 'ü', tone: Tone.first),
  'ǘ': (letter: 'ü', tone: Tone.second),
  'ǚ': (letter: 'ü', tone: Tone.third),
  'ǜ': (letter: 'ü', tone: Tone.fourth),
  'ü': (letter: 'ü', tone: null),
};

/// Tone marks that arrive as separate characters, after the vowel.
const Map<String, Tone> _combining = {
  '\u0304': Tone.first,
  '\u0301': Tone.second,
  '\u030c': Tone.third,
  '\u0300': Tone.fourth,
};

const Map<String, Tone> _numbers = {
  '1': Tone.first,
  '2': Tone.second,
  '3': Tone.third,
  '4': Tone.fourth,
  '5': Tone.neutral,
};
