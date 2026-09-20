import 'character_index.dart';
import 'english_translator.dart';
import 'translation_backend.dart';

/// Composes a whole phrase, by letting the model answer in characters.
///
/// The bridge, run backwards. The model writes Chinese, which is what it was
/// trained to do, and the dictionary turns those characters into tone-marked
/// pinyin, which it does deterministically. Neither half is asked to do the
/// other's job: the model never produces a tone mark, and the dictionary never
/// has to compose a sentence.
///
/// Behind the dictionary tier, because a single word is a dictionary's job.
/// The dictionary has candidates, an HSK band and an honest "these both mean
/// hot"; a model would pick one and sound certain about it.
class EnglishModelTranslator implements EnglishTranslator {
  const EnglishModelTranslator({
    required this.characters,
    required this.backend,
  });

  /// Reads the model's characters back into pinyin, and declines anything it
  /// cannot read — which is also what catches a model that stopped
  /// translating and started talking.
  final CharacterIndex characters;

  final TranslationBackend backend;

  @override
  Future<Said?> say(String english) async {
    if (english.trim().isEmpty) return null;

    final chinese = await backend.intoChinese(english);
    if (chinese == null || chinese.trim().isEmpty) return null;

    final words = await characters.read(chinese);
    if (words == null) return null;

    // The check that makes this direction safe to show at all. Going the other
    // way a bad answer is visibly bad English; going this way the learner
    // cannot read the characters and the pinyin comes back fluent either way,
    // so the only thing that can tell them is the direction that is measured
    // and reliable. Its absence is not a failure — the tier still answers,
    // and the screen says the check was not made.
    final readsBackAs = await backend.intoEnglish(chinese);

    return Said(
      options: [Rendering(words: words)],
      phrasing: Phrasing.generated,
      readsBackAs: readsBackAs,
    );
  }
}
