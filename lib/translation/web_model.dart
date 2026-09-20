/// The browser model tier, with none of the browser in it.
///
/// Separated from `on_device_backend_web.dart` so the decisions worth testing
/// — decline until the weights are cached, stop asking after a real failure,
/// keep only a usable reply, report a download honestly — can be tested on the
/// VM with a fake engine. Only the JS binding needs a browser, and it is the
/// one thing here with no logic in it.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';

import 'english_prompt.dart';
import 'model_asset.dart';
import 'model_prompt.dart';
import 'model_store.dart';
import 'translation_backend.dart';

class WllamaBackend implements TranslationBackend {
  WllamaBackend(this.engine);

  final WebModelEngine engine;

  /// Room for the system prompt, a phrase and its translation, and no more.
  static const _contextTokens = 1024;

  bool _unavailable = false;

  @override
  Future<String?> intoEnglish(String chinese) => _run(
    prompt: promptFor(chinese),
    maxTokens: maxReplyTokens,
    keep: usableReply,
  );

  @override
  Future<String?> intoChinese(String english) => _run(
    prompt: chinesePromptFor(english),
    maxTokens: maxChineseTokens,
    keep: usableChinese,
  );

  Future<String?> _run({
    required String prompt,
    required int maxTokens,
    required String? Function(String) keep,
  }) async {
    if (_unavailable) return null;

    if (!engine.ready) {
      // Only ever loads what is already in the cache: a 533MB download is the
      // model screen's job, asked for, not something a keystroke starts.
      if (await engine.cachedBytes(ModelAsset.qwen08b.url) <= 0) return null;
      if (!await engine.load(ModelAsset.qwen08b.url, _contextTokens)) {
        // A browser that cannot run it at all. Stop asking.
        _unavailable = true;
        return null;
      }
    }

    final reply = await engine.translate(prompt, maxTokens);
    return reply == null ? null : keep(reply);
  }
}

/// What this app asks of a browser model runtime.
///
/// A seam so the backend's own decisions — decline until cached, stop asking
/// after a real failure, keep only a usable reply — are testable without a
/// browser, a GPU, or 533MB. The JS binding below is the only part that cannot
/// be.
abstract interface class WebModelEngine {
  bool get ready;

  /// Whether this browser has the pieces at all: wllama staged, and a private
  /// file system to keep weights in.
  Future<bool> supported();

  /// Bytes of these weights already cached, or 0.
  Future<int> cachedBytes(String url);

  Future<bool> load(String url, int contextTokens);

  /// Runs [prompt] and gives back the raw reply, for the caller to judge.
  /// Direction-agnostic: the prompt already says which way round it is.
  Future<String?> translate(String prompt, int maxTokens);

  double get progress;
  String? get error;

  /// Whether the learner has left the tier switched on.
  bool get enabled;
  void setEnabled(bool enabled);

  Future<bool> remove(String url);
}

class WebModelStore implements ModelStore {
  WebModelStore(this.asset, this.engine) {
    _refresh();
  }

  @override
  final ModelAsset asset;

  final WebModelEngine engine;

  @override
  final ValueNotifier<ModelStatus> status = ValueNotifier(
    const ModelStatus(ModelState.absent),
  );

  Timer? _polling;

  Future<void> _refresh() async {
    if (!await engine.supported()) {
      status.value = const ModelStatus(ModelState.unsupported);
      return;
    }
    final cached = await engine.cachedBytes(asset.url);
    if (cached <= 0) {
      status.value = ModelStatus(ModelState.absent, total: asset.bytes);
      return;
    }
    status.value = ModelStatus(
      engine.enabled ? ModelState.ready : ModelState.disabled,
    );
  }

  @override
  Future<void> download() async {
    if (status.value.state == ModelState.downloading) return;
    status.value = ModelStatus(ModelState.downloading, total: asset.bytes);

    // wllama reports progress into its own state rather than calling back into
    // Dart, so it is read on a timer. A frame's worth of interval: a 533MB
    // download does not need finer.
    _polling = Timer.periodic(const Duration(milliseconds: 250), (_) {
      if (status.value.state != ModelState.downloading) return;
      status.value = ModelStatus(
        ModelState.downloading,
        received: (engine.progress * asset.bytes).round(),
        total: asset.bytes,
      );
    });

    final loaded = await engine.load(asset.url, 1024);
    _polling?.cancel();
    _polling = null;

    if (!loaded) {
      status.value = ModelStatus(
        ModelState.failed,
        total: asset.bytes,
        error: engine.error ?? 'The download did not finish.',
      );
      return;
    }
    await _refresh();
  }

  /// Stops reporting, and nothing else.
  ///
  /// wllama takes an abort signal for a completion but not for a model fetch,
  /// so the request already in flight runs to the end and lands in the cache.
  /// That is why this returns the screen to "not downloaded" rather than
  /// claiming to have stopped anything: asking again afterwards finishes at
  /// once, because the bytes are already there.
  @override
  void cancel() {
    _polling?.cancel();
    _polling = null;
    if (status.value.state == ModelState.downloading) {
      status.value = ModelStatus(ModelState.absent, total: asset.bytes);
    }
  }

  @override
  Future<void> remove() async {
    cancel();
    await engine.remove(asset.url);
    await _refresh();
  }

  @override
  Future<void> setEnabled(bool enabled) async {
    engine.setEnabled(enabled);
    await _refresh();
  }

  @override
  void dispose() {
    _polling?.cancel();
    status.dispose();
  }
}
