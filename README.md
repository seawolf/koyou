# Kǒuyǔ

A Flutter app for Mandarin learners who want to **speak** — tones,
pronunciation, comprehension — rather than learn to read and write characters.

## The gap it fills

There is nowhere to simply type `nǐ hǎo, shìjiè`.

Dictionary apps accept pinyin, but a word at a time. Translation apps accept
phrases, but want Hanzi. And every phone keyboard treats pinyin as a route to
characters, converting it away at the first opportunity — so tone-marked pinyin,
the thing a speaking learner actually works in, is the one thing you can't
enter.

So the input method is the app. It asks for one piece of a syllable at a time —
a starting point, then what can follow it, then the tone — with the pieces
already chosen tucked to the left as a trail you can tap to go back.

Staging it buys three things a full keyboard can't:

- **Only real syllables.** Once you've picked a starting point, the app shows
  what legitimately follows it. Mandarin uses about 400 of the possible
  initial-by-rime combinations, so a full grid invites you to build `qong` or
  `zü`, which aren't words.
- **Spelled the way you'd write it.** `wǒ` is phonologically the rime `uo` with
  no initial at all, but nobody learning to speak thinks that way — they know
  it starts with a w. So `w` and `y` are offered as starting points, and under
  `w` the key says `o`, because the syllable is written `wo`.
- **Tones as words, not marks.** The last stage shows `nī ní nǐ nì ni` — a
  choice you can hear, rather than `ˉ ˊ ˇ ˋ ·`, a puzzle you have to decode.

Choosing the tone is also what commits the syllable, because every Mandarin
syllable has exactly one — there's deliberately no way to enter one without
deciding its tone. Tone marks land where pinyin's rules say (`niú`, not `níu`),
and the spelling irregularities are handled for you.

> **Status: early.** The input method works and is tested. Translation is a
> hand-written phrasebook standing in for a real model — see below.

## Requirements

- Flutter 3.47 or newer (Dart SDK `^3.13.2`)
- Platform toolchains for whichever targets you build: Xcode + CocoaPods for
  iOS, the Android SDK command-line tools for Android, Chrome for web
- [ImageMagick](https://imagemagick.org) 7, only if you need to regenerate the
  app icon

Run `flutter doctor` to check what your machine is missing.

## Getting started

```bash
flutter pub get
flutter run
```

`flutter run` picks a connected device; pass `-d chrome`, `-d ios`, or
`-d android` to choose one. To serve the web build without launching a browser:

```bash
flutter run -d web-server --web-port 5123
```

## Checks

These three are the gate — run them before every commit:

```bash
dart format --output=none --set-exit-if-changed .
flutter analyze
flutter test
```

## Layout

| Path                     | What lives there                                     |
| ------------------------ | ---------------------------------------------------- |
| `lib/main.dart`          | Entry point; nothing but `runApp`                    |
| `lib/app.dart`           | Root `MaterialApp` — routing and theme wiring        |
| `lib/theme.dart`         | Brand seed colour and the light/dark themes          |
| `lib/pinyin/`            | Pure Dart, no Flutter: the syllable inventory, tones, spelling, and the editing model |
| `lib/translation/`       | The `Translator` seam and its phrasebook stand-in    |
| `lib/screens/`           | One file per screen                                  |
| `lib/widgets/`           | Reusable widgets, e.g. the keyboard                  |
| `test/`                  | Mirrors `lib/` (`lib/screens/x.dart` → `test/screens/x_test.dart`) |
| `assets/icon/`           | Generated icon sources — see below                   |
| `tool/generate_icons.sh` | Regenerates the icon; the source of truth for it     |

`lib/pinyin/` deliberately imports no Flutter. The tone-placement and spelling
rules are the part most likely to be subtly wrong, so they are testable without
pumping a widget, and `Composition` holds every editing rule so the keyboard is
a view over it rather than a widget full of logic.

Within it, two files are worth knowing apart:

- [`inventory.dart`](lib/pinyin/inventory.dart) is the source of truth for what
  can be typed at all — which rimes each initial actually combines with, about
  400 syllables. To make a syllable reachable, add it here; the keyboard is
  derived and needs no edit.
- [`keyboard_layout.dart`](lib/pinyin/keyboard_layout.dart) turns that into what
  a learner would recognise: `w` and `y` as starting points, and rime keys
  labelled by spelling rather than phonology. It derives those labels through
  the same spelling rules the renderer uses, so the two can't drift apart.

## Translation

`lib/translation/translator.dart` is the seam a real model plugs into.

What ships today is [`PhrasebookTranslator`](lib/translation/phrasebook_translator.dart):
about 25 hand-written entries that match a whole phrase, fall back to glossing
word by word, and otherwise return nothing. It is not translation — it exists so
the compose-and-translate path runs end to end. The UI labels a word-by-word
gloss as such, because word-by-word Mandarin is often misleading.

The two layers are kept apart on purpose, since the UI is where the work is at
the moment: nothing under `lib/screens/` or `lib/widgets/` names a translation
implementation, only the `Translator` interface. `lib/app.dart` is the single
place one is chosen. Replacing the phrasebook means writing one `Translator` and
editing that one line.

Note that a `Translator` receives pinyin *with* tone marks, and must not
normalise them away — tones are what disambiguate.

## The app icon

The mark is 口 (_kǒu_, "mouth") with a calligraphic speech flick sweeping off
its bottom-left corner — mouth plus speech, for spoken language.

Two things keep the 口 reading as a Hanzi character rather than a chat bubble.
It is built from the character's three real strokes rather than as a rounded
rectangle, so it keeps the square corners, the slight inward taper of both
verticals, and the bottom stroke's overshoot past the right-hand vertical. And
the flick hangs below the bottom stroke instead of interrupting it — 口 has to
stay closed to still be 口, which is why a solid tail fused into the outline
doesn't work.

`tool/generate_icons.sh` holds the icon's geometry and emits everything else:
the SVG in `assets/icon/`, the master and Android-adaptive PNGs beside it, and
then the per-platform icons via
[`flutter_launcher_icons`](https://pub.dev/packages/flutter_launcher_icons).
Edit the geometry at the top of that script and re-run it — never edit the
generated files:

```bash
tool/generate_icons.sh
```

The brand colour lives in two places that must agree: `RED` in that script and
`kSeedColor` in [`lib/theme.dart`](lib/theme.dart).

## Platform identifiers

The bundle/application ID is `com.seawolfsanctuary.kouyu` on both iOS and
Android. The display name is `Kǒuyǔ`; the Dart package name is `kouyu`, since
package names must be ASCII.
