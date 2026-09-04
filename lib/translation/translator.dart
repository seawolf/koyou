/// What a [Translator] came back with.
class Translation {
  const Translation(this.text, {this.wordByWord = false});

  final String text;

  /// Whether this glosses each word separately rather than translating the
  /// phrase as a whole. Worth surfacing: word-by-word Mandarin is often
  /// misleading, and the learner should know which one they are reading.
  final bool wordByWord;

  @override
  String toString() => text;

  @override
  bool operator ==(Object other) =>
      other is Translation &&
      other.text == text &&
      other.wordByWord == wordByWord;

  @override
  int get hashCode => Object.hash(text, wordByWord);
}

/// Turns composed pinyin into English.
///
/// The seam a real model plugs into. Implementations take pinyin *with tone
/// marks* — tones disambiguate, so dropping them would throw away the
/// information that makes the input worth typing.
abstract interface class Translator {
  /// A translation of [pinyin], or null if this translator has none to offer.
  Future<Translation?> translate(String pinyin);
}
