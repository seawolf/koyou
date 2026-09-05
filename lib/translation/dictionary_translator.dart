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
      return Translation(_describe(whole), uncertain: whole.length > 1);
    }

    final keys = request.wordKeys;
    if (keys.length < 2) return null;

    final glosses = <String>[];
    var uncertain = false;
    for (final key in keys) {
      final entries = await dictionary.lookUp(key);
      if (entries.isEmpty) return null;
      glosses.add(_describe(entries));
      uncertain |= entries.length > 1;
    }
    return Translation(
      glosses.join(' · '),
      wordByWord: true,
      uncertain: uncertain,
    );
  }

  /// The first gloss of each candidate, best first.
  ///
  /// Only the first gloss per candidate: an ambiguous syllable can match forty
  /// words, and a wall of every sense of each is less use than a short list.
  String _describe(List<DictionaryEntry> entries) =>
      entries.take(candidates).map((entry) => entry.glosses.first).join(' / ');
}
