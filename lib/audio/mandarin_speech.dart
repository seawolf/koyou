import 'package:flutter_tts/flutter_tts.dart';

import '../pinyin/word.dart';
import '../translation/dictionary.dart';
import '../translation/translator.dart';
import 'speech.dart';

/// Speaks Mandarin with whatever voice the device already has.
///
/// The platform's, rather than a model's: Qwen emits text only, and llama.cpp's
/// TTS path would mean another gigabyte of weights and a vocoder to get worse
/// Mandarin than a phone gives away. Android and iOS both ship a Chinese voice,
/// and browsers expose one through the same plugin, so this is the one tier
/// that works everywhere — including the web, where the model cannot.
class MandarinSpeech implements Speech {
  MandarinSpeech(this.dictionary, {VoiceEngine? engine})
    : _engine = engine ?? PlatformVoice();

  /// Resolves tone-marked pinyin to the characters a voice can read.
  ///
  /// The third use of the same bridge, after the dictionary's own lookups and
  /// the model's. Handed `wǒ mài shū` a Chinese voice says nothing useful; it
  /// needs 我卖书.
  final Dictionary dictionary;

  final VoiceEngine _engine;

  /// Simplified Mandarin. Not `zh` alone: on some devices that resolves to a
  /// Cantonese or Taiwanese voice, which is the wrong pronunciation to teach.
  static const _language = 'zh-CN';

  bool? _available;
  bool _configured = false;

  @override
  Future<bool> available() async {
    if (_available case final known?) return known;
    try {
      return _available = await _engine.hasLanguage(_language);
    } on Object {
      // No engine, or a platform that does not answer. Either way, no button.
      return _available = false;
    }
  }

  @override
  Future<bool> speak(TranslationRequest request) async {
    if (!await available()) return false;

    final chinese = await _resolve(request);
    if (chinese == null) return false;

    try {
      if (!_configured) {
        // Slower than conversational. The point is to hear the tones, and a
        // learner cannot follow a native rate on a phrase they just built.
        await _engine.configure(_language, _slowRate);
        _configured = true;
      }
      await _engine.hush();
      await _engine.say(chinese);
      return true;
    } on Object {
      return false;
    }
  }

  /// Android reads this as a fraction of normal; 0.5 is unnaturally slow on
  /// iOS, where the same scale runs 0 to 1 with 0.5 already normal. The plugin
  /// normalises neither, so this is the compromise: clearly deliberate on
  /// Android, only slightly slow on iOS.
  static const _slowRate = 0.45;

  /// The characters for everything typed, or null if any word is unknown.
  ///
  /// All or nothing, as with translation: dropping a word the dictionary
  /// cannot place would teach a sentence the learner did not write.
  Future<String?> _resolve(TranslationRequest request) async {
    final typed = request.words.where((word) => !word.isEmpty).toList();
    if (typed.isEmpty) return null;

    final characters = StringBuffer();
    for (final word in typed) {
      switch (word) {
        case Literal():
          // Handed to the voice as written. What a Mandarin voice makes of
          // `Steve` is the platform's business, and it is the same thing it
          // does with a name in any other Chinese sentence.
          characters.write(word.text);
        case Spoken():
          final entries = await dictionary.lookUp(word.key);
          if (entries.isEmpty) return null;
          // Any candidate would do for sound. The key carries the tone, so
          // every word matching it is pronounced identically — 前 and 钱 are
          // both qián. Audio is therefore immune to the ambiguity that spoils
          // a translation.
          characters.write(entries.first.simplified);
      }
    }
    return characters.toString();
  }

  @override
  Future<void> stop() async {
    try {
      await _engine.hush();
    } on Object {
      // Nothing was playing, or the engine has gone. Not worth reporting.
    }
  }
}

/// The four things this app asks of a platform voice.
///
/// A seam of its own inside [MandarinSpeech], so the part worth testing — that
/// the right characters, with the right tones, reach the voice at all — can be
/// tested without a plugin. `FlutterTts`'s constructor registers a platform
/// channel, so it cannot even be built in a plain test.
abstract interface class VoiceEngine {
  Future<bool> hasLanguage(String language);
  Future<void> configure(String language, double rate);
  Future<void> say(String text);
  Future<void> hush();
}

/// [VoiceEngine] over `flutter_tts`, which is the platform's own voice on
/// Android, iOS, macOS, Windows and the web.
class PlatformVoice implements VoiceEngine {
  PlatformVoice([FlutterTts? tts]) : _tts = tts ?? FlutterTts();

  final FlutterTts _tts;

  @override
  Future<bool> hasLanguage(String language) async =>
      await _tts.isLanguageAvailable(language) == true;

  @override
  Future<void> configure(String language, double rate) async {
    await _tts.setLanguage(language);
    await _tts.setSpeechRate(rate);
  }

  @override
  Future<void> say(String text) => _tts.speak(text);

  @override
  Future<void> hush() => _tts.stop();
}
