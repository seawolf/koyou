import 'package:flutter/foundation.dart';

import 'model_asset.dart';

export 'model_store_absent.dart' if (dart.library.io) 'model_store_native.dart';

/// Fetches, verifies, and forgets the on-device weights.
///
/// An interface for the same reason [TranslationBackend] is one: the web build
/// has no model and no file system to keep one in, so it gets an
/// implementation that reports [ModelState.unsupported] and does nothing. The
/// screen renders whichever it is given without asking which platform it is on.
abstract interface class ModelStore {
  ModelAsset get asset;

  /// Rebuilds the screen as the download moves.
  ValueListenable<ModelStatus> get status;

  /// Fetches the weights, resuming a part-finished download. Safe to call
  /// while one is running: the second call is ignored.
  Future<void> download();

  /// Stops a download, leaving what has arrived so [download] can resume it.
  void cancel();

  /// Deletes the weights and anything half-downloaded.
  Future<void> remove();

  /// Keeps the weights but stops using them, so turning the model back on
  /// costs nothing.
  Future<void> setEnabled(bool enabled);

  void dispose();
}
