@Tags(['llama'])
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kouyu/pinyin/syllable.dart';
import 'package:kouyu/pinyin/tone.dart';
import 'package:kouyu/translation/dictionary.dart';
import 'package:kouyu/translation/model_translator.dart';
import 'package:kouyu/translation/on_device_backend_native.dart';
import 'package:kouyu/translation/translator.dart';

/// Exercises the real shipping path — llama.cpp and the real weights — rather
/// than the Ollama harness. Skipped unless both are pointed at:
///
///   KOUYU_LLAMA_LIB=/path/to/libllama.dylib \
///   KOUYU_LLAMA_MODEL=/path/to/Qwen3.5-0.8B-Q4_K_M.gguf \
///   flutter test --tags llama
///
/// The library has to be built from llama.cpp at the tag `llama_cpp_dart`
/// pins, which its README names. A mismatch is not a clean error: the struct
/// layout of `llama_model_params` shifts and the FFI call crashes the isolate.
/// On Android none of this applies, because the package bundles a matching
/// `libllama.so` itself.
Syllable _s(String initial, String rime, Tone tone) =>
    Syllable(initial: initial, rime: rime, tone: tone);

void main() {
  final library = Platform.environment['KOUYU_LLAMA_LIB'];
  final model = Platform.environment['KOUYU_LLAMA_MODEL'];
  final ready =
      library != null &&
      model != null &&
      File(library).existsSync() &&
      File(model).existsSync();

  late LlamaBackend backend;

  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    if (ready) {
      backend = LlamaBackend(modelPath: model, libraryPath: library);
    }
  });

  tearDownAll(() async {
    if (ready) await backend.dispose();
  });

  test('translates Chinese, and keeps the tone it was given', () async {
    if (!ready) {
      markTestSkipped('set KOUYU_LLAMA_LIB and KOUYU_LLAMA_MODEL');
      return;
    }

    // 卖 and 买 differ by tone alone in pinyin, which is what the dictionary
    // in front of this backend exists to settle.
    final selling = await backend.translate('我卖书');
    final buying = await backend.translate('我买书');

    expect(selling?.toLowerCase(), contains('sell'));
    expect(buying?.toLowerCase(), anyOf(contains('buy'), contains('bought')));
  });

  // The reason the prompt writes Qwen's markup by hand: left to its own
  // template the model spends every token inside <think> and answers nothing.
  test('answers rather than thinking out loud', () async {
    if (!ready) {
      markTestSkipped('set KOUYU_LLAMA_LIB and KOUYU_LLAMA_MODEL');
      return;
    }

    final answer = await backend.translate('你叫什么名字');
    expect(answer, isNotNull);
    expect(answer, isNot(contains('<think>')));
    // A question translated, not answered.
    expect(answer!.toLowerCase(), contains('name'));
  });

  test('the whole chain resolves pinyin and translates it', () async {
    if (!ready) {
      markTestSkipped('set KOUYU_LLAMA_LIB and KOUYU_LLAMA_MODEL');
      return;
    }

    final translator = ModelTranslator(
      dictionary: Dictionary.bundled(),
      backend: backend,
    );
    final result = await translator.translate(
      TranslationRequest([
        [_s('w', 'o', Tone.third)],
        [_s('m', 'ai', Tone.fourth)],
        [_s('sh', 'u', Tone.first)],
      ]),
    );

    expect(result, isNotNull);
    expect(result!.text.toLowerCase(), contains('sell'));
    expect(result.wordByWord, isFalse);
  });
}
