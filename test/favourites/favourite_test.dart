import 'package:flutter_test/flutter_test.dart';
import 'package:kouyu/favourites/favourite.dart';
import 'package:kouyu/pinyin/syllable.dart';
import 'package:kouyu/pinyin/tone.dart';
import 'package:kouyu/pinyin/word.dart';

final _ni = Spoken([const Syllable(initial: 'n', rime: 'i', tone: Tone.third)]);
final _hao = Spoken([
  const Syllable(initial: 'h', rime: 'ao', tone: Tone.third),
]);

void main() {
  final saved = DateTime.utc(2026, 9, 27, 10, 30);

  test('reads back exactly what it wrote', () {
    // The awkward spellings as well as the regular ones: a zero initial, ü
    // written u: in a key, a neutral tone, a word of two syllables, and a
    // name. Any of them misread would open as a different line.
    final favourite = Favourite(
      words: [
        Spoken([const Syllable(rime: 'uo', tone: Tone.third)]),
        Spoken([
          const Syllable(initial: 'x', rime: 'ie', tone: Tone.fourth),
          const Syllable(initial: 'x', rime: 'ie', tone: Tone.neutral),
        ]),
        Spoken([const Syllable(initial: 'n', rime: 'ü', tone: Tone.third)]),
        const Literal('Steve'),
      ],
      meaning: 'thanks, Steve',
      saved: saved,
    );

    expect(Favourite.fromJson(favourite.toJson()), favourite);
    expect(favourite.pinyin, 'wǒ xièxie nǚ Steve');
  });

  test('keeps the syllables, not the text on screen', () {
    // The text could not be split back — `wanan` is two words — so what is
    // stored is each syllable's dictionary key.
    final json = Favourite(words: [_ni, _hao], saved: saved).toJson();
    expect(json['words'], [
      {
        's': ['ni3'],
      },
      {
        's': ['hao3'],
      },
    ]);
  });

  test('has no meaning where none was showing', () {
    final favourite = Favourite(words: [_ni], saved: saved);
    expect(Favourite.fromJson(favourite.toJson())!.meaning, isNull);
  });

  test('is the favourite for the same line, and no other', () {
    final favourite = Favourite(words: [_ni, _hao], saved: saved);
    expect(favourite.isFor([_ni, _hao]), isTrue);
    // A composition carries an empty word after a trailing space. It is not
    // part of what was typed and must not stop the line matching.
    expect(favourite.isFor([_ni, _hao, const Spoken()]), isTrue);
    // Different word breaks are a different line, and so is a different tone.
    expect(
      favourite.isFor([
        Spoken([..._ni.syllables, ..._hao.syllables]),
      ]),
      isFalse,
    );
    expect(
      favourite.isFor([
        Spoken([const Syllable(initial: 'n', rime: 'i', tone: Tone.second)]),
        _hao,
      ]),
      isFalse,
    );
  });

  test('declines a row it cannot read, rather than half of one', () {
    for (final bad in <Object?>[
      null,
      'nǐ hǎo',
      {'words': [], 'saved': saved.toIso8601String()},
      {
        'words': [
          {
            's': ['ni3'],
          },
        ],
      },
      {
        // The erhua suffix, which this keyboard does not build.
        'words': [
          {
            's': ['ming2', 'r5'],
          },
        ],
        'saved': saved.toIso8601String(),
      },
      {
        'words': [
          {'x': 1},
        ],
        'saved': saved.toIso8601String(),
      },
    ]) {
      expect(Favourite.fromJson(bad), isNull, reason: '$bad');
    }
  });
}
