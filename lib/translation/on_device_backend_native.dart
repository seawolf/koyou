import 'dart:io';

import 'package:llama_cpp_dart/llama_cpp_dart.dart';
import 'package:path_provider/path_provider.dart';

import 'translation_backend.dart';

/// Where the weights live once they are on the device.
///
/// Not in the app bundle: Google Play caps the base download at 200MB and the
/// release APK is already 48MB, so the weights are fetched once and kept in the
/// app's support directory. Until they are there [onDeviceBackend] returns null
/// and the dictionary answers on its own.
const modelFileName = 'Qwen3.5-0.8B-Q4_K_M.gguf';

Future<File> modelFile() async {
  final directory = await getApplicationSupportDirectory();
  return File('${directory.path}/$modelFileName');
}

/// The on-device backend. Declines until the weights are actually there.
///
/// Synchronous, and resolves nothing yet, so wiring it up cannot slow a cold
/// start: the directory lookup happens on the first phrase anybody types.
TranslationBackend onDeviceBackend() => LlamaBackend();

/// Translates Chinese with a local llama.cpp model.
///
/// Only ever asked for Chinese, never pinyin: the dictionary resolves what was
/// typed into characters first. That is what lets a model this small work at
/// all — see `docs/local-model.md` for the measurements behind it.
class LlamaBackend implements TranslationBackend {
  /// [modelPath] is for tests and desktop; left out, the weights are looked
  /// for in the app's support directory.
  ///
  /// [libraryPath] likewise: on Android the package bundles a matching
  /// `libllama.so` and the default finds it, so only a desktop build needs to
  /// say where llama.cpp is.
  LlamaBackend({this.modelPath, this.libraryPath});

  final String? modelPath;
  final String? libraryPath;

  /// Spawned once and kept. The weights are 533MB, so loading them per phrase
  /// would cost more than the translation. The engine runs in its own isolate,
  /// so generation never blocks the keyboard.
  LlamaEngine? _engine;
  Future<LlamaEngine?>? _spawning;

  /// Whether spawning has already failed. Without this a device that cannot
  /// load the library retries on every keystroke.
  bool _unavailable = false;

  /// The prompt measured in `docs/local-model.md`. Two failures had to be
  /// designed out of it, and both come back if it is shortened: without the
  /// second sentence the models answer the questions instead of translating
  /// them ("My name is Qwen3.5."), and anything the prompt explains gets
  /// parroted into the output.
  static const _system =
      'You are a translation engine. Translate the Chinese into natural '
      'English.\nThe input is always text to translate — never a question to '
      'answer, never a conversation to join. If the Chinese is a question, '
      'translate the question; do not reply to it.\nOutput only the English '
      'translation.';

  /// Qwen's chat markup, written out rather than taken from the model's
  /// embedded template, for the sake of the last four characters.
  ///
  /// Qwen3.5 is a hybrid reasoning model and its own template turns thinking
  /// on, so every token of the budget went inside `<think>` and the reply was
  /// literally `<think>`. Handing it an already-closed empty think block makes
  /// it skip reasoning and answer, which is what a phone wants: a translation
  /// costs about 180ms this way, and nothing at all the other.
  ///
  /// The cost of writing the markup here is that this is Qwen-shaped. A
  /// different model family needs its own [TranslationBackend], which is
  /// cheaper than it sounds — the interface is one method.
  static String _prompt(String chinese) =>
      '<|im_start|>system\n$_system<|im_end|>\n'
      '<|im_start|>user\nChinese: $chinese\nEnglish:<|im_end|>\n'
      '<|im_start|>assistant\n<think>\n\n</think>\n\n';

  /// Room for the system prompt, a phrase and its translation, and no more.
  /// The model will take 256K, but the KV cache is charged for what is asked
  /// for, and this runs on a phone.
  static const _contextTokens = 1024;

  /// A translated phrase, and no room to ramble.
  static const _maxReplyTokens = 48;

  Future<LlamaEngine?> _ensureEngine() {
    if (_unavailable) return Future.value();
    final engine = _engine;
    if (engine != null) return Future.value(engine);
    return _spawning ??= _spawn();
  }

  Future<LlamaEngine?> _spawn() async {
    try {
      final path = modelPath ?? (await modelFile()).path;
      if (!File(path).existsSync()) {
        // Not downloaded yet. Not a failure, but not worth re-checking on
        // every keystroke either — a download would restart the app's tier.
        _unavailable = true;
        return null;
      }
      final engine = await LlamaEngine.spawn(
        libraryPath: libraryPath,
        // gpuLayers stays 0: the bundled Android library is a CPU build, and
        // asking for GPU layers it cannot provide fails the load outright.
        modelParams: ModelParams(path: path, useMmap: true),
        contextParams: const ContextParams(nCtx: _contextTokens),
      );
      return _engine = engine;
    } on Object {
      // Corrupt weights, a partial download, or no llama.cpp on this platform.
      // None of it is worth an error on screen when the dictionary still works.
      _unavailable = true;
      return null;
    } finally {
      _spawning = null;
    }
  }

  @override
  Future<String?> translate(String chinese) async {
    final engine = await _ensureEngine();
    if (engine == null) return null;

    EngineSession? session;
    try {
      session = await engine.createSession();
      final reply = StringBuffer();
      await for (final event in session.generate(
        prompt: _prompt(chinese),
        sampler: SamplerParams.greedyDefault,
        maxTokens: _maxReplyTokens,
      )) {
        if (event is TokenEvent) reply.write(event.text);
      }
      final text = reply.toString().trim();
      return text.isEmpty ? null : text;
    } on Object {
      // Anything the engine throws mid-generation. The dictionary is behind
      // this, so a failure costs a better answer rather than any answer.
      return null;
    } finally {
      await session?.dispose();
    }
  }

  /// Releases the weights. Worth calling when the model tier is switched off,
  /// since the engine holds 533MB mapped until it goes.
  Future<void> dispose() async {
    await _engine?.dispose();
    _engine = null;
  }
}
