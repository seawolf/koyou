import 'package:flutter_test/flutter_test.dart';
import 'package:kouyu/pinyin/composition.dart';
import 'package:kouyu/pinyin/tone.dart';

void main() {
  /// Types a syllable the way the keyboard does: initial, rime, then tone.
  Composition type(
    Composition composition,
    String initial,
    String rime,
    Tone tone,
  ) => composition.withInitial(initial).withRime(rime).commit(tone);

  test('starts empty', () {
    const composition = Composition();
    expect(composition.isEmpty, isTrue);
    expect(composition.text, isEmpty);
    expect(composition.preview, isEmpty);
  });

  test('a syllable is committed by choosing its tone', () {
    final composition = type(const Composition(), 'n', 'i', Tone.third);
    expect(composition.text, 'nǐ');
    expect(composition.isEmpty, isFalse);
  });

  test('syllables run together inside a word', () {
    var composition = type(const Composition(), 'sh', 'i', Tone.fourth);
    composition = type(composition, 'j', 'ie', Tone.fourth);
    expect(composition.text, 'shìjiè');
  });

  test('space separates words', () {
    var composition = type(const Composition(), 'n', 'i', Tone.third);
    composition = composition.space();
    composition = type(composition, 'h', 'ao', Tone.third);
    expect(composition.text, 'nǐ hǎo');
  });

  group('the draft', () {
    test('previews untoned, since the tone completes it', () {
      final composition = const Composition().withInitial('n').withRime('i');
      expect(composition.text, isEmpty);
      expect(composition.preview, 'ni');
    });

    test('shows a lone initial while it waits for a rime', () {
      final composition = const Composition().withInitial('zh');
      expect(composition.preview, 'zh');
      expect(composition.draft.isCommittable, isFalse);
    });

    test(
      'previews against committed text, spaced only across a word break',
      () {
        var composition = type(const Composition(), 'n', 'i', Tone.third);
        expect(composition.withInitial('h').withRime('ao').preview, 'nǐhao');

        composition = composition.space();
        expect(composition.withInitial('h').withRime('ao').preview, 'nǐ hao');
      },
    );

    test('is replaced, not appended to, when a key is pressed twice', () {
      final composition = const Composition()
          .withInitial('n')
          .withInitial('h')
          .withRime('i')
          .withRime('ao');
      expect(composition.preview, 'hao');
    });
  });

  group('refusals', () {
    // Every syllable needs a rime, so a tone alone must not commit anything.
    test('a tone with no rime commits nothing', () {
      expect(const Composition().commit(Tone.first).isEmpty, isTrue);
      expect(
        const Composition().withInitial('n').commit(Tone.first).text,
        isEmpty,
      );
    });

    test('space is refused mid-syllable rather than guessing', () {
      final composition = const Composition().withInitial('n').withRime('i');
      expect(composition.space().preview, 'ni');
      expect(composition.space().text, isEmpty);
    });

    test('space is refused when the current word is empty', () {
      var composition = type(const Composition(), 'n', 'i', Tone.third);
      composition = composition.space();
      expect(composition.space().text, 'nǐ');
      expect(composition.space().words.length, 2);
    });
  });

  group('backspace', () {
    test('takes the rime, then the initial, then the last syllable', () {
      var composition = type(const Composition(), 'n', 'i', Tone.third);
      composition = composition.withInitial('h').withRime('ao');

      composition = composition.backspace();
      expect(composition.preview, 'nǐh');

      composition = composition.backspace();
      expect(composition.preview, 'nǐ');

      composition = composition.backspace();
      expect(composition.isEmpty, isTrue);
    });

    test('removes a word break', () {
      var composition = type(const Composition(), 'n', 'i', Tone.third);
      composition = composition.space();
      expect(composition.words.length, 2);

      composition = composition.backspace();
      expect(composition.words.length, 1);
      expect(composition.text, 'nǐ');
    });

    test('does nothing when there is nothing to remove', () {
      expect(const Composition().backspace().isEmpty, isTrue);
    });
  });

  test('clearing resets everything', () {
    var composition = type(const Composition(), 'n', 'i', Tone.third);
    composition = composition.space().withInitial('h');
    expect(composition.cleared().isEmpty, isTrue);
  });

  test('editing does not mutate the previous value', () {
    final first = type(const Composition(), 'n', 'i', Tone.third);
    final second = type(first, 'h', 'ao', Tone.third);
    expect(first.text, 'nǐ');
    expect(second.text, 'nǐhǎo');
  });
}
