/// Turns Chinese into English.
///
/// The one job an on-device model, a platform translation API and a network
/// service all do identically, and the seam they swap at. It deliberately
/// knows nothing about pinyin: resolving what was typed into characters is
/// [ModelTranslator]'s work, and by the time a backend is called the hard,
/// tone-sensitive half is already done.
abstract interface class TranslationBackend {
  /// English for [chinese], or null if this backend has nothing to offer.
  ///
  /// Returning null rather than throwing is what lets a backend be absent —
  /// weights not downloaded yet, a platform model unavailable on this device,
  /// no network — without the app losing the dictionary behind it.
  Future<String?> translate(String chinese);
}
