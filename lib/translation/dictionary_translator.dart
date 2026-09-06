import 'dictionary.dart';
import 'translator.dart';

/// Looks the pinyin up in CC-CEDICT.
///
/// Tries everything typed as one entry first, since a set phrase is one word in
/// the dictionary whether or not the learner spaced it, then falls back to
/// glossing word by word.
///
/// It is a dictionary and behaves like one: it resolves words and set phrases,
/// including idioms, and it does not translate sentences. Grammar, word order
/// and anything idiomatic that is not itself an entry are beyond it.
class DictionaryTranslator implements Translator {
  const DictionaryTranslator(this.dictionary, {this.candidates = 3});

  final Dictionary dictionary;

  /// How many candidate words to offer when the pinyin is ambiguous.
  final int candidates;

  @override
  Future<Translation?> translate(TranslationRequest request) async {
    if (request.isEmpty) return null;

    final whole = await dictionary.lookUp(request.key);
    if (whole.isNotEmpty) {
      return Translation(
        _describe(whole),
        uncertain: _isAmbiguous(whole),
        // Taken from the word offered first, not from whichever entry happens
        // to carry a band.
        hskLevel: whole.first.hskLevel,
      );
    }

    final keys = request.wordKeys;
    if (keys.length < 2) return null;

    final written = request.writtenWords;
    final words = <WordGloss>[];
    var uncertain = false;
    for (var index = 0; index < keys.length; index++) {
      final entries = await dictionary.lookUp(keys[index]);
      if (entries.isEmpty) return null;
      words.add(WordGloss(pinyin: written[index], english: _describe(entries)));
      uncertain |= _isAmbiguous(entries);
    }
    // [text] stays filled for anything that wants one line of it — a test, a
    // log, a future share sheet. The screen reads [words] and lays them out
    // down the page instead.
    return Translation(
      words.map((word) => word.english).join(' · '),
      wordByWord: true,
      uncertain: uncertain,
      words: words,
    );
  }

  /// The first gloss of each candidate, best first.
  ///
  /// Only the first gloss per candidate: an ambiguous syllable can match forty
  /// words, and a wall of every sense of each is less use than a short list.
  ///
  /// One entry per word, too. CC-CEDICT sometimes splits a word's senses across
  /// entries — `ni3` has two for 你 — and "you / you / doubtful" reads as three
  /// answers when it is two.
  /// Whether these are several different words, rather than one word whose
  /// senses CC-CEDICT split across separate entries.
  bool _isAmbiguous(List<DictionaryEntry> entries) =>
      entries.map((entry) => entry.simplified).toSet().length > 1;

  String _describe(List<DictionaryEntry> entries) {
    final seen = <String>{};
    final glosses = <String>[];
    for (final entry in entries) {
      if (!seen.add(entry.simplified)) continue;
      glosses.add(entry.glosses.first);
      if (glosses.length == candidates) break;
    }
    return glosses.join(' / ');
  }
}
