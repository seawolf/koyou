import 'package:flutter_test/flutter_test.dart';
import 'package:kouyu/translation/model_asset.dart';
import 'package:kouyu/translation/web_model.dart';

/// A browser runtime that isn't one, so the decisions can be tested without a
/// GPU, a browser, or 533MB.
class _FakeEngine implements WebModelEngine {
  _FakeEngine({this.supportedHere = true, this.cached = 0, this.loads = true});

  bool supportedHere;
  int cached;
  bool loads;

  /// Set directly by the tests that care what comes back.
  String? reply = 'I sell books.';

  @override
  bool ready = false;

  @override
  double progress = 0;

  @override
  String? error;

  @override
  bool enabled = true;

  int loadCalls = 0;
  int translateCalls = 0;
  final List<String> prompts = [];

  @override
  Future<bool> supported() async => supportedHere;

  @override
  Future<int> cachedBytes(String url) async => cached;

  @override
  Future<bool> load(String url, int contextTokens) async {
    loadCalls++;
    if (!loads) {
      error = 'no WebGPU and no fallback';
      return false;
    }
    ready = true;
    cached = ModelAsset.qwen08b.bytes;
    progress = 1;
    return true;
  }

  @override
  Future<String?> translate(String prompt, int maxTokens) async {
    translateCalls++;
    prompts.add(prompt);
    return reply;
  }

  @override
  void setEnabled(bool on) => enabled = on;

  @override
  Future<bool> remove(String url) async {
    ready = false;
    cached = 0;
    progress = 0;
    return true;
  }
}

void main() {
  group('the backend', () {
    // A keystroke must never start a 533MB download. Until the weights are
    // cached this declines and the dictionary answers, exactly as on a phone.
    test('declines until the weights are cached', () async {
      final engine = _FakeEngine();
      final backend = WllamaBackend(engine);

      expect(await backend.translate('我卖书'), isNull);
      expect(engine.loadCalls, 0, reason: 'nothing may be fetched');
      expect(engine.translateCalls, 0);
    });

    test('loads and answers once they are', () async {
      final engine = _FakeEngine(cached: ModelAsset.qwen08b.bytes);
      final backend = WllamaBackend(engine);

      expect(await backend.translate('我卖书'), 'I sell books.');
      expect(engine.loadCalls, 1);
      // The prompt is the shared one, with the closed think block that stops
      // Qwen reasoning instead of answering.
      expect(engine.prompts.single, contains('<|im_start|>system'));
      expect(engine.prompts.single, contains('<think>\n\n</think>'));
      expect(engine.prompts.single, contains('我卖书'));
    });

    test('loads once, not per phrase', () async {
      final engine = _FakeEngine(cached: ModelAsset.qwen08b.bytes);
      final backend = WllamaBackend(engine);

      await backend.translate('我卖书');
      await backend.translate('我买书');
      expect(engine.loadCalls, 1);
      expect(engine.translateCalls, 2);
    });

    // A browser that cannot run it at all should be asked once, not on every
    // phrase for the rest of the session.
    test('stops asking after a real failure', () async {
      final engine = _FakeEngine(
        cached: ModelAsset.qwen08b.bytes,
        loads: false,
      );
      final backend = WllamaBackend(engine);

      expect(await backend.translate('我卖书'), isNull);
      expect(await backend.translate('我买书'), isNull);
      expect(engine.loadCalls, 1);
    });

    test(
      'keeps only the first line, and only if it reads as English',
      () async {
        final engine = _FakeEngine(cached: ModelAsset.qwen08b.bytes);
        final backend = WllamaBackend(engine);

        engine.reply = 'I sell books.\n10. 11. 12.';
        expect(await backend.translate('我卖书'), 'I sell books.');

        engine.reply = '10. 1.1.1. 2011.';
        expect(await backend.translate('我卖书'), isNull);

        engine.reply = 'console.log("hi");';
        expect(await backend.translate('我卖书'), isNull);

        engine.reply = null;
        expect(await backend.translate('我卖书'), isNull);
      },
    );
  });

  group('the store', () {
    test('says so where a browser cannot run it', () async {
      final store = WebModelStore(
        ModelAsset.qwen08b,
        _FakeEngine(supportedHere: false),
      );
      addTearDown(store.dispose);
      await pumpEventQueue();
      expect(store.status.value.state, ModelState.unsupported);
    });

    test('reports absent, then ready after a download', () async {
      final engine = _FakeEngine();
      final store = WebModelStore(ModelAsset.qwen08b, engine);
      addTearDown(store.dispose);
      await pumpEventQueue();
      expect(store.status.value.state, ModelState.absent);
      expect(store.status.value.total, ModelAsset.qwen08b.bytes);

      await store.download();
      expect(store.status.value.state, ModelState.ready);
    });

    test('reports a failure with a reason', () async {
      final engine = _FakeEngine(loads: false);
      final store = WebModelStore(ModelAsset.qwen08b, engine);
      addTearDown(store.dispose);

      await store.download();
      expect(store.status.value.state, ModelState.failed);
      expect(store.status.value.error, contains('WebGPU'));
    });

    test('switching off keeps the download', () async {
      final engine = _FakeEngine(cached: ModelAsset.qwen08b.bytes);
      final store = WebModelStore(ModelAsset.qwen08b, engine);
      addTearDown(store.dispose);
      await pumpEventQueue();
      expect(store.status.value.state, ModelState.ready);

      await store.setEnabled(false);
      expect(store.status.value.state, ModelState.disabled);
      expect(engine.cached, greaterThan(0), reason: 'the bytes stay');

      await store.setEnabled(true);
      expect(store.status.value.state, ModelState.ready);
    });

    test('removing goes back to absent', () async {
      final engine = _FakeEngine(cached: ModelAsset.qwen08b.bytes);
      final store = WebModelStore(ModelAsset.qwen08b, engine);
      addTearDown(store.dispose);

      await store.remove();
      expect(store.status.value.state, ModelState.absent);
      expect(engine.cached, 0);
    });

    test('a second download while one runs is ignored', () async {
      final engine = _FakeEngine();
      final store = WebModelStore(ModelAsset.qwen08b, engine);
      addTearDown(store.dispose);

      await Future.wait([store.download(), store.download()]);
      expect(engine.loadCalls, 1);
    });
  });
}
