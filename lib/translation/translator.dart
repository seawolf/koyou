import '../pinyin/syllable.dart';

/// What a [Translator] is asked about.
///
/// Structured rather than a string of pinyin. Every dictionary and translation
/// service keys on something derived from the syllables — tone numbers, or the
/// characters themselves — and the app already knows the syllables it built, so
/// handing over the parts saves every translator from picking written pinyin
/// back apart. Splitting `wanan` into syllables is genuinely ambiguous; knowing
/// it was typed as `wǎn` + `ān` is not.
class TranslationRequest {
  const TranslationRequest(this.words);

  /// The words as typed, each a list of syllables. Word breaks are the ones the
  /// learner entered, which is more than a page of Chinese text ever gives you.
  final List<List<Syllable>> words;

  bool get isEmpty => words.every((word) => word.isEmpty);

  /// Everything typed, as written, tone marks included.
  String get written => words
      .where((word) => word.isNotEmpty)
      .map((word) => word.map((syllable) => syllable.written).join())
      .join(' ');

  /// Every syllable as a dictionary key: `ni3 hao3 shi4 jie4`.
  ///
  /// Word breaks are dropped, because a set phrase is one dictionary entry
  /// whether or not the learner spaced it.
  String get key => words
      .expand((word) => word)
      .map((syllable) => syllable.numbered)
      .join(' ');

  /// One dictionary key per word: `[ni3 hao3, shi4 jie4]`.
  List<String> get wordKeys => [
    for (final word in words)
      if (word.isNotEmpty) word.map((syllable) => syllable.numbered).join(' '),
  ];
}

/// What a [Translator] came back with.
class Translation {
  const Translation(
    this.text, {
    this.wordByWord = false,
    this.uncertain = false,
    this.hskLevel,
  });

  final String text;

  /// Whether this glosses each word separately rather than translating the
  /// phrase as a whole. Worth surfacing: word-by-word Mandarin is often
  /// misleading, and the learner should know which one they are reading.
  final bool wordByWord;

  /// Whether the pinyin matched several different words and this is a list of
  /// candidates rather than an answer.
  ///
  /// Unavoidable for a single syllable: only 17% of one-syllable pinyin keys
  /// map to a single word, against 91% for two and 99% for three or more.
  /// Pretending to have picked the right one would be worse than saying so.
  final bool uncertain;

  /// The HSK band of the word being offered, 1 being the most elementary, or
  /// null when the word is outside the syllabus or the answer spans several.
  ///
  /// Worth showing: it tells a learner whether what they typed is core
  /// vocabulary or something they have wandered into.
  final int? hskLevel;

  @override
  String toString() => text;

  @override
  bool operator ==(Object other) =>
      other is Translation &&
      other.text == text &&
      other.wordByWord == wordByWord &&
      other.uncertain == uncertain &&
      other.hskLevel == hskLevel;

  @override
  int get hashCode => Object.hash(text, wordByWord, uncertain, hskLevel);
}

/// Turns composed pinyin into English.
///
/// The seam a dictionary, a translation service, or a model plugs into.
abstract interface class Translator {
  /// A translation of [request], or null if this translator has none to offer.
  Future<Translation?> translate(TranslationRequest request);
}

/// Asks each translator in turn and takes the first answer.
///
/// Lets a small curated list sit in front of a large dictionary, and a network
/// service behind both, without any of them knowing about the others.
class CompositeTranslator implements Translator {
  const CompositeTranslator(this.translators);

  final List<Translator> translators;

  @override
  Future<Translation?> translate(TranslationRequest request) async {
    for (final translator in translators) {
      final result = await translator.translate(request);
      if (result != null) return result;
    }
    return null;
  }
}
