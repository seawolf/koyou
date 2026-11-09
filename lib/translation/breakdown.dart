import '../pinyin/reading.dart';
import '../pinyin/syllable.dart';
import '../pinyin/tone.dart';
import 'dictionary.dart';
import 'translator.dart';

/// What a word is made of, and what a word means on its own, from the
/// dictionary.
///
/// A word of several syllables is built from characters that each mean
/// something — 米饭 is 米 "uncooked rice" and 饭 "cooked rice" — and seeing the
/// pieces is half of remembering the whole. CC-CEDICT has an entry for nearly
/// every character, and the word's own key says which reading each character
/// takes inside it, so each can be looked up in exactly that reading: 97% of
/// syllabus words of two or more characters have every character glossed.
///
/// Pinyin and meanings only. The characters are what is looked up, never what
/// is shown: they are not the learning surface.
class Breakdown {
  const Breakdown(this.dictionary);

  final Dictionary dictionary;

  /// Each character of [simplified], in the reading [key] gives it, with what
  /// it means on its own; empty where that cannot be worked out.
  ///
  /// Empty for a single character, which is its own breakdown, and wherever
  /// the characters and syllables do not line up one to one — a word with a
  /// letter in it, or the erhua suffix, which the keyboard does not build.
  Future<List<WordGloss>> charactersOf(String simplified, String key) async {
    final syllables = syllablesFor(key);
    final characters = simplified.runes.map(String.fromCharCode).toList();
    if (syllables == null ||
        syllables.length < 2 ||
        syllables.length != characters.length) {
      return const [];
    }
    return [
      for (var i = 0; i < characters.length; i++)
        WordGloss(
          pinyin: syllables[i].written,
          english:
              await _characterGloss(characters[i], syllables[i]) ??
              'not glossed on its own',
        ),
    ];
  }

  /// What the word written [simplified] and keyed [key] means, in a few
  /// senses, or null if the dictionary does not have it.
  Future<String?> glossOf(String simplified, String key) async {
    for (final entry in await dictionary.lookUp(key)) {
      if (entry.simplified == simplified && !entry.properNoun) {
        return shortGloss(entry.glosses);
      }
    }
    return null;
  }

  /// The character [character] read as [syllable], glossed.
  ///
  /// A neutral tone falls back to the same syllable in any tone, and nothing
  /// else does. 西 in 东西 is *xi* with no tone, which CC-CEDICT does not list
  /// on its own; it is the weakened form of 西 *xī*, "west" — which is also the
  /// joke of the word: east and west, a thing. A full tone that has no entry
  /// is left unglossed instead, because there the nearest reading is often a
  /// different word altogether: 漂 in 漂亮 is *piào*, and the 漂 that does have
  /// an entry is *piāo*, "to float".
  Future<String?> _characterGloss(String character, Syllable syllable) async {
    final exact = await _entryFor(character, [syllable.numbered]);
    if (exact != null) return shortGloss(exact.glosses);
    if (syllable.tone != Tone.neutral) return null;

    final letters = syllable.numbered.substring(
      0,
      syllable.numbered.length - 1,
    );
    final fallback = await _entryFor(character, [
      for (final tone in const [1, 2, 3, 4]) '$letters$tone',
    ]);
    return fallback == null ? null : shortGloss(fallback.glosses);
  }

  /// The commonest ordinary entry for [character] under any of [keys].
  Future<DictionaryEntry?> _entryFor(
    String character,
    List<String> keys,
  ) async {
    final found = <DictionaryEntry>[
      for (final key in keys)
        for (final entry in await dictionary.lookUp(key))
          if (entry.simplified == character && !entry.properNoun) entry,
    ]..sort((a, b) => a.compareForDisplay(b));
    return found.isEmpty ? null : found.first;
  }

  /// A short reminder of what an entry means: up to three of its senses,
  /// plain ones first, without the dictionary's housekeeping.
  ///
  /// Counted by sense and not by gloss, because CC-CEDICT packs several into
  /// one — 生 has seven in its first — and stopped at about forty characters,
  /// because past that it is a definition rather than a reminder. One sense is
  /// too thin, though: 话 is "dialect" alone, and "dialect; language; spoken
  /// words" with three.
  ///
  /// A sense marked "(slang)" or "(loanword)" goes after the plain ones, so 米
  /// is "uncooked rice; meter" before it is "Chinese yuan". "(bound form)" is
  /// the exception, kept where it falls, because it tells a learner something
  /// they need: that the character does not stand on its own. A sense with
  /// characters in it is skipped, since this is shown as it stands.
  static String? shortGloss(List<String> glosses) {
    final plain = <String>[];
    final marked = <String>[];
    for (final gloss in glosses) {
      // The marker belongs to the whole sense, not its first synonym:
      // "(loanword) fan; devotee" is a loanword twice over, and "devotee" on
      // its own would read as something 饭 plainly means.
      final head = gloss.trim().toLowerCase();
      final isMarked = head.startsWith('(') && !head.startsWith('(bound form)');
      for (final sense in gloss.split('; ')) {
        final text = sense.trim();
        final lower = text.toLowerCase();
        if (text.isEmpty ||
            lower.startsWith('cl:') ||
            lower.startsWith('see ') ||
            lower.startsWith('variant of') ||
            lower.startsWith('also written') ||
            _han.hasMatch(text)) {
          continue;
        }
        (isMarked ? marked : plain).add(text);
      }
    }
    final kept = <String>[];
    var length = 0;
    for (final sense in [...plain, ...marked]) {
      if (kept.isNotEmpty && (kept.length == 3 || length + sense.length > 40)) {
        break;
      }
      kept.add(sense);
      length += sense.length + 2;
    }
    return kept.isEmpty ? null : kept.join('; ');
  }

  static final _han = RegExp(r'[㐀-鿿]');
}
