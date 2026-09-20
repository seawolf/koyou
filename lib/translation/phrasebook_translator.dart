import '../pinyin/reading.dart';
import '../pinyin/word.dart';
import 'english_translator.dart';
import 'translator.dart';

/// A short hand-written list of phrases, asked before the dictionary.
///
/// It exists for the gap a dictionary structurally cannot fill: whole
/// utterances that are not themselves dictionary entries. `wǒ ài nǐ` is three
/// ordinary words, so CC-CEDICT has no entry for it and glossing gives
/// "I; me; love; you" — true, and not what anyone says.
///
/// Kept deliberately small. It is not a translation strategy, it is a patch
/// over specific phrases, and anything that belongs in a dictionary belongs in
/// the dictionary.
class PhrasebookTranslator implements Translator {
  const PhrasebookTranslator();

  @override
  Future<Translation?> translate(TranslationRequest request) async {
    final phrase = request.written.toLowerCase();
    for (final entry in phrasebook) {
      // A whole utterance, hand-checked: nothing beats it.
      if (entry.pinyin == phrase) {
        return Translation(entry.english, matchedWhole: true);
      }
    }
    return null;
  }
}

/// The same list read the other way: English in, pinyin out.
///
/// Asked before the English index for the same reason as above, and for one
/// more. Inverting a dictionary cannot answer "hello": CC-CEDICT glosses 你好
/// "hello; hi", but 你好 is absent from the HSK vocabulary the ranking comes
/// from — genuinely absent, the syllabus counts 你 and 好 separately — so it
/// has no rank to sort by and loses to 好, whose eighth sense is "(after a form
/// of address) hello". Greetings are the first thing anybody types, so they are
/// the clearest case for a hand-written answer.
class EnglishPhrasebook implements EnglishTranslator {
  const EnglishPhrasebook();

  @override
  Future<Said?> say(String english) async {
    final asked = _plain(english);
    if (asked.isEmpty) return null;
    for (final entry in phrasebook) {
      if (_plain(entry.english) != asked) continue;
      return Said(
        options: [Rendering(words: entry.words, meaning: entry.english)],
        phrasing: Phrasing.entry,
      );
    }
    return null;
  }

  /// Enough normalising to match how someone would type it, and no more.
  ///
  /// The list is a handful of phrases long; anything cleverer than case and
  /// punctuation would be tuning a matcher against nine strings.
  static String _plain(String english) =>
      english.toLowerCase().replaceAll(_punctuation, '').trim();
}

final _punctuation = RegExp(r"[^a-z0-9' ]");

/// One phrase, written both ways round.
///
/// [pinyin] is what the composed line looks like and [keys] is what it is made
/// of, one dictionary key per word. Both are stored because both are wanted:
/// the written form is what makes this file readable to whoever edits it next,
/// and the keys are what turn it back into syllables the keyboard could have
/// built. A test asserts the two say the same thing, so they cannot drift.
class Phrase {
  const Phrase({
    required this.pinyin,
    required this.keys,
    required this.english,
  });

  final String pinyin;
  final List<String> keys;
  final String english;

  /// The phrase as words, for putting into the input area.
  List<Word> get words => [for (final key in keys) Spoken(syllablesFor(key)!)];
}

/// Keyed on the pinyin as written, tone marks included, because that is what
/// makes it readable to whoever edits it next.
const List<Phrase> phrasebook = [
  // The one greeting that has to be written out. "goodbye", "sorry",
  // "thank you" and "excuse me" all resolve correctly by inverting the
  // dictionary, so they are not here; "hello" does not, for the reason in
  // [EnglishPhrasebook].
  // Two words, as the rest of the list spells it and as the keyboard makes
  // you type it. The pinyin direction does not need this row either way: the
  // dictionary finds 你好 from `nǐ hǎo` and `nǐhǎo` alike, because a key
  // drops word breaks.
  Phrase(pinyin: 'nǐ hǎo', keys: ['ni3', 'hao3'], english: 'hello'),
  Phrase(
    pinyin: 'wǒ ài nǐ',
    keys: ['wo3', 'ai4', 'ni3'],
    english: 'I love you',
  ),
  Phrase(
    pinyin: 'nǐ hǎo shìjiè',
    keys: ['ni3', 'hao3', 'shi4 jie4'],
    english: 'hello, world',
  ),
  Phrase(
    pinyin: 'nǐ hǎo ma',
    keys: ['ni3', 'hao3', 'ma5'],
    english: 'how are you?',
  ),
  Phrase(
    pinyin: 'wǒ bù zhīdào',
    keys: ['wo3', 'bu4', 'zhi1 dao4'],
    english: "I don't know",
  ),
  Phrase(
    pinyin: 'nǐ jiào shénme míngzi',
    keys: ['ni3', 'jiao4', 'shen2 me5', 'ming2 zi5'],
    english: "what's your name?",
  ),
  Phrase(
    pinyin: 'wǒ shì yīngguórén',
    keys: ['wo3', 'shi4', 'ying1 guo2 ren2'],
    english: 'I am British',
  ),
  Phrase(
    pinyin: 'qǐng zài shuō yī cì',
    keys: ['qing3', 'zai4', 'shuo1', 'yi1', 'ci4'],
    english: 'please say that again',
  ),
  Phrase(
    pinyin: 'wǒ tīng bù dǒng',
    keys: ['wo3', 'ting1', 'bu4', 'dong3'],
    english: "I don't understand",
  ),
];
