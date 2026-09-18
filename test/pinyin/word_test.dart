import 'package:flutter_test/flutter_test.dart';
import 'package:kouyu/pinyin/composition.dart';
import 'package:kouyu/pinyin/keyboard_layout.dart';
import 'package:kouyu/pinyin/syllable.dart';
import 'package:kouyu/pinyin/tone.dart';
import 'package:kouyu/pinyin/word.dart';

InitialKey key(String label) =>
    initialKeys.firstWhere((key) => key.label == label);

Composition type(Composition from, String initial, String rime, Tone tone) =>
    from.withInitial(key(initial)).withRime(rime).commit(tone);

void main() {
  /// `wǒ jiào` — two words, ready for a name after them.
  Composition myNameIs() {
    var composition = type(const Composition(), 'w', 'uo', Tone.third);
    composition = composition.space();
    return type(composition, 'j', 'iao', Tone.fourth);
  }

  test('a name is a word of its own, carried as written', () {
    final composition = myNameIs().withLiteral('Steve');

    expect(composition.text, 'wǒ jiào Steve');
    expect(composition.words.last, const Literal('Steve'));
    expect(composition.caret, composition.end);
  });

  test('is trimmed, and nothing is added for an empty one', () {
    final composition = myNameIs();
    expect(composition.withLiteral('  Steve  ').text, 'wǒ jiào Steve');
    expect(composition.withLiteral('   '), same(composition));
  });

  // The caret goes either side of a name and never into it: there is no
  // meaningful position inside `Steve` for a syllable to land.
  test('the caret treats it as one unit', () {
    final composition = myNameIs().withLiteral('Steve');
    expect(composition.words.last.length, 1);

    final before = composition.movedTo(const Caret(word: 2, syllable: 0));
    expect(before.textBefore, 'wǒ jiào ');
    expect(before.textAfter, 'Steve');

    final after = composition.movedTo(const Caret(word: 2, syllable: 1));
    expect(after.textBefore, 'wǒ jiào Steve');
    expect(after.textAfter, isEmpty);
  });

  test('a syllable typed against a name starts its own word', () {
    final composition = myNameIs().withLiteral('Steve');

    // At the end of the line, after the name.
    final after = type(composition, 'm', 'a', Tone.neutral);
    expect(after.text, 'wǒ jiào Steve ma');

    // And before it, without going inside it.
    final at = composition.movedTo(const Caret(word: 2, syllable: 0));
    expect(type(at, 'm', 'a', Tone.neutral).text, 'wǒ jiào ma Steve');
  });

  test('backspace takes the whole name, not a letter of it', () {
    final composition = myNameIs().withLiteral('Steve');
    final back = composition.backspace();

    expect(back.text, 'wǒ jiào');
    expect(back.caret, back.end);
    expect(back.words.whereType<Literal>(), isEmpty);
  });

  test('correcting one replaces it in place', () {
    final composition = myNameIs().withLiteral('Steve');
    // What tapping the name on screen does: the caret goes to it, and the
    // editor comes back with the new spelling.
    final corrected = composition
        .movedTo(const Caret(word: 2, syllable: 0))
        .withLiteral('Stephen');

    expect(corrected.text, 'wǒ jiào Stephen');
    expect(
      corrected.words.whereType<Literal>().length,
      1,
      reason: 'corrected, not added alongside',
    );
  });

  test('space is refused against a name, which is already its own word', () {
    final composition = myNameIs().withLiteral('Steve');
    expect(composition.space(), same(composition));
  });

  test('retoning leaves a name alone', () {
    final composition = myNameIs().withLiteral('Steve');
    expect(composition.retoned(2, 0, Tone.first), same(composition));
  });

  test('names survive being typed around', () {
    var composition = const Composition().withLiteral('Steve');
    expect(composition.text, 'Steve');

    composition = composition.movedTo(const Caret(word: 0, syllable: 0));
    composition = type(composition, 'w', 'uo', Tone.third);
    expect(composition.text, 'wǒ Steve');
  });

  group('the word itself', () {
    test('a name is indivisible', () {
      const steve = Literal('Steve');
      expect(steve.length, 1);
      expect(steve.writtenTake(0), isEmpty);
      expect(steve.writtenTake(1), 'Steve');
      expect(steve.writtenSkip(0), 'Steve');
      expect(steve.writtenSkip(1), isEmpty);
    });

    test('a spoken word is keyed for the dictionary', () {
      final word = Spoken([
        Syllable(initial: 'n', rime: 'i', tone: Tone.third),
        Syllable(initial: 'h', rime: 'ao', tone: Tone.third),
      ]);
      expect(word.written, 'nǐhǎo');
      expect(word.key, 'ni3 hao3');
      expect(word.writtenTake(1), 'nǐ');
      expect(word.writtenSkip(1), 'hǎo');
    });
  });
}
