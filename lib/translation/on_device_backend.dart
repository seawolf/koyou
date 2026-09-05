/// Resolves the on-device translation backend, or nothing where there is none.
///
/// Conditional so that the web build never reaches the native implementation:
/// it depends on `dart:ffi` and a bundled llama.cpp, neither of which exists in
/// a browser. Web gets [onDeviceBackend] returning null and falls through to the
/// dictionary, which is a complete product on its own.
library;

export 'on_device_backend_absent.dart'
    if (dart.library.io) 'on_device_backend_native.dart';
