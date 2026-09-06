import 'package:flutter_test/flutter_test.dart';
import 'package:kouyu/pinyin/composition.dart';
import 'package:kouyu/pinyin/keyboard_layout.dart';
import 'package:kouyu/pinyin/syllable.dart';
import 'package:kouyu/pinyin/tone.dart';
import 'package:kouyu/translation/dictionary.dart';
import 'package:kouyu/translation/tone_suggestion.dart';
import 'package:kouyu/translation/translator.dart';

InitialKey _key(String label) =>
    initialKeys.firstWhere((key) => key.label == label);

Syllable _s(String initial, String rime, Tone tone) =>
    Syllable(initial: initial, rime: rime, tone: tone);

/// `nǐ` and `hǎo`, plus the words the wrong tones would land on.
Dictionary _dictionary() => Dictionary(
  loadShard: (letter) async => switch (letter) {
    'n' =>
      'ni3\t你\t-\t5\t1\tyou\n'
          'ni2\t呢\t-\t96\t1\t(particle)\n'
          'ni3 hao3\t你好\t-\t300\t1\thello\n',
    'h' => 'hao3\t好\t-\t20\t1\tgood\n',
    'x' =>
      'xie4 xie5\t谢谢\t-\t520\t1\tto thank\n'
          'xie4 xie4\t泄泻\t-\t-\t-\t(TCM) to have diarrhea\n',
    's' => 'shi2\t时\t-\t115\t1\ttime\n',
    _ => throw AssertionError('no shard $letter'),
  },
);

void main() {
  late Suggester suggester;

  setUp(() => suggester = DictionarySuggester(_dictionary()));

  TranslationRequest request(List<List<Syllable>> words) =>
      TranslationRequest(words);

  // What was typed is not a word at all, and the same letters with another
  // tone are. No judgement involved.
  test('offers the word when the tone makes nothing', () async {
    final found = await suggester.check(
      request([
        [_s('n', 'i', Tone.third), _s('h', 'ao', Tone.first)],
      ]),
    );

    expect(found, isNotNull);
    expect(found!.written, 'nǐhǎo');
    expect(found.gloss, 'hello');
    expect(found.syllable, 1);
    expect(found.tone, Tone.third);
  });

  // 泄泻 is a real word, so an unknown-word rule alone would say nothing. It
  // is also in no syllabus, while 谢谢 is one of the first words anyone learns.
  test('offers a common word over an unranked one', () async {
    final found = await suggester.check(
      request([
        [_s('x', 'ie', Tone.fourth), _s('x', 'ie', Tone.fourth)],
      ]),
    );

    expect(found?.written, 'xièxie');
    expect(found?.tone, Tone.neutral);
  });

  group('stays quiet', () {
    test('on a word that is right', () async {
      expect(
        await suggester.check(
          request([
            [_s('n', 'i', Tone.third), _s('h', 'ao', Tone.third)],
          ]),
        ),
        isNull,
      );
    });

    // 呢 is rank 96 and 你 is rank 5, so a frequency-ratio rule would correct
    // a perfectly good particle. Being a ranked word at all is enough.
    test('on a common word with a much commoner neighbour', () async {
      expect(
        await suggester.check(
          request([
            [_s('n', 'i', Tone.second)],
          ]),
        ),
        isNull,
      );
    });

    test('on a single obscure syllable, which may be deliberate', () async {
      // shi2 is ranked here, but the rule also refuses to look at
      // single-syllable words that resolve at all.
      expect(
        await suggester.check(
          request([
            [_s('sh', 'i', Tone.second)],
          ]),
        ),
        isNull,
      );
    });

    test('when nothing is typed', () async {
      expect(await suggester.check(request([[]])), isNull);
    });
  });

  test('accepting one changes the tone and nothing else', () {
    var composition = const Composition();
    composition = composition
        .withInitial(_key('n'))
        .withRime('i')
        .commit(Tone.third);
    composition = composition
        .withInitial(_key('h'))
        .withRime('ao')
        .commit(Tone.first);
    expect(composition.text, 'nǐhāo');

    final fixed = composition.retoned(0, 1, Tone.third);
    expect(fixed.text, 'nǐhǎo');
    expect(fixed.caret, composition.caret, reason: 'the caret stays put');
  });

  test('a change outside the line is refused', () {
    final composition = const Composition()
        .withInitial(_key('n'))
        .withRime('i')
        .commit(Tone.third);
    expect(composition.retoned(9, 0, Tone.first), same(composition));
    expect(composition.retoned(0, 9, Tone.first), same(composition));
  });
}
