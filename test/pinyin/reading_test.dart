import 'package:flutter_test/flutter_test.dart';
import 'package:kouyu/pinyin/inventory.dart';
import 'package:kouyu/pinyin/reading.dart';
import 'package:kouyu/pinyin/syllable.dart';
import 'package:kouyu/pinyin/tone.dart';

void main() {
  test('reads a key back into the syllable that wrote it', () {
    // Every syllable this app can build, round-tripped through its own key.
    // This is the only thing that proves the two directions agree, and a
    // disagreement would be silent: the dictionary lookup would still work
    // and the answer would come back spelled wrong.
    for (final initial in syllableInventory.keys) {
      for (final rime in syllableInventory[initial]!) {
        for (final tone in Tone.values) {
          final syllable = Syllable(initial: initial, rime: rime, tone: tone);
          expect(
            syllableFor(syllable.numbered),
            syllable,
            reason: '${syllable.numbered} should read back as $syllable',
          );
        }
      }
    }
  });

  test('every syllable in the inventory spells differently', () {
    // What makes the round trip above possible at all. Two initial-and-rime
    // pairs spelling the same letters would make reading a key a guess, so a
    // rime added to the inventory has to keep this true.
    final spellings = <String>{};
    for (final initial in syllableInventory.keys) {
      for (final rime in syllableInventory[initial]!) {
        final letters = Syllable(
          initial: initial,
          rime: rime,
          tone: Tone.first,
        ).letters;
        expect(
          spellings.add(letters),
          isTrue,
          reason: '$initial + $rime spells $letters, which is already taken',
        );
      }
    }
    expect(spellings, hasLength(403));
  });

  test('reads the awkward spellings, not just the regular ones', () {
    // The three kinds pinyin respells, which a naive split on letters gets
    // wrong: a zero initial written with w or y, ü written u after j/q/x, and
    // ü written u: in a key.
    expect(syllableFor('wo3'), const Syllable(rime: 'uo', tone: Tone.third));
    expect(syllableFor('you2'), const Syllable(rime: 'iu', tone: Tone.second));
    expect(
      syllableFor('ju4'),
      const Syllable(initial: 'j', rime: 'ü', tone: Tone.fourth),
    );
    expect(
      syllableFor('nu:3'),
      const Syllable(initial: 'n', rime: 'ü', tone: Tone.third),
    );
  });

  test('reads a whole key as words', () {
    final syllables = syllablesFor('ni3 hao3');
    expect(syllables, hasLength(2));
    expect(syllables!.map((s) => s.written).join(), 'nǐhǎo');
  });

  test('declines what the keyboard does not build', () {
    // The erhua suffix, which 359 dictionary entries are keyed on, and the
    // interjections the inventory leaves out on purpose. Declining is the
    // point: half a line of pinyin is worse than none.
    expect(syllableFor('r5'), isNull);
    expect(syllableFor('ng2'), isNull);
    expect(syllableFor('hm5'), isNull);
    expect(syllablesFor('ming2 r5 ge5'), isNull);
  });

  test('declines what is not a key at all', () {
    expect(syllableFor(''), isNull);
    expect(syllableFor('ni'), isNull);
    expect(syllableFor('ni6'), isNull);
    expect(syllablesFor(''), isNull);
  });
}
