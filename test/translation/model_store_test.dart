import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kouyu/translation/model_asset.dart';
import 'package:kouyu/translation/model_store_native.dart';

/// Stands in for 533MB of weights: a few hundred bytes with a real digest, so
/// the resume and checksum paths can be exercised in milliseconds.
final _weights = utf8.encode('pretend these are GGUF weights' * 20);

ModelAsset _asset({String? digest}) => ModelAsset(
  name: 'test-weights.gguf',
  url: 'http://example.invalid/unused',
  bytes: _weights.length,
  sha256: digest ?? sha256.convert(_weights).toString(),
  label: 'Test weights',
  licence: 'Apache 2.0',
);

/// Serves [_weights], honours `Range`, and can be told to cut the response
/// short so a resume has something to resume from.
class _Host {
  _Host(this.server);

  final HttpServer server;
  int rangeRequests = 0;

  /// Bytes to send before hanging up, or null to serve the lot.
  int? truncateAt;

  static Future<_Host> start() async {
    final host = _Host(await HttpServer.bind(InternetAddress.loopbackIPv4, 0));
    host.server.listen((request) async {
      final range = request.headers.value('range');
      var from = 0;
      if (range != null) {
        host.rangeRequests++;
        from = int.parse(RegExp(r'bytes=(\d+)-').firstMatch(range)!.group(1)!);
        request.response.statusCode = HttpStatus.partialContent;
      }
      var body = _weights.sublist(from);
      final cut = host.truncateAt;
      if (cut != null && cut < body.length) body = body.sublist(0, cut);
      request.response.add(body);
      await request.response.close();
    });
    return host;
  }

  Uri get url => Uri.parse('http://127.0.0.1:${server.port}/weights.gguf');

  Future<void> stop() => server.close(force: true);
}

void main() {
  late Directory directory;
  late _Host host;

  setUp(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    // The mock HttpClient flutter_test installs answers 400 to everything.
    HttpOverrides.global = null;
    directory = await Directory.systemTemp.createTemp('kouyu-model');
    host = await _Host.start();
  });

  tearDown(() async {
    await host.stop();
    directory.deleteSync(recursive: true);
  });

  NativeModelStore store([ModelAsset? asset]) => NativeModelStore(
    asset ?? _asset(),
    directory: () async => directory,
    source: host.url,
  );

  Future<ModelState> settle(NativeModelStore subject) async {
    await subject.download();
    return subject.status.value.state;
  }

  test('downloads, verifies, and reports ready', () async {
    final subject = store();
    addTearDown(subject.dispose);

    expect(await settle(subject), ModelState.ready);
    final file = await weightsFile(subject.asset, () async => directory);
    expect(file.existsSync(), isTrue);
    expect(file.lengthSync(), _weights.length);
    // Nothing left behind.
    final partial = await partialFile(subject.asset, () async => directory);
    expect(partial.existsSync(), isFalse);
  });

  // The whole reason for the .part file: 533MB over a phone's connection will
  // be interrupted, and starting again from zero is not acceptable.
  test('resumes from what already arrived', () async {
    host.truncateAt = 100;
    final subject = store();
    addTearDown(subject.dispose);

    expect(await settle(subject), ModelState.failed);
    final partial = await partialFile(subject.asset, () async => directory);
    expect(partial.lengthSync(), 100, reason: 'the part-download is kept');
    expect(subject.status.value.received, 100);

    host.truncateAt = null;
    expect(await settle(subject), ModelState.ready);
    expect(host.rangeRequests, 1, reason: 'it asked for the rest, not the lot');
  });

  // A wrong file is worse than no file: it would load as a different model, or
  // crash the engine.
  test('refuses weights that do not match their digest', () async {
    final subject = store(_asset(digest: 'f' * 64));
    addTearDown(subject.dispose);

    expect(await settle(subject), ModelState.failed);
    expect(subject.status.value.error, contains('checksum'));
    final file = await weightsFile(subject.asset, () async => directory);
    expect(file.existsSync(), isFalse);
    // The bad bytes are gone too, so a retry cannot resume onto them.
    final partial = await partialFile(subject.asset, () async => directory);
    expect(partial.existsSync(), isFalse);
  });

  test('switching off keeps the download; deleting does not', () async {
    final subject = store();
    addTearDown(subject.dispose);
    await settle(subject);

    await subject.setEnabled(false);
    expect(subject.status.value.state, ModelState.disabled);
    final file = await weightsFile(subject.asset, () async => directory);
    expect(file.existsSync(), isTrue, reason: 'switching off must not delete');
    expect(await weightsUsable(subject.asset, () async => directory), isFalse);

    await subject.setEnabled(true);
    expect(subject.status.value.state, ModelState.ready);
    expect(await weightsUsable(subject.asset, () async => directory), isTrue);

    await subject.remove();
    expect(subject.status.value.state, ModelState.absent);
    expect(file.existsSync(), isFalse);
  });

  test('a second download while one runs is ignored', () async {
    final subject = store();
    addTearDown(subject.dispose);

    final first = subject.download();
    final second = subject.download();
    await Future.wait([first, second]);
    expect(subject.status.value.state, ModelState.ready);
  });

  test('reports a host that is not there, and keeps nothing', () async {
    final subject = NativeModelStore(
      _asset(),
      directory: () async => directory,
      source: Uri.parse('http://127.0.0.1:1/weights.gguf'),
    );
    addTearDown(subject.dispose);

    expect(await settle(subject), ModelState.failed);
    expect(subject.status.value.error, isNotNull);
  });
}
