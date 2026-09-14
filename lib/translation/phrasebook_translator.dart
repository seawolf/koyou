import 'translator.dart';

/// A short hand-written list of phrases, asked before the dictionary.
///
/// It exists for the gap a dictionary structurally cannot fill: whole
/// utterances that are not themselves dictionary entries. `wǒ ài nǐ` is three
/// ordinary words, so CC-CEDICT has no entry for it and glossing gives
/// "I; me · to love · you" — true, and not what anyone says.
///
/// Kept deliberately small. It is not a translation strategy, it is a patch
/// over specific phrases, and anything that belongs in a dictionary belongs in
/// the dictionary.
class PhrasebookTranslator implements Translator {
  const PhrasebookTranslator();

  @override
  Future<Translation?> translate(TranslationRequest request) async {
    final phrase = request.written.toLowerCase();
    final match = _phrasebook[phrase];
    // A whole utterance, hand-checked: nothing beats it.
    return match == null ? null : Translation(match, matchedWhole: true);
  }
}

/// Keyed on the pinyin as written, tone marks included, because that is what
/// makes it readable to whoever edits it next.
const Map<String, String> _phrasebook = {
  'wǒ ài nǐ': 'I love you',
  'nǐ hǎo shìjiè': 'hello, world',
  'nǐ hǎo ma': 'how are you?',
  'wǒ bù zhīdào': "I don't know",
  'nǐ jiào shénme míngzi': "what's your name?",
  'wǒ shì yīngguórén': 'I am British',
  'qǐng zài shuō yī cì': 'please say that again',
  'wǒ tīng bù dǒng': "I don't understand",
};
