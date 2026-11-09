import '../pinyin/word.dart';
import 'breakdown.dart';
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

    // Null once a name is in the line: no entry covers `wǒ jiào Steve`.
    final key = request.key;
    final whole = key == null
        ? const <DictionaryEntry>[]
        : await dictionary.lookUp(key);
    if (whole.isNotEmpty) {
      final uncertain = _isAmbiguous(whole);
      return Translation(
        _describe(whole),
        // One entry for everything typed. The key drops word breaks, so this
        // finds 缘分 whether it was spaced or not.
        matchedWhole: true,
        uncertain: uncertain,
        madeOf: uncertain
            ? const []
            : await Breakdown(dictionary)
                  .charactersOf(whole.first.simplified, whole.first.key),
        // Taken from the word offered first, not from whichever entry happens
        // to carry a band.
        hskLevel: whole.first.hskLevel,
      );
    }

    final typed = request.words.where((word) => !word.isEmpty).toList();
    if (typed.length < 2) return null;

    final words = <WordGloss>[];
    var uncertain = false;
    for (final word in typed) {
      switch (word) {
        case Literal():
          // Nothing to look up, and nothing to correct: it goes through as
          // the learner wrote it.
          words.add(WordGloss(pinyin: word.text, english: 'as you typed it'));
        case Spoken():
          final entries = await dictionary.lookUp(word.key);
          if (entries.isEmpty) return null;
          words.add(
            WordGloss(pinyin: word.written, english: _describe(entries)),
          );
          uncertain |= _isAmbiguous(entries);
      }
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
