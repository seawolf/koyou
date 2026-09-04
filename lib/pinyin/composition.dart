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

/// A line of pinyin being composed: the words entered so far, plus the syllable
/// in progress.
///
/// Immutable, and holds every editing rule. The keyboard and screen are views
/// over this, so the rules can be tested without pumping a widget.
class Composition {
  const Composition({
    this.words = const <List<Syllable>>[<Syllable>[]],
    this.draft = const Draft(),
  });

  /// Words, each a list of syllables. Always at least one, possibly empty.
  ///
  /// Nested because pinyin runs syllables together inside a word and separates
  /// words with spaces: `shìjiè` is one word of two syllables, `nǐ hǎo` is two
  /// words of one.
  final List<List<Syllable>> words;

  final Draft draft;

  ComposeStage get stage => draft.stage;

  bool get isEmpty => draft.isEmpty && words.every((word) => word.isEmpty);

  /// The committed text: syllables joined within a word, words space-separated.
  String get text => words
      .where((word) => word.isNotEmpty)
      .map((word) => word.map((syllable) => syllable.written).join())
      .join(' ');

  /// The draft as it should be appended to [text], including the space that
  /// separates it when it starts a new word.
  String get draftSuffix {
    final written = draft.written;
    if (written.isEmpty) return '';
    if (text.isEmpty) return written;
    return words.last.isEmpty ? ' $written' : written;
  }

  /// [text] with the draft appended, for display while typing.
  String get preview => '$text$draftSuffix';

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
    next.last.add(
      Syllable(initial: draft.initial!.initial, rime: draft.rime!, tone: tone),
    );
    return Composition(words: next);
  }

  /// Starts a new word.
  ///
  /// Refused while a draft is open — the half-typed syllable would either be
  /// silently dropped or silently committed without a tone, and both are worse
  /// than doing nothing.
  Composition space() {
    if (!draft.isEmpty || words.last.isEmpty) return this;
    return Composition(words: [..._mutableWords(), <Syllable>[]]);
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
    if (next.last.isNotEmpty) {
      next.last.removeLast();
      return Composition(words: next);
    }
    if (next.length > 1) {
      next.removeLast();
      return Composition(words: next);
    }
    return this;
  }

  Composition cleared() => const Composition();

  List<List<Syllable>> _mutableWords() =>
      words.map((word) => [...word]).toList();

  Composition _copy({List<List<Syllable>>? words, Draft? draft}) =>
      Composition(words: words ?? this.words, draft: draft ?? this.draft);
}
