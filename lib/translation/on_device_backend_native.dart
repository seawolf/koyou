import 'package:llama_cpp_dart/llama_cpp_dart.dart';

import 'model_asset.dart';
import 'model_prompt.dart';
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

  /// Generations run one at a time, in the order asked for.
  ///
  /// Not an optimisation — a correctness fix. Sessions created on one engine
  /// share KV sequence 0, so two generations at once corrupt each other's
  /// cache: on a laptop, five overlapping translations produced "I am. 10. 11.
  /// 12." from 我是 and threw on the other four. The app asks on every
  /// keystroke, which is exactly how they overlap.
  Future<void> _queue = Future<void>.value();

  /// Set only when loading genuinely failed — a corrupt file, or no llama.cpp
  /// on this platform — so a device that cannot run the model stops retrying
  /// on every phrase.
  ///
  /// Deliberately not set when the weights are merely absent or switched off.
  /// Those change while the app is running, and latching would mean the model
  /// stayed silent until a restart.
  bool _unavailable = false;

  /// Room for the system prompt, a phrase and its translation, and no more.
  /// The model will take 256K, but the KV cache is charged for what is asked
  /// for, and this runs on a phone.
  static const _contextTokens = 1024;

  /// A translated phrase, and no room to ramble.
  static const _maxReplyTokens = maxReplyTokens;

  /// Deterministic, but not `SamplerParams.greedyDefault`.
  ///
  /// `greedy: true` short-circuits to argmax and ignores the rest of the
  /// chain, penalties included, which is how a wobble turns into "10. 11. 12."
  /// and runs to the token limit. A temperature of zero collapses to the same
  /// argmax *after* the filters, so the repeat penalty still applies and the
  /// answer is still the same every time.
  static const _sampler = SamplerParams(
    temperature: 0,
    repeatPenalty: 1.1,
    penaltyLastN: 64,
  );

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
  Future<String?> translate(String chinese) {
    final result = _queue.then((_) => _generate(chinese));
    // The queue must survive a failed generation, so swallow the error here;
    // [_generate] has already turned it into a null for the caller.
    _queue = result.then((_) {}, onError: (_) {});
    return result;
  }

  Future<String?> _generate(String chinese) async {
    final engine = await _ensureEngine();
    if (engine == null) return null;

    EngineSession? session;
    try {
      session = await engine.createSession();
      final reply = StringBuffer();
      await for (final event in session.generate(
        prompt: promptFor(chinese),
        sampler: _sampler,
        maxTokens: _maxReplyTokens,
      )) {
        if (event is! TokenEvent) continue;
        reply.write(event.text);
        // A translation is one line. Stopping at the first break both trims
        // the answer and cancels the rest of the generation, which is the only
        // stop sequence available here — and the difference between "I am his
        // own." and "I am his own.\n10.1.1.1.1.1. 2011."
        if (reply.toString().contains('\n')) break;
      }
      return usableReply(reply.toString());
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
