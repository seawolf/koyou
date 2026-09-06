import '../translation/translator.dart';

/// Says aloud what has been typed.
///
/// A seam for the same reason [Translator] is one, and kept apart from
/// translation because it answers a different question. Translation asks what
/// the pinyin *means*; speech asks how it *sounds*, which is the thing this app
/// is actually about — and the two fail independently. A phrase with no
/// translation is still worth hearing.
///
/// Takes what was typed rather than a string, because a speech engine needs
/// characters and only the dictionary can turn tone-marked pinyin into them.
/// That resolution belongs behind this interface, not in a screen.
abstract interface class Speech {
  /// Whether this device can speak Mandarin at all.
  ///
  /// Asked once, and the control is hidden entirely when it is false: a button
  /// that silently does nothing is worse than no button. False on a device
  /// with no Chinese voice installed, and in a browser without one.
  Future<bool> available();

  /// Speaks [request], and returns whether there was anything to say.
  ///
  /// False when the pinyin cannot be resolved to characters — the caller can
  /// then say so, rather than leaving a button that appears broken.
  Future<bool> speak(TranslationRequest request);

  /// Stops anything in progress. Called when the text changes underneath it.
  Future<void> stop();
}
