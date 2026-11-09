import '../pinyin/word.dart';
import 'breakdown.dart';
import 'character_index.dart';
import 'dictionary.dart';
import 'english_translator.dart';
import 'translation_backend.dart';
import 'translator.dart';

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
    this.dictionary,
  });

  /// Glosses the answer a word at a time, so a sentence the model wrote can be
  /// taken apart as a dictionary answer can. Null leaves the parts out.
  final Dictionary? dictionary;

  /// Reads the model's characters back into pinyin, and declines anything it
  /// cannot read — which is also what catches a model that stopped
  /// translating and started talking.
  final CharacterIndex characters;

  final TranslationBackend backend;

  /// [register] is accepted and deliberately not used. Told to translate
  /// formally or informally, the model stopped translating and started
  /// answering — about half of twelve phrases went wrong against one with no
  /// instruction, and in informal mode it used the formal 您 anyway. The
  /// numbers are in `docs/local-model.md`; the screen tells the learner a
  /// sentence is translated as written.
  @override
  Future<Said?> say(String english, {Register? register}) async {
    if (english.trim().isEmpty) return null;

    final chinese = await backend.intoChinese(english);
    if (chinese == null || chinese.trim().isEmpty) return null;

    final read = await characters.readWithCharacters(chinese);
    if (read == null || !read.any((piece) => piece.word is Spoken)) {
      return null;
    }
    final words = [for (final piece in read) piece.word];

    // The check that makes this direction safe to show at all. Going the other
    // way a bad answer is visibly bad English; going this way the learner
    // cannot read the characters and the pinyin comes back fluent either way,
    // so the only thing that can tell them is the direction that is measured
    // and reliable. Its absence is not a failure — the tier still answers,
    // and the screen says the check was not made.
    final readsBackAs = await backend.intoEnglish(chinese);

    return Said(
      options: [Rendering(words: words, parts: await _partsOf(read))],
      phrasing: Phrasing.generated,
      readsBackAs: readsBackAs,
    );
  }

  /// The answer taken apart one level: a sentence into its words, each glossed
  /// from the dictionary, or a single word into its characters.
  ///
  /// The meanings are the dictionary's, never the model's. The model chose the
  /// words; what each one means is looked up, so a word it used oddly is at
  /// least glossed truly.
  Future<List<WordGloss>> _partsOf(List<ReadWord> read) async {
    final dictionary = this.dictionary;
    if (dictionary == null) return const [];
    final breakdown = Breakdown(dictionary);

    final spoken = [
      for (final piece in read)
        if (piece.word is Spoken) piece,
    ];
    if (spoken.length == 1 && read.length == 1) {
      final only = spoken.single;
      return breakdown.charactersOf(only.characters!, only.key!);
    }
    return [
      for (final piece in read)
        switch (piece.word) {
          Literal(:final text) => WordGloss(
            pinyin: text,
            english: 'as written',
          ),
          Spoken() => WordGloss(
            pinyin: piece.word.written,
            english:
                await breakdown.glossOf(piece.characters!, piece.key!) ?? '—',
          ),
        },
    ];
  }
}
