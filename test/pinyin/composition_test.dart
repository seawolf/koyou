import 'package:flutter_test/flutter_test.dart';
import 'package:kouyu/pinyin/composition.dart';
import 'package:kouyu/pinyin/keyboard_layout.dart';
import 'package:kouyu/pinyin/syllable.dart';
import 'package:kouyu/pinyin/tone.dart';
import 'package:kouyu/pinyin/word.dart';

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

  group('reopening a syllable', () {
    /// `nǐ hǎo`.
    Composition line() {
      var composition = type(const Composition(), 'n', 'i', Tone.third);
      composition = composition.space();
      return type(composition, 'h', 'ao', Tone.third);
    }

    test('back to the tone keeps the letters and asks again', () {
      final reopened = line().redraft(1, 0, ComposeStage.tone);

      expect(reopened.stage, ComposeStage.tone);
      expect(reopened.text, 'nǐ', reason: 'the syllable came out of the line');
      // Untoned, because the tone is the thing being chosen again.
      expect(reopened.preview, 'nǐ hao');
      expect(reopened.caret, const Caret(word: 1, syllable: 0));

      // And choosing puts it back exactly where it was.
      expect(reopened.commit(Tone.fourth).text, 'nǐ hào');
    });

    test('back to the rime asks for what follows the initial', () {
      final reopened = line().redraft(1, 0, ComposeStage.rime);

      expect(reopened.stage, ComposeStage.rime);
      expect(reopened.preview, 'nǐ h');
      expect(reopened.withRime('en').commit(Tone.third).text, 'nǐ hěn');
    });

    // A syllable in the middle has to come back to the middle.
    test('puts the new syllable back where the old one was', () {
      var composition = type(const Composition(), 'n', 'i', Tone.third);
      composition = type(composition, 'h', 'ao', Tone.third);
      composition = type(composition, 'm', 'a', Tone.neutral);
      expect(composition.text, 'nǐhǎoma');

      final reopened = composition.redraft(0, 1, ComposeStage.tone);
      expect(reopened.preview, 'nǐhaoma');
      expect(reopened.commit(Tone.fourth).text, 'nǐhàoma');
    });

    test(
      'going back to the initial is refused, being what backspace is for',
      () {
        final composition = line();
        expect(
          composition.redraft(1, 0, ComposeStage.initial),
          same(composition),
        );
      },
    );

    test('a position outside the line is refused', () {
      final composition = line();
      expect(composition.redraft(9, 0, ComposeStage.tone), same(composition));
      expect(composition.redraft(1, 9, ComposeStage.tone), same(composition));
    });

    test('a name has no stages to go back to', () {
      final composition = line().withLiteral('Steve');
      expect(composition.redraft(2, 0, ComposeStage.tone), same(composition));
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
  group('a line worked out elsewhere', () {
    test('arrives ready to be edited, caret at the end', () {
      final composition = Composition.of([
        Spoken([Syllable(initial: 'w', rime: 'o', tone: Tone.third)]),
        Spoken([Syllable(rime: 'ai', tone: Tone.fourth)]),
      ]);
      expect(composition.preview, 'wǒ ài');
      // Where typing would have left it, so the next key carries on rather
      // than inserting into the middle.
      expect(composition.caret, composition.end);
      expect(composition.stage, ComposeStage.initial);
    });

    test('drops empty words rather than showing a stray space', () {
      final composition = Composition.of([
        const Spoken(),
        Spoken([Syllable(initial: 'w', rime: 'o', tone: Tone.third)]),
        const Spoken(),
      ]);
      expect(composition.words, hasLength(1));
      expect(composition.preview, 'wǒ');
    });

    test('nothing at all is just an empty line', () {
      expect(Composition.of(const []).isEmpty, isTrue);
      expect(Composition.of(const [Spoken()]).isEmpty, isTrue);
    });

    test('carries a word that is not Mandarin', () {
      final composition = Composition.of([
        Spoken([Syllable(initial: 'w', rime: 'o', tone: Tone.third)]),
        const Literal('Steve'),
      ]);
      expect(composition.preview, 'wǒ Steve');
      expect(composition.words.last, const Literal('Steve'));
    });

    test('can be edited the moment it lands', () {
      // The reason an answer is words and not text. Every rule already
      // written applies to it: retone one syllable, backspace off the end.
      final composition = Composition.of([
        Spoken([Syllable(initial: 'w', rime: 'o', tone: Tone.third)]),
        Spoken([Syllable(rime: 'ai', tone: Tone.fourth)]),
      ]);
      expect(composition.retoned(0, 0, Tone.first).preview, 'wō ài');
      // Two presses, as for a line that was typed: the syllable goes, then
      // the word break.
      expect(composition.backspace().preview, 'wǒ ');
      expect(composition.backspace().backspace().preview, 'wǒ');
    });
  });

  group('typing on a physical keyboard', () {
    /// [letters] typed one at a time, failing the test at the first refusal.
    Composition typing(
      String letters, [
      Composition from = const Composition(),
    ]) {
      var composition = from;
      for (final letter in letters.split('')) {
        final next = composition.withLetter(letter);
        expect(next, isNotNull, reason: '$letter after ${composition.preview}');
        composition = next!;
      }
      return composition;
    }

    test('spells a syllable as it is written, then takes a tone', () {
      final composition = typing('shang').commit(Tone.fourth);
      expect(composition.text, 'shàng');
    });

    // The visual cue the user asked for: each letter moves on at once, and
    // the h of a digraph revises the initial rather than waiting for it.
    test('moves on at the first letter, and an h makes it a digraph', () {
      final s = typing('s');
      expect(s.draft.initial!.label, 's');
      expect(s.stage, ComposeStage.rime);

      final sh = typing('sh');
      expect(sh.draft.initial!.label, 'sh');
      expect(sh.stage, ComposeStage.rime);

      expect(typing('zh').draft.initial!.label, 'zh');
      expect(typing('ch').draft.initial!.label, 'ch');
      expect(typing('sa').draft.initial!.label, 's');
    });

    test('takes a rime as soon as one is spelt, and lengthens it after', () {
      expect(typing('ba').draft.rime, 'a');
      expect(typing('ba').stage, ComposeStage.tone);
      expect(typing('ban').draft.rime, 'an');
      expect(typing('bang').draft.rime, 'ang');
    });

    test('holds letters that are on the way to a rime but not one yet', () {
      final io = typing('xio');
      expect(io.draft.rime, isNull);
      expect(io.draft.typed, 'io');
      expect(io.stage, ComposeStage.rime);
      expect(io.draftSuffix, 'xio');
      expect(typing('xiong').draft.rime, 'iong');
    });

    test('refuses what no syllable is spelt with', () {
      expect(typing('q').withLetter('o'), isNull, reason: 'no qo, no qong');
      expect(const Composition().withLetter('i'), isNull);
      expect(const Composition().withLetter('v'), isNull);
      expect(typing('ba').withLetter('h'), isNull, reason: 'only after z c s');
    });

    test('spells the syllables without an initial as they are written', () {
      expect(typing('wo').commit(Tone.third).text, 'wǒ');
      expect(typing('yi').commit(Tone.first).text, 'yī');
      expect(typing('yu').commit(Tone.second).text, 'yú');
      expect(typing('ai').commit(Tone.fourth).text, 'ài');
      expect(typing('er').commit(Tone.fourth).text, 'èr');
    });

    test('takes v for ü, and u where ü is written u', () {
      expect(typing('lv').commit(Tone.fourth).text, 'lǜ');
      expect(typing('nve').commit(Tone.fourth).text, 'nüè');
      expect(typing('ju').commit(Tone.second).text, 'jú');
    });

    test('ignores case', () {
      expect(typing('NI').commit(Tone.third).text, 'nǐ');
    });

    test('a tone straight after a syllable changes its tone', () {
      final ni = typing('ni').withTone(Tone.third);
      expect(ni.text, 'nǐ');
      expect(ni.withTone(Tone.fourth).text, 'nì');
      expect(
        ni.withTone(Tone.fourth).withTone(Tone.second).text,
        'ní',
        reason: 'as many times as it takes',
      );
    });

    test('a tone is for the new syllable once one is started', () {
      final line = typing('h', typing('ni').withTone(Tone.third));
      expect(line.withTone(Tone.fourth).text, 'nǐ', reason: 'h takes no tone');
      final hao = typing('hao', typing('ni').withTone(Tone.third));
      expect(hao.withTone(Tone.fourth).text, 'nǐhào');
    });

    test('a tone after a space changes nothing', () {
      final spaced = typing('ni').withTone(Tone.third).space();
      expect(spaced.withTone(Tone.fourth).text, 'nǐ');
    });

    test('a tone retones whatever is before the caret, after moving it', () {
      final line = typing(
        'hao',
        typing('ni').withTone(Tone.third),
      ).withTone(Tone.third);
      expect(line.movedBy(-1).withTone(Tone.second).text, 'níhǎo');
    });

    test('a tone has nothing to change at the very start', () {
      expect(const Composition().withTone(Tone.first).isEmpty, isTrue);
    });

    test('takes back one letter at a time, by the rules that built it', () {
      expect(typing('bang').withoutLetter().draft.rime, 'an');
      expect(typing('sh').withoutLetter().draft.initial!.label, 's');
      expect(typing('xio').withoutLetter().draft.rime, 'i');
      expect(typing('s').withoutLetter().draft.isEmpty, isTrue);
      expect(typing('a').withoutLetter().draft.isEmpty, isTrue);
    });

    test('with nothing being built, takes back a whole syllable', () {
      final composition = typing('ni').commit(Tone.third);
      expect(composition.withoutLetter().text, '');
    });

    test('types where the caret is', () {
      final line = type(
        type(const Composition(), 'n', 'i', Tone.third).space(),
        'h',
        'ao',
        Tone.third,
      ).movedTo(const Caret(word: 0, syllable: 1));
      expect(typing('men', line).commit(Tone.neutral).text, 'nǐmen hǎo');
    });

    test('moves the caret a place at a time, across word breaks', () {
      final line = type(
        type(const Composition(), 'n', 'i', Tone.third),
        'h',
        'ao',
        Tone.third,
      ).space();
      // nǐ hǎo |  — the caret starts after the break.
      final atEnd = line.caret;
      expect(line.movedBy(1).caret, atEnd, reason: 'nothing to the right');
      expect(line.movedBy(-1).caret, const Caret(word: 0, syllable: 2));
      expect(
        line.movedBy(-1).movedBy(-1).caret,
        const Caret(word: 0, syllable: 1),
      );
    });

    test('keeps the caret still while a syllable is being built', () {
      final line = typing(
        'n',
        type(const Composition(), 'h', 'ao', Tone.third),
      );
      expect(line.movedBy(-1).caret, line.caret);
    });
  });
}
