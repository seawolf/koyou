import 'dart:async';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import 'model_asset.dart';
import 'model_store.dart';

/// The store for a platform that can hold weights on disk.
ModelStore modelStore() => NativeModelStore(ModelAsset.qwen08b);

/// Where the weights are kept. Injectable so tests need no plugin and no
/// 533MB.
typedef DirectoryLookup = Future<Directory> Function();

/// Where the weights live, and the two files that describe their state.
///
/// The app support directory rather than documents: these are not the
/// learner's files, they are the app's, and on iOS documents are offered up to
/// the Files app and backed up to iCloud — 533MB of re-downloadable weights
/// should be neither.
Future<File> weightsFile(
  ModelAsset asset, [
  DirectoryLookup? directory,
]) async => File(
  '${(await (directory ?? getApplicationSupportDirectory)()).path}/${asset.name}',
);

/// A part-finished download. Kept on failure so it can be resumed.
Future<File> partialFile(
  ModelAsset asset, [
  DirectoryLookup? directory,
]) async => File('${(await weightsFile(asset, directory)).path}.part');

/// Present when the model is downloaded but switched off.
///
/// A marker beside the weights rather than a stored preference: it describes
/// the file, it disappears with the file, and it spares the app a preferences
/// dependency for one boolean.
Future<File> disabledMarker(
  ModelAsset asset, [
  DirectoryLookup? directory,
]) async => File('${(await weightsFile(asset, directory)).path}.disabled');

/// Whether the weights are present and switched on.
Future<bool> weightsUsable(
  ModelAsset asset, [
  DirectoryLookup? directory,
]) async {
  try {
    final file = await weightsFile(asset, directory);
    if (!file.existsSync()) return false;
    return !(await disabledMarker(asset, directory)).existsSync();
  } on Object {
    return false;
  }
}

class NativeModelStore implements ModelStore {
  NativeModelStore(this.asset, {this.directory, Uri? source})
    : source = source ?? Uri.parse(asset.url) {
    _refresh();
  }

  @override
  final ModelAsset asset;

  /// Overridden by tests; null means the app's support directory.
  final DirectoryLookup? directory;

  /// Where to fetch from. Overridden by tests so the resume and checksum paths
  /// can be exercised against a local server.
  final Uri source;

  @override
  final ValueNotifier<ModelStatus> status = ValueNotifier(
    const ModelStatus(ModelState.absent),
  );

  HttpClient? _client;
  bool _cancelled = false;
  bool _busy = false;

  Future<void> _refresh() async {
    try {
      final file = await weightsFile(asset, directory);
      if (!file.existsSync()) {
        final partial = await partialFile(asset, directory);
        status.value = ModelStatus(
          ModelState.absent,
          received: partial.existsSync() ? partial.lengthSync() : 0,
          total: asset.bytes,
        );
        return;
      }
      final off = (await disabledMarker(asset, directory)).existsSync();
      status.value = ModelStatus(off ? ModelState.disabled : ModelState.ready);
    } on Object {
      status.value = const ModelStatus(ModelState.unsupported);
    }
  }

  @override
  Future<void> download() async {
    if (_busy) return;
    _busy = true;
    _cancelled = false;
    try {
      await _fetch();
    } finally {
      _busy = false;
      _client?.close(force: true);
      _client = null;
    }
  }

  Future<void> _fetch() async {
    final partial = await partialFile(asset, directory);
    var already = partial.existsSync() ? partial.lengthSync() : 0;
    // More on disk than the file is long means it is not this file.
    if (already > asset.bytes) {
      partial.deleteSync();
      already = 0;
    }
    status.value = ModelStatus(
      ModelState.downloading,
      received: already,
      total: asset.bytes,
    );

    IOSink? sink;
    try {
      final client = _client = HttpClient()
        ..connectionTimeout = const Duration(seconds: 30);
      final request = await client.getUrl(source);
      // Resume rather than start again: this is 533MB over a phone's
      // connection, and it will be interrupted.
      if (already > 0) request.headers.set('range', 'bytes=$already-');
      final response = await request.close();

      final resuming =
          already > 0 && response.statusCode == HttpStatus.partialContent;
      if (response.statusCode != HttpStatus.ok && !resuming) {
        throw HttpException('${response.statusCode} from the model host');
      }
      // A 200 to a range request means the host ignored it, so start over
      // rather than append to what is there.
      if (already > 0 && !resuming) already = 0;

      sink = partial.openWrite(
        mode: already > 0 ? FileMode.append : FileMode.write,
      );
      var received = already;
      await for (final chunk in response) {
        if (_cancelled) break;
        sink.add(chunk);
        received += chunk.length;
        status.value = ModelStatus(
          ModelState.downloading,
          received: received,
          total: asset.bytes,
        );
      }
      await sink.flush();
      await sink.close();
      sink = null;

      if (_cancelled) {
        await _refresh();
        return;
      }
      if (partial.lengthSync() != asset.bytes) {
        throw const FileSystemException('the download ended early');
      }

      status.value = const ModelStatus(ModelState.verifying);
      if (!await _digestMatches(partial)) {
        partial.deleteSync();
        throw const FileSystemException(
          'the downloaded weights did not match their checksum',
        );
      }

      final destination = await weightsFile(asset, directory);
      if (destination.existsSync()) destination.deleteSync();
      partial.renameSync(destination.path);
      final marker = await disabledMarker(asset, directory);
      if (marker.existsSync()) marker.deleteSync();
      status.value = const ModelStatus(ModelState.ready);
    } on Object catch (error) {
      await sink?.close();
      final partialBytes = partial.existsSync() ? partial.lengthSync() : 0;
      status.value = ModelStatus(
        ModelState.failed,
        received: partialBytes,
        total: asset.bytes,
        error: _explain(error),
      );
    }
  }

  /// Hashes the file in chunks. Reading 533MB into memory to hash it would be
  /// the largest allocation the app ever made, on the device least able to
  /// afford it.
  Future<bool> _digestMatches(File file) async {
    final sink = _DigestSink();
    final input = sha256.startChunkedConversion(sink);
    await for (final chunk in file.openRead()) {
      input.add(chunk);
    }
    input.close();
    return sink.digest.toString() == asset.sha256;
  }

  static String _explain(Object error) => switch (error) {
    SocketException() => 'No connection to the model host.',
    HttpException(:final message) => message,
    FileSystemException(:final message) => message,
    _ => 'The download did not finish.',
  };

  @override
  void cancel() {
    _cancelled = true;
    _client?.close(force: true);
  }

  @override
  Future<void> remove() async {
    cancel();
    for (final file in [
      await weightsFile(asset, directory),
      await partialFile(asset, directory),
      await disabledMarker(asset, directory),
    ]) {
      if (file.existsSync()) file.deleteSync();
    }
    await _refresh();
  }

  @override
  Future<void> setEnabled(bool enabled) async {
    final marker = await disabledMarker(asset, directory);
    if (enabled) {
      if (marker.existsSync()) marker.deleteSync();
    } else if (!marker.existsSync()) {
      marker.writeAsStringSync('');
    }
    await _refresh();
  }

  @override
  void dispose() {
    cancel();
    status.dispose();
  }
}

/// Collects the one digest `startChunkedConversion` emits.
class _DigestSink implements Sink<Digest> {
  late Digest digest;

  @override
  void add(Digest data) => digest = data;

  @override
  void close() {}
}
