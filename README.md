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
- **A caret marks where you are, and can be moved.** A trailing space renders
  as nothing, so pressing space and then starting the next syllable looks
  identical to forgetting to press it — and `wǒài` is not `wǒ ài`. A blinking
  caret sits where the next syllable will go, with the space after a word break
  drawn explicitly.

  Tap a syllable to put the caret before it, or past its middle to put the
  caret after it, as in any other text field. Everything then happens there:
  typing inserts, backspace deletes what is behind the caret, and space breaks
  the word at that point. So a syllable four words back can be fixed without
  retyping everything after it.

  The caret moves between syllables, never inside one. A syllable is what the
  keyboard produces and what a learner says, so there is no useful position
  between a vowel and its own tone mark. Moving the caret also drops a
  half-typed syllable: it has no tone, so it is not a syllable yet, and
  carrying half of one to a new place in the line is stranger than losing it.

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
| `lib/audio/`             | The `Speech` seam and the platform voice behind it   |
| `web/kouyu_model.js`     | The browser side of the model tier; everything testable is in Dart |
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

The build refuses to write fewer than 50,000 entries. It deletes the existing
shards before writing, and a source that fetches but does not parse would
otherwise replace a working dictionary with a stub and report success — which
is exactly what happened when the download path was found to be splitting
CRLF-terminated CC-CEDICT lines on `\n`, leaving a `\r` that the entry pattern
could never match. `--input` never hit it, because `readAsLines` handles both.

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

#### Which reading earned the rank

Joining on the reading is necessary but not sufficient, because **the source
gives one `frequency` per word and lists every reading of that word beneath
it**. Credited to all of them, the commonest word in the language hands its
standing to its own rarest reading: 的 is rank 1 as `de5` and carried that into
`di4`, so typing `dì` was offered "bull's-eye; target". 94% of characters with
more than one reading shared a single rank this way.

Nothing in the data says which reading a frequency describes, so it is inferred
from two independent signals. A reading keeps the rank if **either** supports
it — they fail on different words, and admitting one reading too many costs far
less than stripping the right one:

- **The commonest HSK compound of two or more characters.** A single-character
  word may no longer credit itself, which is what spread the rank in the first
  place.
- **How many CC-CEDICT entries use the character in that reading.** Breadth
  rather than frequency, and it catches what the first signal cannot see: 喝 is
  common as `hē` but appears in compounds mostly as `hè`, so on the HSK signal
  alone "to drink" lost its rank to "to shout".

Neither signal can see a word that is common standing alone and absent from
compounds, which is every grammatical particle, so a **neutral tone on a single
character** vouches for itself — otherwise 的 and 了 hand their rank to a rare
reading that does appear in one.

A reading supported by neither falls back to its own compound evidence, and only
where it has none is the word's rank kept and heavily demoted, so it still
outranks a word carrying no rank at all.

The HSK band is attributed the same way, so "bull's-eye" is no longer labelled
HSK 1 either.

| typing | before | after |
| ------ | ------ | ----- |
| `dì` | 的 "bull's-eye; target" | 地 "earth" |
| `kuài` | 会 "to reckon accounts" | 快 "rapid" |
| `shuì` | 说 "to persuade" | 睡 "to sleep" |
| `bà` | 把 "handle" | 爸 "father" |
| `dī` | 的 "a taxi" | 低 "low" |
| `là` | 落 "to leave out" | 辣 "hot (spicy)" |

This moves the top candidate for 79 of 100,129 keys, every one a single
syllable — which is where the ambiguity is. Characters sharing one rank across
every reading fall from 94% to 14%.

Each signal alone leaves regressions the other repairs, which is the whole
argument for taking both: on the HSK signal alone `hē` offered "to shout" and
`dū` offered 督, and on the CC-CEDICT signal alone `dōu` and `hái` lose their
adverb readings. Measure any change to this against
`test/translation/bundled_dictionary_test.dart`, which pins both kinds.

### The glosses themselves

CC-CEDICT glosses often point at other entries: 你 is glossed "you (informal, as
opposed to courteous 您[nin2])". The first build dropped any gloss containing a
character, on the grounds that this app does not show characters — **which threw
away 你, the commonest word for "you", altogether.**

Now a bracketed aside containing a reference is removed whole, leaving "you".
Stripping only the characters left subjectless prose, and a gloss left dangling
on "variant of" or "(from)" is dropped instead. That recovers about 9,400
glosses and 6,900 entries.

### Noticing a mistyped tone

Type `nǐ hāo` and the app offers `nǐhǎo` — 你好 — as a tap. Offered, never
applied: the learner may have meant the odd word, and silently retoning what
someone wrote in a language they are learning would be the rudest thing this
app could do. Accepting changes one tone and nothing else, so the letters and
the caret stay where they were.

**This is a dictionary question, not a model's.** It takes **0.16ms** once the
shard is loaded, 37ms cold, against the second or two a phone needs for one
model generation — and asking a model would mean a *second* generation on top
of the translation. It is also the least reliable thing to ask a small model:
it does not know which tone is right, it knows which sentence sounds likely,
and it will nag confidently about correct input. Frequency data is not an
opinion.

Two signals, both narrow enough to stay quiet on correct pinyin:

- **What was typed is not a word, and the same letters with another tone are.**
  Not a judgement at all. `nǐ hāo` is nothing; `nǐ hǎo` is 你好.
- **What was typed is a word, but one no syllabus contains, while a
  tone-neighbour is common.** `xiè xiè` is 泄泻, "(TCM) to have diarrhea" —
  a real entry, so the first signal says nothing — and `xiè xie` is 谢谢.

What it deliberately does **not** do is compare how common two words are. 呢 is
rank 96 and 你 is rank 5, so a ratio rule would "correct" a perfectly good
particle; 时 at 115 would be corrected to 是 at 4. Being a ranked word at all
is enough to be left alone, and single syllables are never questioned, because
an obscure one can be a deliberate pick from the candidate list.

Measured against the real data it fires on `nǐ hāo`, `zài jiān`, `shì jié`,
`lǎo shí` and `xiè xiè`, and stays silent on 你好, 世界, 朋友, 谢谢, 老师,
再见, 没关系, 我, 时, 妈, 呢 and 埋.

What it cannot catch is a wrong tone that still makes a sensible word in
context — `wǒ shí` where `wǒ shì` was meant. That needs to know what the
sentence is about, which is a model's job, and a job for a better model than
fits on a phone.

### Which tier answers

The dictionary answers every keystroke; the model is asked once typing pauses,
and **only about what the dictionary could not answer whole**. Where the
dictionary matched the entire line as one entry — a set phrase, an idiom, a
compound — that is the answer, and the model is not woken at all.

That last rule is not tidiness. The lookup key drops word breaks, so 缘分 is
found whether it was typed `yuánfèn` or `yuán fèn`. But the model is handed one
character per *word*, so the spaced spelling reached it as 元份 — not a word —
and its paraphrase, "A portion", displaced "fate or chance that brings people
together" which the dictionary already had. Spacing a compound is an easy thing
for a learner to get wrong, and now it costs nothing.

### Saying it aloud

The speaker in the app bar reads the line back, in Mandarin, on request. It
uses **the platform's own voice** — Android's TTS engine, iOS's
`AVSpeechSynthesizer`, or a browser's speech synthesis, through `flutter_tts`.

Not a model. Qwen3.5 emits text only, whatever it is fed; llama.cpp *can* run
OuteTTS with a WavTokenizer vocoder, and Chinese is one of its better
languages, but that is another gigabyte of weights plus a vocoder and audio
plumbing to get worse Mandarin than a phone gives away for nothing. The
platform voice also costs no bundle size, needs no download to manage, and is
the one tier that works on the web as well.

It runs on the same bridge as everything else: a Chinese voice handed
`wǒ mài shū` says nothing useful, so the dictionary resolves it to 我卖书
first. That makes audio the third use of `DictionaryEntry.simplified`, after
the dictionary's own lookups and the model's.

Audio is also **more robust than translation** to the one weakness of that
resolution. Where `qián` resolves to 前 and the learner meant 钱, the
translation is wrong but the sound is not: the key carries the tone, so every
word matching it is pronounced identically. A wrong character, read aloud, is
still the right syllable.

Two deliberate choices:

- **On request only.** Speaking as the line grows would read out a fragment of
  a sentence after every syllable — unusable, and the fastest way to make
  someone put the phone down. Any edit stops whatever is playing, because it
  was about the text as it was.
- **Slower than conversational**, because the point is to hear the tones.

Where the device has no Chinese voice the button is not there at all, rather
than present and silent. Where a word cannot be resolved, nothing is spoken and
the screen says why.

One thing to expect rather than fix: a native voice applies **tone sandhi** —
不 `bù` becomes `bú` before a fourth tone, 一 `yī` becomes `yì` — so the audio
will not always match the tone marks on screen. That is what a native speaker
says, which for a speaking app is the point.

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
- **An on-device model.** Measured rather than guessed at — see
  [docs/local-model.md](docs/local-model.md). Fed bare pinyin even a 27B model
  loses half of a set of tone minimal pairs, rendering `tā wěn wǒ` ("he kissed
  me") as "held my hand": fluent nonsense, confidently. But that is the wrong
  question to ask it. Let the dictionary resolve the pinyin to characters, which
  it does deterministically and tone-exactly, and the model has only to
  translate Chinese — at which point **0.8B is enough**, scoring 17 of 19
  learner sentences, identically across repeated runs, in under a tenth of a
  second. The dictionary is not replaced by a model; it is what makes one work
  at a size that fits a phone. The platform models — Apple's Foundation Models,
  Gemini Nano — are free of bundle cost, and the same split applies to them.

  Built, on Android and in the browser. `llama_cpp_dart` (MIT) bundles
  llama.cpp into the APK, and the weights are a resumable, digest-pinned
  first-run download managed from the ✨ button — they cannot ship inside the
  app, since Play caps the base download at 200MB. Switching the model off
  keeps the download and frees the memory. iOS needs a full Xcode install
  before it builds at all.

  The web build runs the **same** GGUF through the same prompt:
  [wllama](https://github.com/ngxson/wllama) is llama.cpp compiled to WASM with
  a WebGPU backend, and the weights sit in the origin's private file system. In
  a real browser the answers matched the native ones exactly, at about 300ms
  each. Staging it is one command:

  ```bash
  tool/fetch_wllama.sh
  ```

  Without that the web build still works — the model backend declines and the
  dictionary answers, which is the same thing that happens on a phone with no
  weights downloaded. WebGPU now ships in every major browser including mobile,
  so this is also the only way to get the model onto an iPhone until iOS can be
  built.

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
