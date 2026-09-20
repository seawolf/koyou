/// Reads a dictionary key back into the syllables the keyboard builds.
///
/// The inverse of [Syllable.numbered], and the piece that lets an answer come
/// back into the input area: a dictionary key is letters and a tone number,
/// and the app works in initials, rimes and tones.
///
/// Not a parser of written pinyin. It reads `ni3 hao3`, never `nǐ hǎo` —
/// splitting written pinyin into syllables is genuinely ambiguous (`wanan` is
/// two words) and a key already has its boundaries and its tones.
library;

import 'inventory.dart';
import 'syllable.dart';
import 'tone.dart';

/// The syllables [key] spells, or null if any of them is not one this app
/// builds.
///
/// Null rather than a best effort. 0.34% of dictionary entries are keyed on
/// syllables the keyboard deliberately leaves out — 359 of them on the erhua
/// suffix `r5`, the rest interjections like `hm` and `ng` and one-off
/// curiosities like `biang` — and a line with a hole in it is worse than no
/// line.
List<Syllable>? syllablesFor(String key) {
  if (key.isEmpty) return null;
  final syllables = <Syllable>[];
  for (final part in key.split(' ')) {
    final syllable = syllableFor(part);
    if (syllable == null) return null;
    syllables.add(syllable);
  }
  return syllables;
}

/// The syllable `wo3` or `nu:3` spells, or null if this app does not build it.
Syllable? syllableFor(String numbered) {
  if (numbered.length < 2) return null;
  final tone = _tones[numbered[numbered.length - 1]];
  if (tone == null) return null;
  // `u:` is how the dictionary writes ü, which is how [Syllable.numbered]
  // wrote it on the way out.
  final letters = numbered
      .substring(0, numbered.length - 1)
      .replaceAll('u:', 'ü');
  final parts = _spellings[letters];
  if (parts == null) return null;
  return Syllable(initial: parts.initial, rime: parts.rime, tone: tone);
}

const Map<String, Tone> _tones = {
  '1': Tone.first,
  '2': Tone.second,
  '3': Tone.third,
  '4': Tone.fourth,
  '5': Tone.neutral,
};

/// Every syllable's letters, mapped to the initial and rime behind them.
///
/// Derived from [syllableInventory] rather than written out, because the
/// spelling rules are already in [Syllable] and a second table of them would
/// be a second place for `you`, `wei` and `ju` to be got wrong. Every one of
/// the 403 syllables in the inventory spells differently, so the mapping is
/// exact — pinned by a test, since a rime added to the inventory could in
/// principle collide.
final Map<String, ({String initial, String rime})> _spellings = {
  for (final initial in syllableInventory.keys)
    for (final rime in syllableInventory[initial]!)
      Syllable(initial: initial, rime: rime, tone: Tone.first).letters: (
        initial: initial,
        rime: rime,
      ),
};
