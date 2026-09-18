import 'package:flutter_test/flutter_test.dart';
import 'package:kouyu/audio/mandarin_speech.dart';
import 'package:kouyu/pinyin/syllable.dart';
import 'package:kouyu/pinyin/word.dart';
import 'package:kouyu/pinyin/tone.dart';
import 'package:kouyu/translation/dictionary.dart';
import 'package:kouyu/translation/translator.dart';

/// Records what the platform was asked to do, so the tests can assert on the
/// characters handed over rather than on anything a voice does with them.
class _FakeTts implements VoiceEngine {
  final List<String> spoken = [];
  final List<String> languages = [];
  double? rate;
  int stops = 0;
  bool hasMandarin = true;

  @override
  Future<bool> hasLanguage(String language) async =>
      language == 'zh-CN' && hasMandarin;

  @override
  Future<void> configure(String language, double value) async {
    languages.add(language);
    rate = value;
  }

  @override
  Future<void> say(String text) async => spoken.add(text);

  @override
  Future<void> hush() async => stops++;
}

Syllable _s(String initial, String rime, Tone tone) =>
    Syllable(initial: initial, rime: rime, tone: tone);

void main() {
  late _FakeTts engine;
  late MandarinSpeech speech;

  setUp(() {
    engine = _FakeTts();
    speech = MandarinSpeech(
      Dictionary(
        loadShard: (letter) async => switch (letter) {
          'w' => 'wo3\t我\t-\t3\t1\tI; me\n',
          'm' =>
            'mai3\t买\t-\t500\t1\tto buy\n'
                'mai4\t卖\t-\t600\t1\tto sell\n',
          's' => 'shu1\t书\t-\t560\t1\tbook\n',
          _ => throw AssertionError('no shard $letter'),
        },
      ),
      engine: engine,
    );
  });

  TranslationRequest request(List<Word> words) => TranslationRequest(words);

  test('speaks the characters, not the pinyin', () async {
    final said = await speech.speak(
      request([
        Spoken([_s('w', 'o', Tone.third)]),
        Spoken([_s('m', 'ai', Tone.fourth)]),
        Spoken([_s('sh', 'u', Tone.first)]),
      ]),
    );

    expect(said, isTrue);
    // A Chinese voice handed "wǒ mài shū" says nothing useful.
    expect(engine.spoken, ['我卖书']);
    expect(engine.languages, ['zh-CN']);
  });

  // The tone the learner chose has to survive into the audio, or the app is
  // teaching the wrong word out loud.
  test('the tone decides what is said', () async {
    await speech.speak(
      request([
        Spoken([_s('w', 'o', Tone.third)]),
        Spoken([_s('m', 'ai', Tone.third)]),
      ]),
    );
    await speech.speak(
      request([
        Spoken([_s('w', 'o', Tone.third)]),
        Spoken([_s('m', 'ai', Tone.fourth)]),
      ]),
    );

    expect(engine.spoken, ['我买', '我卖']);
  });

  // A voice gets the name as written, which is what it would get from any
  // other Chinese sentence containing one.
  test('a name is spoken as written', () async {
    final said = await speech.speak(
      request([
        Spoken([_s('w', 'o', Tone.third)]),
        const Literal('Steve'),
      ]),
    );

    expect(said, isTrue);
    expect(engine.spoken, ['我Steve']);
  });

  test('is slowed down, so the tones can be heard', () async {
    await speech.speak(
      request([
        Spoken([_s('w', 'o', Tone.third)]),
      ]),
    );
    expect(engine.rate, lessThan(0.5));
  });

  // All or nothing, as with translation: dropping an unknown word would say a
  // sentence the learner did not write.
  test('says nothing when a word cannot be placed', () async {
    final said = await speech.speak(
      request([
        Spoken([_s('w', 'o', Tone.third)]),
        Spoken([
          _s('m', 'ai', Tone.second),
        ]), // mai2, absent from the stand-in shard
      ]),
    );

    expect(said, isFalse);
    expect(engine.spoken, isEmpty);
  });

  test('says nothing, and reports it, without a Mandarin voice', () async {
    engine.hasMandarin = false;
    expect(await speech.available(), isFalse);
    expect(
      await speech.speak(
        request([
          Spoken([_s('w', 'o', Tone.third)]),
        ]),
      ),
      isFalse,
    );
    expect(engine.spoken, isEmpty);
  });

  test('configures the voice once, not per phrase', () async {
    for (var i = 0; i < 3; i++) {
      await speech.speak(
        request([
          Spoken([_s('w', 'o', Tone.third)]),
        ]),
      );
    }
    expect(engine.languages, ['zh-CN']);
    expect(engine.spoken.length, 3);
  });

  test('stopping is safe when nothing is playing', () async {
    await speech.stop();
    expect(engine.stops, 1);
  });
}
