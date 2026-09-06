import 'package:flutter/foundation.dart';

/// The weights the on-device translator runs, pinned to an exact file.
///
/// Pinned by digest on purpose. The weights are fetched over the network at
/// first run, so the digest is the only thing that says the 533MB which
/// arrived are the 533MB that were measured — and if the publisher replaces the
/// file, a failed check is the right outcome rather than a quietly different
/// model.
@immutable
class ModelAsset {
  const ModelAsset({
    required this.name,
    required this.url,
    required this.bytes,
    required this.sha256,
    required this.label,
    required this.licence,
  });

  /// File name on disk, and inside the publisher's repository.
  final String name;

  final String url;

  /// Exact size, so a download can show progress before the first byte and
  /// refuse a response whose length disagrees.
  final int bytes;

  /// Lower-case hex SHA-256, as published in the repository's LFS metadata.
  final String sha256;

  /// What to call it on screen.
  final String label;

  final String licence;

  /// Rounded for display: "533 MB", not "532517120 bytes".
  String get sizeLabel => '${(bytes / 1000000).round()} MB';

  /// Qwen3.5-0.8B at Q4_K_M — the smallest model measured to work, and the
  /// same file the numbers in `docs/local-model.md` come from.
  static const qwen08b = ModelAsset(
    name: 'Qwen3.5-0.8B-Q4_K_M.gguf',
    url:
        'https://huggingface.co/unsloth/Qwen3.5-0.8B-GGUF/resolve/main/'
        'Qwen3.5-0.8B-Q4_K_M.gguf',
    bytes: 532517120,
    sha256: 'bd258782e35f7f458f8aced1adc053e6e92e89bc735ba3be89d38a06121dc517',
    label: 'Qwen3.5 0.8B',
    licence: 'Apache 2.0',
  );
}

/// Where the weights have got to.
enum ModelState {
  /// No on-device model on this platform — the web build, in practice.
  unsupported,

  /// Supported, but nothing downloaded.
  absent,

  downloading,

  /// Downloaded, and being checked against [ModelAsset.sha256]. Separate from
  /// [downloading] because it takes a moment on a phone and looks like a hang.
  verifying,

  ready,

  /// Downloaded but switched off, so it can be turned back on without
  /// fetching 533MB again.
  disabled,

  failed,
}

/// What the model screen renders.
@immutable
class ModelStatus {
  const ModelStatus(
    this.state, {
    this.received = 0,
    this.total = 0,
    this.error,
  });

  final ModelState state;
  final int received;
  final int total;

  /// Why it failed, in words a learner can act on.
  final String? error;

  /// 0 to 1 while downloading, or null when there is nothing to show.
  double? get progress =>
      state == ModelState.downloading && total > 0 ? received / total : null;

  bool get isUsable => state == ModelState.ready;
}
