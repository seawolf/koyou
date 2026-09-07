import 'package:flutter/foundation.dart';

import 'model_asset.dart';

export 'model_store_web.dart' if (dart.library.io) 'model_store_native.dart';

/// Fetches, verifies, and forgets the on-device weights.
///
/// An interface because the two platforms keep the weights in different
/// places and by different means. On a phone this owns the file: a resumable
/// download, a digest check, a part-file. In a browser wllama owns the OPFS
/// cache, so the web store reports and drives rather than managing bytes —
/// duplicating that would mean two caches disagreeing.
///
/// The screen renders whichever it is given without asking which it has, and a
/// platform with no model at all reports [ModelState.unsupported].
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
