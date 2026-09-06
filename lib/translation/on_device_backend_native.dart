import 'package:llama_cpp_dart/llama_cpp_dart.dart';

import 'model_asset.dart';
import 'model_store_native.dart';
import 'translation_backend.dart';

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

  /// Set only when loading genuinely failed — a corrupt file, or no llama.cpp
  /// on this platform — so a device that cannot run the model stops retrying
  /// on every phrase.
  ///
  /// Deliberately not set when the weights are merely absent or switched off.
  /// Those change while the app is running, and latching would mean the model
  /// stayed silent until a restart.
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

  Future<LlamaEngine?> _ensureEngine() async {
    if (_unavailable) return null;

    if (modelPath == null && !await weightsUsable(ModelAsset.qwen08b)) {
      // Not downloaded, removed, or switched off. Checked every time rather
      // than once, because all three change while the app is running — and if
      // an engine is already up, this is where switching the model off gives
      // back the 533MB it holds mapped.
      await dispose();
      return null;
    }

    final engine = _engine;
    if (engine != null) return engine;
    return _spawning ??= _spawn();
  }

  Future<LlamaEngine?> _spawn() async {
    try {
      final path = modelPath ?? (await weightsFile(ModelAsset.qwen08b)).path;
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
