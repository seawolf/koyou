@Tags(['llama'])
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kouyu/pinyin/syllable.dart';
import 'package:kouyu/pinyin/word.dart';
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
    final selling = await backend.intoEnglish('我卖书');
    final buying = await backend.intoEnglish('我买书');

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

    final answer = await backend.intoEnglish('你叫什么名字');
    expect(answer, isNotNull);
    expect(answer, isNot(contains('<think>')));
    // A question translated, not answered.
    expect(answer!.toLowerCase(), contains('name'));
  });

  // The defect behind the nonsense on a real device: the screen asks on every
  // keystroke, so generations overlap, and sessions created on one engine
  // share KV sequence 0. Overlapping, five requests used to give
  // "I am. 10. 11. 12." for 我是 and throw on the other four.
  test('overlapping requests do not corrupt each other', () async {
    if (!ready) {
      markTestSkipped('set KOUYU_LLAMA_LIB and KOUYU_LLAMA_MODEL');
      return;
    }

    const typing = ['我是', '我是他', '我是他的', '我是他的老', '我是他的老公'];
    final answers = await Future.wait(typing.map(backend.intoEnglish));

    for (var i = 0; i < typing.length; i++) {
      final answer = answers[i];
      expect(answer, isNotNull, reason: typing[i]);
      expect(answer, isNot(contains('\n')), reason: typing[i]);
      // The corruption announced itself as a numbered list.
      expect(
        RegExp(r'\b1[0-9]\.').hasMatch(answer!),
        isFalse,
        reason: '${typing[i]} gave $answer',
      );
      expect(answer.toLowerCase(), contains('i am'), reason: typing[i]);
    }
  });

  // Same five again, one at a time, so a pass above cannot be luck.
  test('answers are the same whether asked at once or in turn', () async {
    if (!ready) {
      markTestSkipped('set KOUYU_LLAMA_LIB and KOUYU_LLAMA_MODEL');
      return;
    }

    const typing = ['我是他', '我是他的老公'];
    final together = await Future.wait(typing.map(backend.intoEnglish));
    final inTurn = <String?>[];
    for (final chinese in typing) {
      inTurn.add(await backend.intoEnglish(chinese));
    }
    expect(together, inTurn);
  });

  // A name goes through untranslated, which is why a literal needs no special
  // handling downstream: 我叫Steve is ordinary Chinese text.
  test('carries a name through the whole chain', () async {
    if (!ready) {
      markTestSkipped('set KOUYU_LLAMA_LIB and KOUYU_LLAMA_MODEL');
      return;
    }

    final translator = ModelTranslator(
      dictionary: Dictionary.bundled(),
      backend: backend,
    );
    // wǒ jiào Steve
    final result = await translator.translate(
      TranslationRequest([
        Spoken([_s('w', 'o', Tone.third)]),
        Spoken([_s('j', 'iao', Tone.fourth)]),
        const Literal('Steve'),
      ]),
    );

    expect(result, isNotNull);
    expect(result!.text, contains('Steve'));
    expect(result.text.toLowerCase(), contains('name'));
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
        Spoken([_s('w', 'o', Tone.third)]),
        Spoken([_s('m', 'ai', Tone.fourth)]),
        Spoken([_s('sh', 'u', Tone.first)]),
      ]),
    );

    expect(result, isNotNull);
    expect(result!.text.toLowerCase(), contains('sell'));
    expect(result.wordByWord, isFalse);
  });
}
