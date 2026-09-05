import 'package:flutter_test/flutter_test.dart';
import 'package:kouyu/pinyin/syllable.dart';
import 'package:kouyu/pinyin/tone.dart';
import 'package:kouyu/translation/phrasebook_translator.dart';
import 'package:kouyu/translation/translator.dart';

Syllable syllable(String initial, String rime, Tone tone) =>
    Syllable(initial: initial, rime: rime, tone: tone);

void main() {
  const translator = PhrasebookTranslator();

  // wǒ ài nǐ — three ordinary words, so no dictionary has an entry for it.
  final iLoveYou = TranslationRequest([
    [syllable('', 'uo', Tone.third)],
    [syllable('', 'ai', Tone.fourth)],
    [syllable('n', 'i', Tone.third)],
  ]);

  test('matches a whole utterance the dictionary cannot have', () async {
    expect(iLoveYou.written, 'wǒ ài nǐ');
    expect(
      await translator.translate(iLoveYou),
      const Translation('I love you'),
    );
  });

  test('leaves anything else to the dictionary behind it', () async {
    final justYou = TranslationRequest([
      [syllable('n', 'i', Tone.third)],
    ]);
    expect(await translator.translate(justYou), isNull);
  });

  // Tones distinguish words, so a phrasebook must not treat them as noise.
  test('does not match when the tones are wrong', () async {
    final wrongTone = TranslationRequest([
      [syllable('', 'uo', Tone.third)],
      [syllable('', 'ai', Tone.first)],
      [syllable('n', 'i', Tone.third)],
    ]);
    expect(await translator.translate(wrongTone), isNull);
  });

  test('has nothing to say about empty input', () async {
    expect(await translator.translate(const TranslationRequest([])), isNull);
  });
}
