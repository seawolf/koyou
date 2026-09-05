import 'dictionary.dart';
import 'translation_backend.dart';
import 'translator.dart';

/// Translates a whole phrase, by resolving it to characters first.
///
/// The measured reason for the indirection: models cannot read tone-marked
/// pinyin. Given `wǒ mài shū` directly, a 27B model answered "I buy books",
/// losing the tone that is the entire point of the word — and the same model
/// rendered `tā wěn wǒ` ("he kissed me") as "held my hand". Given the
/// characters the dictionary resolves, an 0.8B model gets both right.
///
/// So the dictionary does the tone-exact half, which it does deterministically,
/// and the backend does the fluent half, which it was trained for. See
/// `docs/local-model.md` for the measurements.
class ModelTranslator implements Translator {
  const ModelTranslator({required this.dictionary, required this.backend});

  /// Resolves each word to the commonest word with that exact reading.
  final Dictionary dictionary;

  final TranslationBackend backend;

  @override
  Future<Translation?> translate(TranslationRequest request) async {
    // A single word is the dictionary's job, not a model's. It has candidates,
    // an HSK band and an honest "several words sound like this" for the 83% of
    // one-syllable keys that are ambiguous; a model would pick one and sound
    // certain about it. This exists for what a dictionary cannot do — grammar,
    // word order, and anything idiomatic.
    final words = request.wordKeys;
    if (words.length < 2) return null;

    final chinese = StringBuffer();
    for (final key in words) {
      final entries = await dictionary.lookUp(key);
      // One unresolvable word and the whole sentence would be guesswork, so
      // hand back to the dictionary rather than translate around a hole.
      if (entries.isEmpty) return null;
      chinese.write(entries.first.simplified);
    }

    final english = await backend.translate(chinese.toString());
    if (english == null || english.trim().isEmpty) return null;

    // Not word by word, and not the "several words sound like this" kind of
    // uncertain either — that flag is about homophones, and this is one
    // reading of a whole phrase. No HSK band: it describes a word, and this
    // spans several.
    return Translation(english.trim());
  }
}
