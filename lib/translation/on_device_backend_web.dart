import 'dart:js_interop';

import 'translation_backend.dart';
import 'web_model.dart';

/// The on-device backend in a browser.
///
/// The same model and the same prompt as the phone: wllama is llama.cpp
/// compiled to WASM with a WebGPU backend, so it runs the very GGUF the native
/// tier does. Measured in a browser with WebGPU, the answers matched the native
/// ones exactly — 我卖书 to "I sell books.", 我买书 to "I bought a book." — at
/// about 300ms each after the first.
///
/// Declines until the weights are cached, exactly as the native one does, so
/// the dictionary answers on its own until someone asks for the download.
TranslationBackend onDeviceBackend() => WllamaBackend(webModelEngine());

/// The one browser runtime, shared by the backend and the model store so they
/// cannot disagree about whether the weights are loaded.
WebModelEngine webModelEngine() => _shared ??= _JsWllama();
WebModelEngine? _shared;

/// [WebModelEngine] over `web/kouyu_model.js`.
class _JsWllama implements WebModelEngine {
  @override
  bool get ready => _model?.ready() ?? false;

  @override
  double get progress => _model?.progress() ?? 0;

  @override
  String? get error => _model?.error();

  @override
  bool get enabled => _model?.enabled() ?? false;

  @override
  void setEnabled(bool enabled) => _model?.setEnabled(enabled);

  @override
  Future<bool> supported() async {
    final model = _model;
    if (model == null) return false;
    return (await model.supported().toDart).toDart;
  }

  @override
  Future<int> cachedBytes(String url) async {
    final model = _model;
    if (model == null) return 0;
    return (await model.cachedBytes(url).toDart).toDartInt;
  }

  @override
  Future<bool> load(String url, int contextTokens) async {
    final model = _model;
    if (model == null) return false;
    return (await model.load(url, contextTokens).toDart).toDart;
  }

  @override
  Future<String?> translate(String prompt, int maxTokens) async {
    final model = _model;
    if (model == null) return null;
    return (await model.translate(prompt, maxTokens).toDart)?.toDart;
  }

  @override
  Future<bool> remove(String url) async {
    final model = _model;
    if (model == null) return false;
    return (await model.remove(url).toDart).toDart;
  }

  /// Null when the glue has not loaded — which is what a build without
  /// `tool/fetch_wllama.sh` having been run looks like.
  _KouyuModel? get _model => _kouyuModel;
}

@JS('kouyuModel')
external _KouyuModel? get _kouyuModel;

@JS()
@staticInterop
class _KouyuModel {}

extension on _KouyuModel {
  external bool ready();
  external double progress();
  external String? error();
  external bool enabled();
  external void setEnabled(bool on);
  external JSPromise<JSBoolean> supported();
  external JSPromise<JSNumber> cachedBytes(String url);
  external JSPromise<JSBoolean> load(String url, int contextTokens);
  external JSPromise<JSString?> translate(String prompt, int maxTokens);
  external JSPromise<JSBoolean> remove(String url);
}
