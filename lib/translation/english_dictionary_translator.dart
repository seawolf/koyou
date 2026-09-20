import '../pinyin/reading.dart';
import '../pinyin/word.dart';
import 'dictionary.dart';
import 'english_index.dart';
import 'english_translator.dart';

/// Answers a word by inverting CC-CEDICT.
///
/// It is a dictionary read backwards and behaves like one: it answers words
/// and set phrases and it does not compose sentences. "toilet" it can do;
/// "where is the toilet?" it cannot, and declines rather than guess — that is
/// what the model tier behind it is for.
///
/// Where English is vaguer than Chinese it offers the alternatives instead of
/// picking. "hot" is 热 or 辣 and nothing in the English says which; showing
/// both, each with what it actually means, is the only honest answer.
class EnglishDictionaryTranslator implements EnglishTranslator {
  const EnglishDictionaryTranslator({
    required this.index,
    required this.dictionary,
  });

  final EnglishIndex index;

  /// Read for the glosses and the HSK band, not for the pinyin — the index
  /// already carries the key. Without it a learner choosing between three
  /// candidates would be choosing between three strings of pinyin they cannot
  /// tell apart.
  final Dictionary dictionary;

  @override
  Future<Said?> say(String english) async {
    final meanings = await index.lookUp(english);
    if (meanings.isEmpty) return null;
    final queries = EnglishIndex.queriesFor(english);

    final options = <Rendering>[];
    for (final meaning in meanings) {
      final syllables = syllablesFor(meaning.key);
      // A word the keyboard cannot build — the erhua suffix, an interjection.
      // Skipped rather than declined over: the other candidates are still
      // answers.
      if (syllables == null) continue;
      final entry = await _entryFor(meaning);
      options.add(
        Rendering(
          words: [Spoken(syllables)],
          meaning: entry == null ? null : _senseFor(entry, queries),
          hskLevel: entry?.hskLevel,
        ),
      );
    }
    if (options.isEmpty) return null;
    return Said(options: options, phrasing: Phrasing.entry);
  }

  /// The sense that was actually asked about.
  ///
  /// Not the entry's first gloss, which is the obvious thing and the wrong
  /// one. 热 is glossed "to warm up / to heat up / hot (of weather) / …", so
  /// somebody typing "hot" and choosing between candidates was being shown
  /// "to warm up" against 辣's "hot (spicy)" — a choice between one answer
  /// and something that does not look like an answer at all.
  ///
  /// The whole sense is returned rather than the matched synonym, because the
  /// bracketed part is the useful bit: "hot (of weather)" is what distinguishes
  /// it, and that is exactly what the index had to strip to find it.
  String _senseFor(DictionaryEntry entry, List<String> queries) {
    for (final gloss in entry.glosses) {
      for (final synonym in gloss.split('; ')) {
        if (queries.contains(EnglishIndex.normalise(synonym))) return gloss;
      }
    }
    return entry.glosses.first;
  }

  /// The entry the index was pointing at.
  ///
  /// Matched on the characters, not just the key: several words share a
  /// reading, and glossing 啤酒 with 皮酒's meaning would be worse than showing
  /// no gloss at all.
  Future<DictionaryEntry?> _entryFor(EnglishMeaning meaning) async {
    for (final entry in await dictionary.lookUp(meaning.key)) {
      if (entry.simplified == meaning.simplified) return entry;
    }
    return null;
  }
}
