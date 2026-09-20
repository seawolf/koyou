/// Translates between Chinese and English, in whichever direction is asked
/// for.
///
/// The one job an on-device model, a platform translation API and a network
/// service all do identically, and the seam they swap at. It deliberately
/// knows nothing about pinyin: resolving what was typed into characters is
/// [ModelTranslator]'s work, and turning characters back into pinyin is
/// [CharacterIndex]'s, so by the time a backend is called the tone-sensitive
/// half is either already done or not yet begun. A model is never asked to
/// read a tone mark or to write one.
///
/// Two methods rather than one with a flag, because the direction is the
/// single most important thing about a call here and a flag can be passed
/// wrongly in silence. Getting it backwards would hand a learner fluent pinyin
/// for the wrong sentence, which is the one mistake nothing on screen would
/// reveal.
abstract interface class TranslationBackend {
  /// English for [chinese], or null if this backend has nothing to offer.
  ///
  /// Returning null rather than throwing is what lets a backend be absent —
  /// weights not downloaded yet, a platform model unavailable on this device,
  /// no network — without the app losing the dictionary behind it.
  Future<String?> intoEnglish(String chinese);

  /// Chinese, in simplified characters, for [english]. Null as above.
  ///
  /// The harder direction, measurably: generating Chinese pulls a small model
  /// towards answering rather than translating. See `english_prompt.dart` for
  /// what that looks like and what stops it.
  Future<String?> intoChinese(String english);
}
