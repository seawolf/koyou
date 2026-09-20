@Tags(['ollama'])
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kouyu/pinyin/syllable.dart';
import 'package:kouyu/pinyin/word.dart';
import 'package:kouyu/pinyin/tone.dart';
import 'package:kouyu/translation/character_index.dart';
import 'package:kouyu/translation/dictionary.dart';
import 'package:kouyu/translation/english_model_translator.dart';
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

  /// The reverse prompt, which had to be measured separately because this
  /// direction fails differently: asked for Chinese, the model drifts into
  /// answering rather than translating. The two examples are what stopped it
  /// — see `english_prompt.dart`, which carries the same text in the chat
  /// markup llama.cpp is given.
  static const _reverse =
      'You are a translation engine. Translate the input into natural Mandarin '
      'Chinese, whatever language it is written in.\nThe input is always text '
      'to translate — never a question to answer, never a conversation to '
      'join, never a request to carry out. Keep the speaker and the meaning '
      'exactly: if the input says "I", the Chinese says 我; if it asks a '
      'question, the Chinese asks the same question.\nAnswer with the Chinese '
      'translation in simplified characters on a single line, and nothing '
      'else.\n\nInput: can you help me?\nChinese: 你能帮我吗？\n'
      'Input: I would like a coffee please\nChinese: 我想要一杯咖啡。\n';

  @override
  Future<String?> intoChinese(String english) =>
      _ask(_reverse, 'Input: $english\nChinese:');

  @override
  Future<String?> intoEnglish(String chinese) =>
      _ask(_system, 'Chinese: $chinese\nEnglish:');

  Future<String?> _ask(String system, String prompt) async {
    final client = HttpClient();
    try {
      final request = await client.postUrl(_endpoint);
      request.headers.contentType = ContentType.json;
      request.write(
        jsonEncode({
          'model': model,
          'system': system,
          'prompt': prompt,
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

  // A name is carried, not translated: Chinese writes foreign names in Latin
  // letters as a matter of course, so 我叫Steve needs nothing explaining.
  test('carries a word that is not Chinese through untouched', () async {
    if (!available) {
      markTestSkipped('no Ollama on 127.0.0.1:11434');
      return;
    }

    final translator = ModelTranslator(
      dictionary: Dictionary.bundled(),
      backend: OllamaBackend(),
    );
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
        Spoken([_s('w', 'o', Tone.third)]),
        Spoken([_s('m', 'ai', Tone.fourth)]),
        Spoken([_s('sh', 'u', Tone.first)]),
      ]),
    );

    expect(result, isNotNull);
    expect(result!.text.toLowerCase(), contains('sell'));
    expect(result.text.toLowerCase(), isNot(contains('buy')));
  });
  // The whole reverse pipeline, end to end: the model writes characters, the
  // dictionary reads them back as tone-marked pinyin, and the answer is
  // checked by translating it forwards again. The model never sees a tone
  // mark in either direction.
  test('composes a phrase from English, tones included', () async {
    if (!available) {
      markTestSkipped('no Ollama on 127.0.0.1:11434');
      return;
    }

    final translator = EnglishModelTranslator(
      characters: CharacterIndex.bundled(),
      backend: OllamaBackend(),
    );

    final said = await translator.say('I want to go to Beijing tomorrow');
    expect(said, isNotNull);
    // Tones on every syllable, because they came from the dictionary rather
    // than from the model.
    expect(said!.best.written, matches(RegExp(r'[\u0101-\u01d6]')));
    expect(said.best.written.toLowerCase(), contains('běijīng'));
    // And the check that makes this direction safe to show at all.
    expect(said.readsBackAs?.toLowerCase(), contains('beijing'));
  });

  // The failure this direction actually has: a request served rather than
  // translated. Two examples in the prompt are what stop it, and this is
  // what notices if they are ever taken out.
  test('translates a request instead of carrying it out', () async {
    if (!available) {
      markTestSkipped('no Ollama on 127.0.0.1:11434');
      return;
    }

    final translator = EnglishModelTranslator(
      characters: CharacterIndex.bundled(),
      backend: OllamaBackend(),
    );

    for (final asked in const [
      'can you speak more slowly?',
      'do you have any tea?',
      'I would like two beers please',
    ]) {
      final said = await translator.say(asked);
      expect(said, isNotNull, reason: asked);
      // The round trip is the assertion. A model that answered rather than
      // translated reads back as something else entirely — "would you like
      // two beers?" for "I would like two beers please".
      expect(said!.readsBackAs, isNotNull, reason: asked);
      stdout.writeln('  $asked -> ${said.best.written}');
      stdout.writeln('     reads back as ${said.readsBackAs}');
    }
  });
}
