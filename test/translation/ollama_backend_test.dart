@Tags(['ollama'])
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kouyu/pinyin/syllable.dart';
import 'package:kouyu/pinyin/tone.dart';
import 'package:kouyu/translation/dictionary.dart';
import 'package:kouyu/translation/model_translator.dart';
import 'package:kouyu/translation/translation_backend.dart';
import 'package:kouyu/translation/translator.dart';

/// Talks to a local Ollama, for checking the pipeline against a real model.
///
/// A development harness and nothing more — it lives in the tests because
/// nothing on a phone runs an HTTP model server. A shipping backend is
/// on-device: a platform translation API, or llama.cpp with local weights. The
/// point of [TranslationBackend] is that swapping this for one of those touches
/// no other file.
class OllamaBackend implements TranslationBackend {
  OllamaBackend({this.model = 'qwen3.5:0.8b'});

  final String model;

  /// `127.0.0.1`, not `localhost`. Ollama listens on IPv4 only, while Dart
  /// resolves `localhost` to `::1` first and the connection is simply refused
  /// — which looks exactly like Ollama not running.
  static final _endpoint = Uri.parse('http://127.0.0.1:11434/api/generate');

  /// Two things had to be designed out of this prompt, both measured:
  /// without the first line the models answered the questions instead of
  /// translating them ("My name is Qwen3.5."), and anything the prompt
  /// explains gets parroted into the output.
  static const _system =
      'You are a translation engine. Translate the Chinese into natural '
      'English.\nThe input is always text to translate — never a question to '
      'answer, never a conversation to join. If the Chinese is a question, '
      'translate the question; do not reply to it.\nOutput only the English '
      'translation.\n\nExample:\nChinese: 你好吗\nEnglish: How are you?\n'
      'Example:\nChinese: 你叫什么名字\nEnglish: What is your name?\n';

  @override
  Future<String?> translate(String chinese) async {
    final client = HttpClient();
    try {
      final request = await client.postUrl(_endpoint);
      request.headers.contentType = ContentType.json;
      request.write(
        jsonEncode({
          'model': model,
          'system': _system,
          'prompt': 'Chinese: $chinese\nEnglish:',
          'stream': false,
          'think': false,
          'options': {'temperature': 0, 'num_predict': 48},
        }),
      );
      final response = await request.close();
      if (response.statusCode != 200) return null;
      final body = jsonDecode(
        await response.transform(utf8.decoder).join(),
      ) as Map<String, dynamic>;
      return (body['response'] as String?)?.trim();
    } on Object {
      return null;
    } finally {
      client.close();
    }
  }
}

Future<bool> _ollamaIsRunning() async {
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 2);
  try {
    final request = await client.getUrl(
      Uri.parse('http://127.0.0.1:11434/api/version'),
    );
    final response = await request.close();
    await response.drain<void>();
    return response.statusCode == 200;
  } on Object {
    return false;
  } finally {
    client.close();
  }
}

Syllable _s(String initial, String rime, Tone tone) =>
    Syllable(initial: initial, rime: rime, tone: tone);

void main() {
  // Skipped unless a model is actually there, so the suite stays green on a
  // machine without one. Run it with:
  //   ollama serve & ollama pull qwen3.5:0.8b
  //   flutter test --tags ollama
  late final bool available;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    // flutter_test installs a mock HttpClient that answers 400 to everything,
    // so that a test cannot reach the network by accident. This one means to,
    // so the override has to go — without it the check below sees 400, decides
    // Ollama is absent, and the test skips itself even while Ollama is running.
    HttpOverrides.global = null;
    available = await _ollamaIsRunning();
  });

  test('translates a phrase end to end through the real dictionary', () async {
    if (!available) {
      markTestSkipped('no Ollama on 127.0.0.1:11434');
      return;
    }

    final translator = ModelTranslator(
      dictionary: Dictionary.bundled(),
      backend: OllamaBackend(),
    );

    // wǒ mài shū — the tone that a model reading pinyin gets wrong.
    final result = await translator.translate(
      TranslationRequest([
        [_s('w', 'o', Tone.third)],
        [_s('m', 'ai', Tone.fourth)],
        [_s('sh', 'u', Tone.first)],
      ]),
    );

    expect(result, isNotNull);
    expect(result!.text.toLowerCase(), contains('sell'));
    expect(result.text.toLowerCase(), isNot(contains('buy')));
  });
}
