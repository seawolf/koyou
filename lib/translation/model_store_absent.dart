import 'package:flutter/foundation.dart';

import 'model_asset.dart';
import 'model_store.dart';

/// The store on a platform with no on-device model — see `model_store.dart`.
ModelStore modelStore() => _AbsentStore();

class _AbsentStore implements ModelStore {
  @override
  final ModelAsset asset = ModelAsset.qwen08b;

  @override
  final ValueNotifier<ModelStatus> status = ValueNotifier(
    const ModelStatus(ModelState.unsupported),
  );

  @override
  Future<void> download() async {}

  @override
  void cancel() {}

  @override
  Future<void> remove() async {}

  @override
  Future<void> setEnabled(bool enabled) async {}

  @override
  void dispose() => status.dispose();
}
