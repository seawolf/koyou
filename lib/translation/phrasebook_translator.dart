import 'translator.dart';

/// A stand-in [Translator] backed by a hand-written phrasebook.
///
/// This is not translation and does not pretend to be. It matches whole
/// phrases, falls back to glossing word by word, and otherwise returns null.
/// It exists so the compose-and-translate path runs end to end while a real
/// model is still a plan — swapping it out means writing one [Translator] and
/// changing one argument at the call site.
class PhrasebookTranslator implements Translator {
  const PhrasebookTranslator();

  @override
  Future<Translation?> translate(String pinyin) async {
    final phrase = _normalise(pinyin);
    if (phrase.isEmpty) return null;

    final whole = _phrasebook[phrase];
    if (whole != null) return Translation(whole);

    final words = phrase.split(' ');
    if (words.length < 2) return null;
    final glosses = [for (final word in words) _phrasebook[word]];
    if (glosses.any((gloss) => gloss == null)) return null;
    return Translation(glosses.join(' · '), wordByWord: true);
  }

  String _normalise(String pinyin) =>
      pinyin.toLowerCase().trim().replaceAll(RegExp(r'\s+'), ' ');
}

/// Enough entries to exercise the path, no more. Every key here is reachable
/// from the keyboard, which is the only reason to trust it as a fixture.
const Map<String, String> _phrasebook = {
  'nǐ': 'you',
  'hǎo': 'good',
  'nǐ hǎo': 'hello',
  'nǐ hǎo shìjiè': 'hello, world',
  'shìjiè': 'world',
  'wǒ': 'I; me',
  'wǒmen': 'we; us',
  'tā': 'he; she; it',
  'shì': 'to be',
  'bù': 'not',
  'hěn': 'very',
  'ài': 'to love',
  'wǒ ài nǐ': 'I love you',
  'xièxie': 'thank you',
  'zàijiàn': 'goodbye',
  'duìbuqǐ': 'sorry',
  'qǐng': 'please',
  'shuǐ': 'water',
  'chá': 'tea',
  'dà': 'big',
  'xiǎo': 'small',
  'māma': 'mum',
  'zhōngguó': 'China',
  'zhōngwén': 'Chinese',
  'yī': 'one',
  'èr': 'two',
  'sān': 'three',
};
