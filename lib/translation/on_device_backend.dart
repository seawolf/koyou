/// Resolves the on-device translation backend, or nothing where there is none.
///
/// Conditional because the two run the same model through different runtimes:
/// the native one is llama.cpp over `dart:ffi`, and the web one is the same
/// llama.cpp compiled to WASM with a WebGPU backend, reached through
/// `dart:js_interop`. Neither import survives on the other platform.
///
/// Both decline until the weights are on the device, so until someone asks for
/// the download the dictionary answers on its own — which is a complete
/// product either way.
library;

export 'on_device_backend_web.dart'
    if (dart.library.io) 'on_device_backend_native.dart';
