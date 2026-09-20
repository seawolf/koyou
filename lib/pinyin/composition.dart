import 'package:flutter/foundation.dart';

import 'keyboard_layout.dart';
import 'syllable.dart';
import 'tone.dart';
import 'word.dart';

/// Which piece of a syllable the learner is choosing.
///
/// The keyboard shows one bank at a time and steps through these in order, so
/// the choice on offer is always small and always the next thing needed.
enum ComposeStage { initial, rime, tone }

/// The syllable being assembled, one stage at a time.
///
/// [initial] and [rime] are null until chosen, which is not the same as being
/// empty: the bare-vowel key is a real choice that contributes no letters, and
/// `ān` has to be typeable.
class Draft {
  const Draft({this.initial, this.rime});

  final InitialKey? initial;
  final String? rime;

  bool get isEmpty => initial == null;

  ComposeStage get stage {
    if (initial == null) return ComposeStage.initial;
    if (rime == null) return ComposeStage.rime;
    return ComposeStage.tone;
  }

  /// Whether this is enough to commit, needing only a tone.
  bool get isCommittable => initial != null && rime != null;

  /// How far the draft has got, for display. Untoned, because choosing the tone
  /// is what completes it.
  String get written {
    final initial = this.initial;
    if (initial == null) return '';
    final rime = this.rime;
    if (rime == null) return initial.spelling;
    return Syllable(
      initial: initial.initial,
      rime: rime,
      tone: Tone.neutral,
    ).written;
  }

  /// The chosen rime as it appeared on the key, or null if none is chosen yet.
  ///
  /// The label, not the phonological rime: under `w` the learner pressed `o`,
  /// not `uo`, and the trail has to show them what they pressed.
  String? get rimeLabel {
    final initial = this.initial;
    if (initial == null || rime == null) return null;
    return written.substring(initial.spelling.length);
  }

  /// The five syllables this draft could become, in tone order.
  List<Syllable> get candidates {
    final initial = this.initial;
    final rime = this.rime;
    if (initial == null || rime == null) return const [];
    return tonedCandidates(initial, rime);
  }
}

/// Where the next syllable goes: an insertion point between two syllables.
///
/// Syllable-granular rather than character-granular, because a syllable is
/// both what the keyboard produces and what a learner says. There is no useful
/// position inside `shì`, and offering one would let a caret sit between a
/// vowel and its own tone mark.
@immutable
class Caret {
  const Caret({required this.word, required this.syllable});

  /// Index into [Composition.words].
  final int word;

  /// How many of that word's units are before the caret, so 0 is the start of
  /// the word and the word's length is its end. A [Literal] has one unit, so
  /// the caret goes either side of `Steve` and never into it.
  final int syllable;

  @override
  bool operator ==(Object other) =>
      other is Caret && other.word == word && other.syllable == syllable;

  @override
  int get hashCode => Object.hash(word, syllable);

  @override
  String toString() => 'Caret($word:$syllable)';
}

/// A line being composed: the words entered so far, plus the syllable in
/// progress.
///
/// Immutable, and holds every editing rule. The keyboard and screen are views
/// over this, so the rules can be tested without pumping a widget.
class Composition {
  const Composition({
    this.words = const <Word>[Spoken()],
    this.draft = const Draft(),
    this.caret = const Caret(word: 0, syllable: 0),
  });

  /// The words. Always at least one, possibly empty.
  ///
  /// A [Spoken] word runs its syllables together — `shìjiè` is one word of two
  /// — and words are separated by spaces. A [Literal] is a word too, so
  /// `wǒ jiào Steve` is three of them, and the one that is not Mandarin is
  /// carried rather than looked up.
  final List<Word> words;

  final Draft draft;

  /// Where editing happens. Defaults to the start, which for an empty line is
  /// also the end — so a composition built by typing keeps the caret at the
  /// end without anything having to track it.
  final Caret caret;

  ComposeStage get stage => draft.stage;

  bool get isEmpty => draft.isEmpty && words.every((word) => word.isEmpty);

  /// The committed text, words space-separated.
  String get text => words
      .where((word) => !word.isEmpty)
      .map((word) => word.written)
      .join(' ');

  /// Everything before the caret, as written.
  ///
  /// Includes the space that separates the caret's word from the one before
  /// it, so the two halves plus the draft reassemble the line exactly.
  String get textBefore {
    final earlier = [
      for (var index = 0; index < caret.word; index++)
        if (!words[index].isEmpty) words[index].written,
    ].join(' ');
    final head = words[caret.word].writtenTake(caret.syllable);
    return earlier.isEmpty ? head : '$earlier $head';
  }

  /// Everything from the caret onwards, as written.
  String get textAfter {
    final rest = StringBuffer(words[caret.word].writtenSkip(caret.syllable));
    for (var index = caret.word + 1; index < words.length; index++) {
      if (words[index].isEmpty) continue;
      // The space goes here rather than at the end of [textBefore], so a caret
      // sitting at the end of a word does not push the gap behind it.
      rest.write(' ');
      rest.write(words[index].written);
    }
    return rest.toString();
  }

  /// The draft, which sits at the caret.
  String get draftSuffix => draft.written;

  /// [textBefore], the draft, and [textAfter], for display while typing.
  String get preview => '$textBefore$draftSuffix$textAfter';

  /// Chooses the starting point, and drops any rime already picked — the rimes
  /// on offer depend on the initial, so keeping one could leave a syllable that
  /// does not exist.
  Composition withInitial(InitialKey initial) =>
      _copy(draft: Draft(initial: initial));

  Composition withRime(String rime) => _copy(
    draft: Draft(initial: draft.initial, rime: rime),
  );

  /// Commits the draft as a syllable in [tone]. A no-op when there is nothing
  /// committable, so a tone key is safe to press at any time.
  Composition commit(Tone tone) {
    if (!draft.isCommittable) return this;
    final syllable = Syllable(
      initial: draft.initial!.initial,
      rime: draft.rime!,
      tone: tone,
    );
    final next = [...words];
    final here = next[caret.word];

    if (here is Spoken) {
      next[caret.word] = Spoken(
        [...here.syllables]..insert(caret.syllable, syllable),
      );
      return Composition(
        words: next,
        caret: Caret(word: caret.word, syllable: caret.syllable + 1),
      );
    }
    // Nothing goes inside a name. A syllable typed against one starts its own
    // word on whichever side of it the caret was.
    final at = caret.syllable == 0 ? caret.word : caret.word + 1;
    next.insert(at, Spoken([syllable]));
    return Composition(
      words: next,
      caret: Caret(word: at, syllable: 1),
    );
  }

  /// Puts a word that is not Mandarin at the caret — a name, a brand.
  ///
  /// Replaces the word the caret is in if that is already a literal, which is
  /// what tapping `Steve` in the line and correcting it does. Otherwise it is
  /// inserted as a word of its own, because a name does not run together with
  /// the syllables around it.
  Composition withLiteral(String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return this;

    final next = [...words];
    if (next[caret.word] is Literal) {
      next[caret.word] = Literal(trimmed);
      return Composition(
        words: next,
        caret: Caret(word: caret.word, syllable: 1),
        draft: draft,
      );
    }
    // A half-typed syllable has no tone and so is not a syllable; it would be
    // silently committed or silently dropped, and neither is honest.
    final at = caret.syllable == 0 ? caret.word : caret.word + 1;
    next.insert(at, Literal(trimmed));
    return Composition(
      words: next,
      caret: Caret(word: at, syllable: 1),
    );
  }

  /// The literal at [word], or null if that word is not one.
  ///
  /// What the screen asks before opening the editor on a tapped word.
  Literal? literalAt(int word) {
    if (word < 0 || word >= words.length) return null;
    final found = words[word];
    return found is Literal ? found : null;
  }

  /// Starts a new word.
  ///
  /// Refused while a draft is open — the half-typed syllable would either be
  /// silently dropped or silently committed without a tone, and both are worse
  /// than doing nothing.
  Composition space() {
    if (!draft.isEmpty) return this;
    final word = words[caret.word];
    // Nothing to break off: the word is empty, the caret is at its start, or
    // it is a name, which is already a word of its own.
    if (word.isEmpty || caret.syllable == 0 || word is! Spoken) return this;

    final next = [...words];
    final after = word.syllables.sublist(caret.syllable);
    next[caret.word] = Spoken(word.syllables.sublist(0, caret.syllable));
    next.insert(caret.word + 1, Spoken(after));
    return Composition(
      words: next,
      caret: Caret(word: caret.word + 1, syllable: 0),
    );
  }

  /// Returns to [stage], keeping the choices made before it.
  ///
  /// What the trail of already-chosen pieces does when tapped: it is a way back
  /// to a decision, not an undo.
  Composition backTo(ComposeStage stage) => switch (stage) {
    ComposeStage.initial => _copy(draft: const Draft()),
    ComposeStage.rime => _copy(draft: Draft(initial: draft.initial)),
    ComposeStage.tone => this,
  };

  /// Steps back one stage, then one syllable, then one word break — the exact
  /// reverse of how things were entered.
  Composition backspace() {
    if (draft.rime != null) {
      return _copy(draft: Draft(initial: draft.initial));
    }
    if (draft.initial != null) return _copy(draft: const Draft());

    final next = [...words];
    if (caret.syllable > 0) {
      final here = next[caret.word];
      if (here is Spoken) {
        next[caret.word] = Spoken(
          [...here.syllables]..removeAt(caret.syllable - 1),
        );
        return Composition(
          words: next,
          caret: Caret(word: caret.word, syllable: caret.syllable - 1),
        );
      }
      // A name goes whole: there is nothing inside it to take one piece off.
      next.removeAt(caret.word);
      if (next.isEmpty) return const Composition();
      final landing = caret.word == 0 ? 0 : caret.word - 1;
      return Composition(
        words: next,
        caret: Caret(
          word: landing,
          syllable: caret.word == 0 ? 0 : next[landing].length,
        ),
      );
    }
    if (caret.word > 0) {
      // At the start of a word, what is behind the caret is the word break, so
      // that is what goes — unless one of the two is a name, which cannot be
      // run together with syllables. Then the break is all there is to remove.
      final previous = next[caret.word - 1];
      final here = next[caret.word];
      if (previous is Spoken && here is Spoken) {
        next.removeAt(caret.word - 1);
        next[caret.word - 1] = Spoken([
          ...previous.syllables,
          ...here.syllables,
        ]);
        return Composition(
          words: next,
          caret: Caret(word: caret.word - 1, syllable: previous.length),
        );
      }
      return Composition(
        words: next,
        caret: Caret(word: caret.word - 1, syllable: previous.length),
      );
    }
    return this;
  }

  /// Lifts a committed syllable back into the draft, to be finished again.
  ///
  /// What double-tapping or long-pressing a syllable does. The syllable comes
  /// out of the line and the caret takes its place, so choosing again puts the
  /// new one exactly where the old one was.
  ///
  /// [stage] says how far back to go: [ComposeStage.tone] keeps the initial
  /// and the rime and asks only for the tone, which is the common fix;
  /// [ComposeStage.rime] keeps the initial and asks again for what follows it.
  /// Going back to [ComposeStage.initial] would leave nothing of the syllable,
  /// which is what backspace is for.
  Composition redraft(int word, int syllable, ComposeStage stage) {
    if (stage == ComposeStage.initial) return this;
    if (word < 0 || word >= words.length) return this;
    final here = words[word];
    if (here is! Spoken) return this;
    if (syllable < 0 || syllable >= here.syllables.length) return this;

    final chosen = here.syllables[syllable];
    final key = keyFor(chosen);
    // A syllable the keyboard could not have produced cannot be put back into
    // its banks either. Nothing in the inventory is like this, but a stand-in
    // in a test can be.
    if (key == null) return this;

    final next = [...words];
    next[word] = Spoken([...here.syllables]..removeAt(syllable));
    return Composition(
      words: next,
      caret: Caret(word: word, syllable: syllable),
      draft: stage == ComposeStage.tone
          ? Draft(initial: key, rime: chosen.rime)
          : Draft(initial: key),
    );
  }

  /// Moves the caret, clamped to somewhere it can actually be.
  ///
  /// Drops any draft. A draft has no tone, so it is not yet a syllable, and
  /// carrying half a syllable to a new place in the line is stranger than
  /// losing it — the learner has moved on from it by definition.
  Composition movedTo(Caret target) {
    final word = target.word.clamp(0, words.length - 1);
    final syllable = target.syllable.clamp(0, words[word].length);
    return Composition(
      words: words,
      caret: Caret(word: word, syllable: syllable),
    );
  }

  /// One syllable's tone changed, leaving everything else — including the
  /// caret — where it is.
  ///
  /// What accepting a suggested correction does. Only the tone moves, so there
  /// is nothing to re-parse: the letters the learner chose are still theirs.
  Composition retoned(int word, int syllable, Tone tone) {
    if (word < 0 || word >= words.length) return this;
    final here = words[word];
    if (here is! Spoken) return this;
    if (syllable < 0 || syllable >= here.syllables.length) return this;

    final syllables = [...here.syllables];
    final old = syllables[syllable];
    syllables[syllable] = Syllable(
      initial: old.initial,
      rime: old.rime,
      tone: tone,
    );
    final next = [...words];
    next[word] = Spoken(syllables);
    return Composition(words: next, caret: caret);
  }

  /// A line already worked out elsewhere, ready to be edited.
  ///
  /// How an answer from the translate screen arrives: the words are already
  /// syllables, so every gesture the keyboard offers works on them at once —
  /// retone one, correct a rime, backspace off the end. The caret goes to the
  /// end, where typing would have left it.
  ///
  /// Empty words are dropped. A caller assembling a line from a dictionary
  /// answer has no reason to think about them, and a line with a gap in it
  /// would put a stray space on the screen.
  factory Composition.of(List<Word> words) {
    final kept = words.where((word) => !word.isEmpty).toList();
    if (kept.isEmpty) return const Composition();
    return Composition(
      words: kept,
      caret: Caret(word: kept.length - 1, syllable: kept.last.length),
    );
  }

  /// The caret at the very end, which is where typing leaves it.
  Caret get end => Caret(word: words.length - 1, syllable: words.last.length);

  Composition cleared() => const Composition();

  Composition _copy({List<Word>? words, Draft? draft}) => Composition(
    words: words ?? this.words,
    draft: draft ?? this.draft,
    caret: caret,
  );
}
