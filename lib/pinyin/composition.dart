import 'package:flutter/foundation.dart';

import 'keyboard_layout.dart';
import 'syllable.dart';
import 'tone.dart';

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

  /// How many syllables of that word are before the caret, so 0 is the start
  /// of the word and the word's length is its end.
  final int syllable;

  @override
  bool operator ==(Object other) =>
      other is Caret && other.word == word && other.syllable == syllable;

  @override
  int get hashCode => Object.hash(word, syllable);

  @override
  String toString() => 'Caret($word:$syllable)';
}

/// A line of pinyin being composed: the words entered so far, plus the syllable
/// in progress.
///
/// Immutable, and holds every editing rule. The keyboard and screen are views
/// over this, so the rules can be tested without pumping a widget.
class Composition {
  const Composition({
    this.words = const <List<Syllable>>[<Syllable>[]],
    this.draft = const Draft(),
    this.caret = const Caret(word: 0, syllable: 0),
  });

  /// Words, each a list of syllables. Always at least one, possibly empty.
  ///
  /// Nested because pinyin runs syllables together inside a word and separates
  /// words with spaces: `shìjiè` is one word of two syllables, `nǐ hǎo` is two
  /// words of one.
  final List<List<Syllable>> words;

  final Draft draft;

  /// Where editing happens. Defaults to the start, which for an empty line is
  /// also the end — so a composition built by typing keeps the caret at the
  /// end without anything having to track it.
  final Caret caret;

  ComposeStage get stage => draft.stage;

  bool get isEmpty => draft.isEmpty && words.every((word) => word.isEmpty);

  /// The committed text: syllables joined within a word, words space-separated.
  String get text => words
      .where((word) => word.isNotEmpty)
      .map((word) => word.map((syllable) => syllable.written).join())
      .join(' ');

  /// Everything before the caret, as written.
  ///
  /// Includes the space that separates the caret's word from the one before
  /// it, so the two halves plus the draft reassemble the line exactly.
  String get textBefore {
    final earlier = [
      for (var index = 0; index < caret.word; index++)
        if (words[index].isNotEmpty) _write(words[index]),
    ].join(' ');
    final head = _write(words[caret.word].take(caret.syllable));
    return earlier.isEmpty ? head : '$earlier $head';
  }

  /// Everything from the caret onwards, as written.
  String get textAfter {
    final rest = StringBuffer(_write(words[caret.word].skip(caret.syllable)));
    for (var index = caret.word + 1; index < words.length; index++) {
      if (words[index].isEmpty) continue;
      // The space goes here rather than at the end of [textBefore], so a caret
      // sitting at the end of a word does not push the gap behind it.
      rest.write(' ');
      rest.write(_write(words[index]));
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
    final next = _mutableWords();
    next[caret.word].insert(
      caret.syllable,
      Syllable(initial: draft.initial!.initial, rime: draft.rime!, tone: tone),
    );
    return Composition(
      words: next,
      caret: Caret(word: caret.word, syllable: caret.syllable + 1),
    );
  }

  /// Starts a new word.
  ///
  /// Refused while a draft is open — the half-typed syllable would either be
  /// silently dropped or silently committed without a tone, and both are worse
  /// than doing nothing.
  Composition space() {
    if (!draft.isEmpty) return this;
    final word = words[caret.word];
    // Nothing to break off: either the word is empty, or the caret is already
    // at its start. Both would leave an empty word, which renders as nothing
    // and lets space be pressed forever.
    if (word.isEmpty || caret.syllable == 0) return this;

    final next = _mutableWords();
    final after = word.sublist(caret.syllable);
    next[caret.word] = word.sublist(0, caret.syllable);
    next.insert(caret.word + 1, after);
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

    final next = _mutableWords();
    if (caret.syllable > 0) {
      next[caret.word].removeAt(caret.syllable - 1);
      return Composition(
        words: next,
        caret: Caret(word: caret.word, syllable: caret.syllable - 1),
      );
    }
    if (caret.word > 0) {
      // At the start of a word, what is behind the caret is the word break, so
      // that is what goes: the two words become one and the caret sits at the
      // join.
      final previous = next.removeAt(caret.word - 1);
      next[caret.word - 1] = [...previous, ...next[caret.word - 1]];
      return Composition(
        words: next,
        caret: Caret(word: caret.word - 1, syllable: previous.length),
      );
    }
    return this;
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
    if (syllable < 0 || syllable >= words[word].length) return this;
    final next = _mutableWords();
    final old = next[word][syllable];
    next[word][syllable] = Syllable(
      initial: old.initial,
      rime: old.rime,
      tone: tone,
    );
    return Composition(words: next, caret: caret);
  }

  /// The caret at the very end, which is where typing leaves it.
  Caret get end => Caret(word: words.length - 1, syllable: words.last.length);

  Composition cleared() => const Composition();

  static String _write(Iterable<Syllable> syllables) =>
      syllables.map((syllable) => syllable.written).join();

  List<List<Syllable>> _mutableWords() =>
      words.map((word) => [...word]).toList();

  Composition _copy({List<List<Syllable>>? words, Draft? draft}) => Composition(
    words: words ?? this.words,
    draft: draft ?? this.draft,
    caret: caret,
  );
}
