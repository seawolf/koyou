import 'translation_backend.dart';

/// Stands in where there is no on-device model — see `on_device_backend.dart`.
///
/// A backend that always declines rather than a null, so callers have nothing
/// to branch on: declining is already how [TranslationBackend] says it has
/// nothing to offer.
TranslationBackend onDeviceBackend() => const _NoBackend();

class _NoBackend implements TranslationBackend {
  const _NoBackend();

  @override
  Future<String?> translate(String chinese) async => null;
}
