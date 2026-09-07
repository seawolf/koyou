import 'model_asset.dart';
import 'model_store.dart';
import 'on_device_backend_web.dart';
import 'web_model.dart';

/// The store for a browser, where the weights live in the origin's private
/// file system and wllama owns the cache.
ModelStore modelStore() => WebModelStore(ModelAsset.qwen08b, webModelEngine());
