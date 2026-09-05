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
  They are laid out as a plus, each in the direction its pitch moves: rising
  above, falling below, the dipping third tone in the middle, the level first
  to the left, the unstressed neutral to the right. Reaching for "the falling
  one" means reaching down, rather than counting to the fourth of five.
- **Grouped by vowel.** The rimes come in a line per starting vowel —
  `a ai ao an ang`, then `ou ong`, then `e ei en eng` — so the bank is scanned
  rather than searched.
- **A caret marks where you are.** A trailing space renders as nothing, so
  pressing space and then starting the next syllable looks identical to
  forgetting to press it — and `wǒài` is not `wǒ ài`. A blinking caret sits at
  the end of the text with the pending space drawn in front of it.

### Two arrangements of the initial bank

The keyboard icon in the app bar switches between them, so they can be compared
by feel — which is the only way to choose.

**Articulation order** groups the initials by where in the mouth they are made,
which is how pinyin is taught: `b p m f`, `d t n l`, `g k h`, `j q x`,
`zh ch sh r`, `z c s`. It keeps the confusable sets adjacent, which matters for
an app about pronunciation. Seven rows of three or four, so the keys are wide
(64pt on a 375pt phone) but the bank is tall and most of each row is empty.

**QWERTY order** — the default — puts each initial in its familiar place, with
every digraph immediately after the letter it extends: `s sh`, `z zh`, `c ch`.
`u`, `i` and `v` drop out, since pinyin never starts a syllable with them, so
the rows come out 8/10/8.

It is QWERTY-*ordered* rather than QWERTY-*positioned*: inserting the digraphs
inline pushes everything after them out of its true column, so `d` no longer
sits under QWERTY's `d`. That is a deliberate trade — a digraph where a hand
reaches for its base letter is worth more on a 26-key thumb layout than exact
columns, which only pay off for ten-finger touch typing. Reading order within
each row is still QWERTY's.

Only the initial bank varies. The rime bank cannot follow: its keys are `iang`,
`ueng`, `üe` — units with no position on a Latin keyboard.

Articulation order needs seven shorter rows, which is about 400pt of height. A
landscape phone leaves 319 below the app bar, so it scrolls there; QWERTY's
three rows fit. That is part of why QWERTY is the default.

### How the screen divides

**Portrait**: the keyboard is full width, anchored to the bottom edge, and only
as tall as the stage on show needs — the initial bank is three rows, the tone
grid is a plus. Everything left over goes to what has been typed.

Sizing it to content is safe *because* it is anchored to the far edge. When the
reading area was the one sized to content, text appearing in it shoved the whole
keyboard up by 44pt mid-word; now the reading area takes what is left, so typing
cannot move a key.

**Landscape**: a full-height panel down the right, controls included, with the
reading area beside it.

A quarter of the width was the aim, but a ten-column row in 25% of a landscape
phone gives 13pt keys, which is not a keyboard. The panel takes the wider of
25% and what the widest bank actually needs — about 44% on a 812pt screen —
capped at half. It is sized from the widest arrangement rather than the one on
show, so switching arrangement never shifts everything in the panel.

### Starting a syllable that has no consonant

`ài`, `wǒ` and `yī` all begin without an initial consonant, which pinyin charts
treat as a single "zero initial" category. That is the wrong unit for a learner,
who knows only that the word starts with an a, a w or a y.

So there is a key for each: `y`, `w`, `a`, `o` and `e`. The first two spell
themselves; the three vowels are only a way in, so under `a` the keys read `a`,
`ai`, `ao`, `an`, `ang` — the whole syllable, since nothing precedes it. This is
also what makes the QWERTY arrangement work, because `a`, `o` and `e` fill three
of the gaps the vowels would otherwise leave.

Choosing the tone is also what commits the syllable, because every Mandarin
syllable has exactly one — there's deliberately no way to enter one without
deciding its tone. Tone marks land where pinyin's rules say (`niú`, not `níu`),
and the spelling irregularities are handled for you.

> **Status: early.** The input method works and is tested, and word meanings
> come from CC-CEDICT. Sentence translation does not exist yet — see
> [Translation](#translation).

## Requirements

- Flutter 3.47 or newer (Dart SDK `^3.13.2`)
- Platform toolchains for whichever targets you build: Xcode + CocoaPods for
  iOS, the Android SDK command-line tools for Android, Chrome for web
- [ImageMagick](https://imagemagick.org) 7, only if you need to regenerate the
  app icon
- A network connection, only if you need to regenerate the dictionary

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
| `lib/translation/`       | The `Translator` seam, the CC-CEDICT lookup, and a small phrasebook |
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

Everything that translates Chinese — dictionaries, translation services,
language models — works on characters. Pinyin on its own does not identify a
word, so the pipeline is not `pinyin → English` but **`pinyin → word →
English`**, and that middle step is the hard part whichever route you take. A
pinyin-keyed dictionary is not an alternative to a translation service; it is
the thing that lets you call one.

### How ambiguous is pinyin, exactly

Measured over the 115,304 entries shipped here, counting *distinct words*
rather than entries — CC-CEDICT splits some words' senses across several
entries, so counting rows overstates the ambiguity and understates how often
a key resolves cleanly:

| key | keys | resolve to one word | words per key | has a frequency rank |
| --- | ---- | ------------------- | ------------- | -------------------- |
| 1 syllable | 1,314 | 17.4% | 7.7 | 86.8% |
| 2 syllables | 52,324 | 91.3% | 1.1 | 16.5% |
| 3 or more | 46,491 | 99.4% | 1.0 | 2.4% |

So a dictionary is reliable for words and set phrases, and cannot be for lone
syllables — `shì` matches forty words. Two things make that workable: ambiguous
answers are labelled "several words sound like this" rather than presented as
fact, and candidates are ordered by frequency, which exists for 87% of exactly
the one-syllable keys that need it.

### What is here

[`translator.dart`](lib/translation/translator.dart) is the seam, and
`CompositeTranslator` asks each translator in turn:

1. [`PhrasebookTranslator`](lib/translation/phrasebook_translator.dart) — a
   short hand-written list of whole utterances. `wǒ ài nǐ` is three ordinary
   words, so no dictionary has an entry for it and glossing gives "I; me · to
   love · you". Deliberately tiny; anything that belongs in a dictionary goes
   in the dictionary.
2. [`DictionaryTranslator`](lib/translation/dictionary_translator.dart) — the
   whole input as one entry first, since a set phrase is one word whether or
   not it was spaced, then word by word.

A `Translator` receives the **syllables**, not a string. Every backend keys on
something derived from them, and the app already knows what it built: splitting
written pinyin into syllables is genuinely ambiguous (`wanan` splits two ways),
while `Syllable.numbered` hands over `wan3 an1` for free.

### The dictionary

CC-CEDICT, 115,304 entries over 23 shards by first letter, about 7.5MB. Shards
are parsed on demand and kept, so a lookup touches one file of at most 650KB
rather than holding the lot in memory.

Regenerate with:

```bash
dart run tool/build_dictionary.dart
```

The build drops what this app cannot use: 758 entries keyed on something the
keyboard cannot type, and 8,923 left with no usable gloss once pure
cross-references are removed. Characters are kept in the data even though
nothing displays them, because they are the bridge to any translation service
worth calling.

### When it loads

Nothing at startup. Shards are read on the first lookup that needs one, so the
dictionary cannot slow a cold start — there are tests on both halves of that.

Measured against the real assets, from local files:

| | |
| --- | --- |
| Largest shard cold (`s`, 650KB) | ~25ms |
| All 22 shards | ~110ms |
| Repeat lookup in a loaded shard | 0.4ms |

Which is why there is no spinner: at 25ms it would be motion for its own sake,
and an indeterminate one never stops animating. The screen instead says
"looking it up…" if a lookup passes 250ms, chosen to be longer than one ever
takes locally so it only appears in the case it is for — the web, where a shard
is an HTTP fetch with no upper bound.

Caching is handled at every level that matters, and none of it is the app's
job. Parsed shards are kept for the session. On a device the shards are files
inside the bundle, so there is nothing to download and only the parse remains.
On the web the browser caches the fetch.

Startup cost, incidentally, is Flutter's own: about 2.1MB of `main.dart.js` plus
several MB of CanvasKit before the first frame, which dwarfs any shard.

### Serving the web build

`flutter run -d web-server` sends no `cache-control`, no `etag`, and no
compression even when the client offers gzip, so local testing is the worst case
by a wide margin. Configure the real host to compress and cache
`assets/assets/dictionary/`; the shards are tab-separated text and more than
halve:

| | uncompressed | gzipped |
| --- | --- | --- |
| Largest shard | 650KB | ~265KB |
| All shards | 7.5MB | ~3.1MB |

### Ordering the candidates

CC-CEDICT carries no frequency data, so on its own it cannot tell 是 from 世 and
listed the forty words for `shì` in whatever order they happened to sort.
Frequency ranks and HSK bands come from
[complete-hsk-vocabulary](https://github.com/drkameleon/complete-hsk-vocabulary)
(MIT), joined on the word *and its reading*.

Both halves of that join are needed:

- **Word and reading**, not the word alone: 解 is common as `jiě` and rare as
  `xiè`, and crediting the second reading with the first's rank is how
  "acrobatic display" came to outrank "to thank".
- **Character within a word**: 谢 is not HSK vocabulary on its own, but 谢谢 is
  and is common, so a character earns a rank from the commonest word containing
  it *in the same reading*.

CC-CEDICT writes ü as `u:` where the HSK data writes `ü`; without normalising,
the join silently misses every ü word.

What it fixed, each a word from a first lesson:

| typing | before | after |
| ------ | ------ | ----- |
| `nǐ` | 拟 "doubtful" | 你 "you" |
| `shì` | 世 "life" | 是 "to be" |
| `yǒu` | 卣 "wine container" | 有 "to have" |
| `xiè` | 亵 "obscene" | 谢 "to thank" |
| `ài` | 僾 "indistinct" | 爱 "affection" |

A gloss-count heuristic was tried first and measured worse than no ordering at
all: it surfaced 势 for `shì` and 黝 for `yǒu`.

Where a word is in the HSK syllabus its band is shown, so a learner can see
whether what they typed is core vocabulary.

### The glosses themselves

CC-CEDICT glosses often point at other entries: 你 is glossed "you (informal, as
opposed to courteous 您[nin2])". The first build dropped any gloss containing a
character, on the grounds that this app does not show characters — **which threw
away 你, the commonest word for "you", altogether.**

Now a bracketed aside containing a reference is removed whole, leaving "you".
Stripping only the characters left subjectless prose, and a gloss left dangling
on "variant of" or "(from)" is dropped instead. That recovers about 9,400
glosses and 6,900 entries.

### Licence

CC-CEDICT is published by MDBG under
[CC BY-SA 4.0](https://creativecommons.org/licenses/by-sa/4.0/); the frequency
and HSK data is MIT licensed, copyright Yanis Zafirópulos. The generated assets
carry both notices — see `assets/dictionary/LICENCE` — and the app credits them
under the ⓘ button in the app bar.

Regenerating needs both sources. `tool/build_dictionary.dart` fetches them
unless given `--input` and `--hsk`.

### What is not here

Sentence translation. A dictionary resolves words and set phrases; grammar and
anything idiomatic that is not itself an entry is beyond it. Two routes, both
of which plug in as another `Translator` at the end of the chain and both of
which want the characters the dictionary now resolves:

- **A translation service.** Needs a network, an API key that cannot live in a
  client, and therefore a proxy — real infrastructure for a learner who is
  often offline.
- **An on-device model.** The appealing one, and currently the least reliable:
  small models are weak at Chinese and pinyin-only Chinese is outside anything
  they were trained on, so they will produce fluent nonsense with confidence.
  The platform models — Apple's Foundation Models, Gemini Nano — are stronger
  and free of bundle cost, but availability varies and the pinyin problem
  remains. Feeding either the resolved characters instead of the pinyin is what
  makes it tractable.

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
