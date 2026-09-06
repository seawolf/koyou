import 'package:flutter_test/flutter_test.dart';
import 'package:kouyu/pinyin/composition.dart';
import 'package:kouyu/pinyin/keyboard_layout.dart';
import 'package:kouyu/pinyin/tone.dart';

void main() {
  InitialKey key(String label) =>
      initialKeys.firstWhere((initial) => initial.label == label);

  /// Types a syllable the way the keyboard does: initial, rime, then tone.
  Composition type(
    Composition composition,
    String initial,
    String rime,
    Tone tone,
  ) => composition.withInitial(key(initial)).withRime(rime).commit(tone);

  test('starts empty, at the first stage', () {
    const composition = Composition();
    expect(composition.isEmpty, isTrue);
    expect(composition.text, isEmpty);
    expect(composition.stage, ComposeStage.initial);
  });

  test('advances a stage per choice', () {
    var composition = const Composition().withInitial(key('n'));
    expect(composition.stage, ComposeStage.rime);

    composition = composition.withRime('i');
    expect(composition.stage, ComposeStage.tone);

    composition = composition.commit(Tone.third);
    expect(
      composition.stage,
      ComposeStage.initial,
      reason: 'ready for the next',
    );
    expect(composition.text, 'nǐ');
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

  // The reason w and y are offered as starting points at all.
  test('w reaches wǒ, which has no initial consonant', () {
    final composition = type(const Composition(), 'w', 'uo', Tone.third);
    expect(composition.text, 'wǒ');
  });

  test('the bare-vowel key is a choice, not the absence of one', () {
    final composition = const Composition().withInitial(key('a'));
    expect(composition.isEmpty, isFalse);
    expect(composition.stage, ComposeStage.rime);
    expect(type(const Composition(), 'a', 'an', Tone.first).text, 'ān');
  });

  group('the draft', () {
    test('previews untoned, since the tone completes it', () {
      final composition = const Composition()
          .withInitial(key('n'))
          .withRime('i');
      expect(composition.text, isEmpty);
      expect(composition.preview, 'ni');
    });

    test('shows the initial alone while it waits for a rime', () {
      expect(const Composition().withInitial(key('zh')).preview, 'zh');
      // The bare-vowel key spells nothing, so there is nothing to show yet.
      expect(const Composition().withInitial(key('a')).preview, isEmpty);
    });

    test('offers the five real candidates once a rime is chosen', () {
      final draft = const Composition()
          .withInitial(key('n'))
          .withRime('i')
          .draft;
      expect(draft.candidates.map((candidate) => candidate.written), [
        'nī',
        'ní',
        'nǐ',
        'nì',
        'ni',
      ]);
    });

    test('labels the rime as the learner pressed it, not phonologically', () {
      // Under w, `uo` was pressed as `o`, because the syllable is written wo.
      final draft = const Composition()
          .withInitial(key('w'))
          .withRime('uo')
          .draft;
      expect(draft.rime, 'uo');
      expect(draft.rimeLabel, 'o');
    });

    test(
      'previews against committed text, spaced only across a word break',
      () {
        var composition = type(const Composition(), 'n', 'i', Tone.third);
        expect(
          composition.withInitial(key('h')).withRime('ao').preview,
          'nǐhao',
        );

        composition = composition.space();
        expect(
          composition.withInitial(key('h')).withRime('ao').preview,
          'nǐ hao',
        );
      },
    );

    // Rimes depend on the initial, so a rime kept across a change of initial
    // could leave a syllable Mandarin does not have.
    test('changing the initial drops the rime', () {
      final composition = const Composition()
          .withInitial(key('j'))
          .withRime('ü')
          .withInitial(key('z'));
      expect(composition.draft.rime, isNull);
      expect(composition.stage, ComposeStage.rime);
    });
  });

  group('going back', () {
    test('to the rime stage keeps the initial', () {
      final composition = const Composition()
          .withInitial(key('n'))
          .withRime('i')
          .backTo(ComposeStage.rime);
      expect(composition.draft.initial?.label, 'n');
      expect(composition.draft.rime, isNull);
      expect(composition.stage, ComposeStage.rime);
    });

    test('to the initial stage clears the draft but keeps committed text', () {
      var composition = type(const Composition(), 'n', 'i', Tone.third);
      composition = composition
          .withInitial(key('h'))
          .withRime('ao')
          .backTo(ComposeStage.initial);
      expect(composition.draft.isEmpty, isTrue);
      expect(composition.text, 'nǐ');
    });
  });

  group('refusals', () {
    test('a tone with no rime commits nothing', () {
      expect(const Composition().commit(Tone.first).isEmpty, isTrue);
      expect(
        const Composition().withInitial(key('n')).commit(Tone.first).text,
        isEmpty,
      );
    });

    test('space is refused mid-syllable rather than guessing', () {
      final composition = const Composition()
          .withInitial(key('n'))
          .withRime('i');
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
    test('steps back a stage, then a syllable', () {
      var composition = type(const Composition(), 'n', 'i', Tone.third);
      composition = composition.withInitial(key('h')).withRime('ao');

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

  group('the caret', () {
    /// `wǒ mài shū` — two words, the middle one a single syllable.
    Composition line() {
      var composition = type(const Composition(), 'w', 'uo', Tone.third);
      composition = composition.space();
      composition = type(composition, 'm', 'ai', Tone.fourth);
      composition = composition.space();
      return type(composition, 'sh', 'u', Tone.first);
    }

    test('typing leaves it at the end', () {
      final composition = line();
      expect(composition.caret, composition.end);
      expect(composition.textBefore, 'wǒ mài shū');
      expect(composition.textAfter, isEmpty);
    });

    test('splits the line where it sits', () {
      final composition = line().movedTo(const Caret(word: 1, syllable: 0));
      expect(composition.textBefore, 'wǒ ');
      expect(composition.textAfter, 'mài shū');
      // The halves still reassemble the line.
      expect(composition.textBefore + composition.textAfter, 'wǒ mài shū');
      expect(composition.text, 'wǒ mài shū', reason: 'moving edits nothing');
    });

    test('inserts where it sits, and moves on', () {
      final moved = line().movedTo(const Caret(word: 1, syllable: 0));
      final inserted = type(moved, 'h', 'ao', Tone.third);

      expect(inserted.text, 'wǒ hǎomài shū');
      expect(inserted.caret, const Caret(word: 1, syllable: 1));
      // And the next syllable lands after the first, not before it.
      expect(type(inserted, 'b', 'u', Tone.fourth).text, 'wǒ hǎobùmài shū');
    });

    test('deletes what is behind it, not what is at the end', () {
      final moved = line().movedTo(const Caret(word: 1, syllable: 1));
      expect(moved.backspace().text, 'wǒ shū');
      expect(moved.backspace().caret, const Caret(word: 1, syllable: 0));
    });

    // At the start of a word what is behind the caret is the word break.
    test('at a word start, deletes the break and joins the words', () {
      final moved = line().movedTo(const Caret(word: 1, syllable: 0));
      final joined = moved.backspace();

      expect(joined.text, 'wǒmài shū');
      expect(joined.caret, const Caret(word: 0, syllable: 1));
      expect(joined.textBefore, 'wǒ');
      expect(joined.textAfter, 'mài shū');
    });

    test('space splits the word it is inside', () {
      var composition = type(const Composition(), 'sh', 'i', Tone.fourth);
      composition = type(composition, 'j', 'ie', Tone.fourth);
      expect(composition.text, 'shìjiè');

      final split = composition
          .movedTo(const Caret(word: 0, syllable: 1))
          .space();
      expect(split.text, 'shì jiè');
      expect(split.caret, const Caret(word: 1, syllable: 0));
    });

    test('space is refused at the start of a word', () {
      final moved = line().movedTo(const Caret(word: 1, syllable: 0));
      expect(moved.space(), same(moved), reason: 'nothing to break off');
    });

    test('moving drops a half-typed syllable', () {
      final drafting = line().withInitial(key('h')).withRime('ao');
      expect(drafting.preview, 'wǒ mài shūhao');

      final moved = drafting.movedTo(const Caret(word: 0, syllable: 0));
      expect(moved.draft.isEmpty, isTrue);
      expect(moved.preview, 'wǒ mài shū');
    });

    test('is clamped to somewhere it can be', () {
      final composition = line();
      expect(
        composition.movedTo(const Caret(word: 9, syllable: 9)).caret,
        composition.end,
      );
      expect(
        composition.movedTo(const Caret(word: -1, syllable: -1)).caret,
        const Caret(word: 0, syllable: 0),
      );
    });

    test('clearing puts it back to the start', () {
      expect(line().cleared().caret, const Caret(word: 0, syllable: 0));
    });

    // Everything typed after a reposition has to end up in the right place,
    // so this walks a whole edit rather than one operation.
    test('a whole insertion in the middle', () {
      // wǒ shū, then go back and put mài between them.
      var composition = type(const Composition(), 'w', 'uo', Tone.third);
      composition = composition.space();
      composition = type(composition, 'sh', 'u', Tone.first);
      expect(composition.text, 'wǒ shū');

      composition = composition.movedTo(const Caret(word: 1, syllable: 0));
      composition = type(composition, 'm', 'ai', Tone.fourth);
      expect(composition.text, 'wǒ màishū');

      // A space after it makes them separate words.
      composition = composition.space();
      expect(composition.text, 'wǒ mài shū');
      expect(composition.caret, const Caret(word: 2, syllable: 0));
    });
  });

  test('clearing resets everything', () {
    var composition = type(const Composition(), 'n', 'i', Tone.third);
    composition = composition.space().withInitial(key('h'));
    expect(composition.cleared().isEmpty, isTrue);
  });

  test('editing does not mutate the previous value', () {
    final first = type(const Composition(), 'n', 'i', Tone.third);
    final second = type(first, 'h', 'ao', Tone.third);
    expect(first.text, 'nǐ');
    expect(second.text, 'nǐhǎo');
  });
}
