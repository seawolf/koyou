import 'package:flutter_test/flutter_test.dart';
import 'package:kouyu/pinyin/composition.dart';
import 'package:kouyu/pinyin/word.dart';
import 'package:kouyu/pinyin/written.dart';

void main() {
  /// [text] read and written back out, or null where it is refused.
  String? roundTrip(String text) {
    final words = readWritten(text);
    return words == null ? null : Composition.of(words).text;
  }

  /// How [text] was split, syllable by syllable, word by word.
  List<List<String>> split(String text) => [
    for (final word in readWritten(text)!)
      switch (word) {
        Spoken(:final syllables) => [for (final s in syllables) s.written],
        Literal(:final text) => ['literal:$text'],
      },
  ];

  test('reads tone-marked pinyin', () {
    expect(roundTrip('nǐ hǎo'), 'nǐ hǎo');
    expect(split('nǐhǎo'), [
      ['nǐ', 'hǎo'],
    ]);
  });

  // The same rule pinyin is written by: a vowel-initial syllable follows
  // another only after an apostrophe.
  test('splits as pinyin spells itself to be read', () {
    expect(split('fāngàn'), [
      ['fān', 'gàn'],
    ]);
    expect(split("fāng'àn"), [
      ['fāng', 'àn'],
    ]);
    expect(split('xiān'), [
      ['xiān'],
    ]);
    expect(split("xī'ān"), [
      ['xī', 'ān'],
    ]);
    expect(split('zhōngguó'), [
      ['zhōng', 'guó'],
    ]);
  });

  test('never puts two tone marks in one syllable', () {
    // Longest first would take `xian`, which carries both marks.
    expect(split('xīān'), [
      ['xī', 'ān'],
    ]);
  });

  test('takes an unmarked syllable beside marked ones as neutral', () {
    expect(split('nǐmen'), [
      ['nǐ', 'men'],
    ]);
    expect(roundTrip('hǎo ma'), 'hǎo ma');
  });

  test('reads tone numbers, and v and u: for ü', () {
    expect(roundTrip('ni3 hao3'), 'nǐ hǎo');
    expect(roundTrip('ni3hao3'), 'nǐhǎo');
    expect(roundTrip('lv4'), 'lǜ');
    expect(roundTrip('nu:3'), 'nǚ');
  });

  test('reads tone marks that arrive decomposed', () {
    expect(roundTrip('nǐ hǎo'), 'nǐ hǎo');
    expect(roundTrip('lǜ'), 'lǜ');
  });

  test('drops punctuation and ignores case', () {
    expect(roundTrip('Nǐ hǎo, shìjiè!'), 'nǐ hǎo shìjiè');
    expect(roundTrip('“Xièxie。”'), 'xièxie');
  });

  // What the app's own Copy puts out has to come back in.
  test('keeps a name as a name', () {
    expect(split('wǒ jiào Steve'), [
      ['wǒ'],
      ['jiào'],
      ['literal:Steve'],
    ]);
    expect(split('wǒ jiào Anna'), [
      ['wǒ'],
      ['jiào'],
      ['literal:Anna'],
    ], reason: 'not an na, though it spells it');
  });

  // Without tones there is nothing to go on, and a guess would be presented
  // as an answer.
  test('refuses pinyin with no tones at all', () {
    expect(readWritten('ni hao'), isNull);
    expect(readWritten('nihao'), isNull);
  });

  test('refuses what is not pinyin', () {
    expect(readWritten('hello world'), isNull);
    expect(readWritten(''), isNull);
    expect(readWritten('你好'), isNull);
    expect(readWritten('3'), isNull);
  });

  test('refuses a tone that has nothing to sit on', () {
    expect(readWritten("ni3'3"), isNull);
    expect(split('nǐ3 hǎo'), [
      ['literal:nǐ3'],
      ['hǎo'],
    ]);
  });
}
