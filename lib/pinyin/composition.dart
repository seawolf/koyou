import 'syllable.dart';
import 'tone.dart';

/// The syllable being assembled, before a tone commits it.
class Draft {
  const Draft({this.initial = '', this.rime = ''});

  final String initial;
  final String rime;

  bool get isEmpty => initial.isEmpty && rime.isEmpty;

  /// Whether this is enough to commit. A rime is the minimum: an initial on
  /// its own cannot be pronounced, and every syllable needs a tone.
  bool get isCommittable => rime.isNotEmpty;

  /// How far the draft has got, for display. Shown untoned, because choosing
  /// the tone is what completes it.
  String get written => isCommittable
      ? Syllable(initial: initial, rime: rime, tone: Tone.neutral).written
      : initial;

  Draft copyWith({String? initial, String? rime}) =>
      Draft(initial: initial ?? this.initial, rime: rime ?? this.rime);
}

/// A line of pinyin being composed: the words entered so far, plus the
/// syllable in progress.
///
/// Immutable, and holds every editing rule. The keyboard and screen stay views
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

  Composition withInitial(String initial) =>
      _copy(draft: draft.copyWith(initial: initial));

  Composition withRime(String rime) => _copy(draft: draft.copyWith(rime: rime));

  /// Commits the draft as a syllable in [tone]. A no-op when there is nothing
  /// committable, so the tone keys are safe to press at any time.
  Composition commit(Tone tone) {
    if (!draft.isCommittable) return this;
    final next = _mutableWords();
    next.last.add(
      Syllable(initial: draft.initial, rime: draft.rime, tone: tone),
    );
    return Composition(words: next, draft: const Draft());
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

  /// Removes the most recent thing entered: the draft's rime, then its
  /// initial, then the last committed syllable, then the last word break.
  Composition backspace() {
    if (draft.rime.isNotEmpty) {
      return _copy(draft: Draft(initial: draft.initial));
    }
    if (draft.initial.isNotEmpty) return _copy(draft: const Draft());

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
