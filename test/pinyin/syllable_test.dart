import 'package:flutter_test/flutter_test.dart';
import 'package:kouyu/pinyin/syllable.dart';
import 'package:kouyu/pinyin/tone.dart';

void main() {
  String write(String initial, String rime, Tone tone) =>
      Syllable(initial: initial, rime: rime, tone: tone).written;

  group('tone mark placement', () {
    // An a wins, then an o, then an e.
    test('an a takes the mark ahead of any other vowel', () {
      expect(write('h', 'ao', Tone.third), 'hǎo');
      expect(write('x', 'iao', Tone.third), 'xiǎo');
      expect(write('zh', 'uang', Tone.fourth), 'zhuàng');
      expect(write('j', 'ian', Tone.fourth), 'jiàn');
    });

    test('an o takes the mark when there is no a', () {
      expect(write('g', 'uo', Tone.second), 'guó');
      expect(write('', 'ou', Tone.third), 'ǒu');
      expect(write('zh', 'ong', Tone.first), 'zhōng');
    });

    test('an e takes the mark when there is no a or o', () {
      expect(write('j', 'ie', Tone.fourth), 'jiè');
      expect(write('h', 'en', Tone.third), 'hěn');
      expect(write('l', 'üe', Tone.fourth), 'lüè');
      expect(write('', 'er', Tone.fourth), 'èr');
    });

    // The clause people get wrong by hand: with no a, o or e, the mark goes on
    // the *last* vowel, not the first.
    test('otherwise the mark goes on the last vowel', () {
      expect(write('n', 'iu', Tone.second), 'niú');
      expect(write('h', 'ui', Tone.fourth), 'huì');
      expect(write('sh', 'ui', Tone.third), 'shuǐ');
      expect(write('l', 'un', Tone.fourth), 'lùn');
      expect(write('n', 'i', Tone.third), 'nǐ');
    });

    test('ü carries the mark when it is the only vowel', () {
      expect(write('n', 'ü', Tone.third), 'nǚ');
      expect(write('l', 'ü', Tone.fourth), 'lǜ');
    });

    test('the neutral tone adds no mark', () {
      expect(write('m', 'a', Tone.neutral), 'ma');
      expect(write('n', 'i', Tone.neutral), 'ni');
      expect(write('', 'i', Tone.neutral), 'yi');
    });
  });

  group('spelling with no initial', () {
    test('i, u and ü rimes gain a y or w', () {
      expect(write('', 'i', Tone.first), 'yī');
      expect(write('', 'u', Tone.third), 'wǔ');
      expect(write('', 'ü', Tone.third), 'yǔ');
      expect(write('', 'ia', Tone.fourth), 'yà');
      expect(write('', 'uo', Tone.third), 'wǒ');
      expect(write('', 'üe', Tone.fourth), 'yuè');
    });

    // These three go further than swapping in a y or w, which is why the
    // spellings are a table rather than a substitution.
    test('iu, ui and un are respelled you, wei and wen', () {
      expect(write('', 'iu', Tone.third), 'yǒu');
      expect(write('', 'ui', Tone.fourth), 'wèi');
      expect(write('', 'un', Tone.second), 'wén');
    });

    test('plain rimes are unchanged', () {
      expect(write('', 'a', Tone.first), 'ā');
      expect(write('', 'ai', Tone.fourth), 'ài');
      expect(write('', 'ang', Tone.second), 'áng');
    });
  });

  group('spelling after j, q and x', () {
    // There is no u/ü contrast after these, so the diaeresis is dropped.
    test('ü is written u', () {
      expect(write('j', 'ü', Tone.first), 'jū');
      expect(write('q', 'ü', Tone.fourth), 'qù');
      expect(write('x', 'ü', Tone.first), 'xū');
      expect(write('j', 'üe', Tone.second), 'jué');
      expect(write('j', 'üan', Tone.fourth), 'juàn');
      expect(write('j', 'ün', Tone.fourth), 'jùn');
    });

    test('but n and l keep it, because there the contrast is real', () {
      expect(write('n', 'ü', Tone.third), 'nǚ');
      expect(write('n', 'u', Tone.fourth), 'nù');
      expect(write('l', 'ü', Tone.fourth), 'lǜ');
      expect(write('l', 'u', Tone.fourth), 'lù');
    });
  });

  test('equality is by parts, not by spelling', () {
    expect(
      const Syllable(initial: 'n', rime: 'i', tone: Tone.third),
      const Syllable(initial: 'n', rime: 'i', tone: Tone.third),
    );
    expect(
      const Syllable(initial: 'n', rime: 'i', tone: Tone.third),
      isNot(const Syllable(initial: 'n', rime: 'i', tone: Tone.second)),
    );
  });
}
