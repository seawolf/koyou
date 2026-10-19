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

  Tapping a syllable twice asks for its tone again, and holding one asks again
  for what follows the initial — the syllable comes out of the line and the
  caret takes its place, so the new one lands exactly where the old one was.
  Getting a tone wrong is the commonest slip there is, and backspacing a whole
  syllable to fix one mark was a poor trade.

  Both are handled by hand rather than with `onDoubleTap`, which would put
  every single tap behind the double-tap timeout — and placing the caret is the
  commonest thing anyone does here. The first tap moves the caret immediately;
  a second within 300ms supersedes it. Nothing is ever waited for.

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

[`english_translator.dart`](lib/translation/english_translator.dart) is the
matching seam for the other direction, with `CompositeEnglishTranslator` and
the same shape of chain — see [Starting from English](#starting-from-english).
It is deliberately a separate seam rather than a flag on the first: the two
share their data and nothing else, and they fail in different ways.

A `Translator` receives the **syllables**, not a string. Every backend keys on
something derived from them, and the app already knows what it built: splitting
written pinyin into syllables is genuinely ambiguous (`wanan` splits two ways),
while `Syllable.numbered` hands over `wan3 an1` for free.

### The dictionary

CC-CEDICT, 115,380 entries over 23 shards by first letter, about 7.5MB. Example
sentences come from Tatoeba through a second tool, run after this one because
it reads the character index to know which sentences can be shown as pinyin:

```bash
dart run tool/build_examples.dart
```

It keeps one sentence per word — 870KB for 11,270 words — preferring short ones
in syllabus vocabulary, and drops any that Tatoeba's own reviewers have flagged
for a native check or a change, along with quotations, idioms, and sentences
about Tatoeba itself. Shards
are parsed on demand and kept, so a lookup touches one file of at most 650KB
rather than holding the lot in memory.

The same source is written out three ways, because the app reads it in three
directions:

| | | |
| --- | --- | --- |
| `assets/dictionary/` | pinyin key → word and glosses | 7.5MB, 23 shards |
| `assets/dictionary/english/` | English headword → Chinese words | 3.7MB, 27 shards |
| `assets/dictionary/characters/` | characters → the pinyin they read as | 2.7MB, 110 shards |

All three are sharded and parsed on demand for the same reason, and all three
carry CC-CEDICT's licence.

Regenerate with:

```bash
dart run tool/build_dictionary.dart
```

The build drops what this app cannot use: 758 entries keyed on something the
keyboard cannot type, and 8,945 left with no usable gloss once pure
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

### Words that are not Chinese

`Wǒ jiào Steve` is a sentence a learner needs on day one, and no amount of
pinyin will spell a name. So a line can hold two kinds of word: `Spoken`, built
from syllables on the app's keyboard, and `Literal`, a run of letters carried
through as written.

Adding one is the single place this app hands over to the phone's own keyboard.
That is deliberate — the premise is that a phone IME fights you over *pinyin*,
but a name is arbitrary letters with capitals in it, which is exactly what a
phone keyboard is for. It sits beside the prompt, where the question "what
comes next" is already being asked, and only at the start of a syllable:
halfway through one is no place to put a name. Tapping a name already in the
line reopens the editor on it, so `Steve` can become `Stephen` without retyping
the sentence.

Downstream it needs almost nothing, which is the point:

- **The model** gets it verbatim. Chinese writes foreign names in Latin letters
  as a matter of course, so `我叫Steve` is ordinary text — measured, and it
  answers "My name is Steve." Nothing had to be explained to it.
- **The dictionary** skips it, and a line containing one can no longer be a
  single entry, so the whole-line lookup is not attempted at all.
- **The tone suggester** ignores it. There is no tone in `Steve` to have got
  wrong.
- **The voice** is handed it as written, the same as it would be in any other
  Chinese sentence with a name in it.

The caret treats a name as one indivisible unit: it goes either side of
`Steve`, never inside, and backspace takes the whole thing. A syllable typed
against one starts its own word rather than running into it.

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

### Starting from English

The compose screen answers "what does this pinyin mean". The **translate
screen** — "Translation into Mandarin Pinyin" — answers the other question,
and is reached by the `translate` icon in the app bar.

Nothing is looked up until it is asked for. A phone keyboard offers
corrections and completions while a sentence is half written, and translating
every intermediate state both fights that and wakes the model for a sentence
nobody has finished — a second of CPU and a sip of battery each time. So there
is a **Translate** button, the keyboard's Go key does the same, and editing the
box clears the answer rather than leaving one that belongs to different text.

It is a screen of its own rather than a mode on the first, and that is the
point: English is ordinary Latin text, so it wants a plain `TextField`, which
brings selection, copy and paste with it for nothing. The composed line cannot
offer those, because it is painted a syllable at a time so that it can be
tapped. Finding a middle ground between the two would have made both worse.

The same bridge, run backwards:

```
"I want to go to Beijing tomorrow"  →  明天我要去北京  →  míngtiān wǒ yào qù běijīng
                            the model                 the dictionary
```

**The model writes characters and never a tone mark.** Generating Chinese is
what it was trained for; the tones come from
[`CharacterIndex`](lib/translation/character_index.dart), deterministically, by
longest match. The word breaks come free with it — a model writes 明天我要去北京
with no spaces at all, and what comes back is five words a learner can edit one
at a time.

The tiers mirror the other direction, and for the same reasons:

1. [`EnglishPhrasebook`](lib/translation/phrasebook_translator.dart) — the same
   hand-written list, read the other way. It also covers the one thing
   inverting a dictionary cannot: "hello". CC-CEDICT glosses 你好 "hello; hi",
   but 你好 is **absent from the HSK vocabulary** the ranking comes from —
   genuinely absent, the syllabus counts 你 and 好 separately — so it has no
   rank to sort by and loses to 好, whose eighth sense is "(after a form of
   address) hello".
2. [`EnglishDictionaryTranslator`](lib/translation/english_dictionary_translator.dart)
   — CC-CEDICT inverted. Words and set phrases; it declines sentences.
3. [`EnglishModelTranslator`](lib/translation/english_model_translator.dart) —
   sentences, and only when the model is switched on. Asked once typing stops,
   and only about English the dictionary could not answer, for the same reason
   as 缘分 above: an entry beats a paraphrase of it.

Without the model this is a word lookup, and the screen says so rather than
declining sentences with no explanation — going by whether the **weights are
downloaded**, not by whether the tier exists, since it is always constructed
and declines at run time.

The box is not labelled "English", because only the dictionary half is
English-only. The model takes whatever it is given and `Bonjour !` comes back
as `nǐ hǎo`. That is not promised anywhere on screen: it works because the
model generalises, it is not measured, and the round-trip check reads back in
English whatever was typed. It did shape the prompt, though — saying "the
input" rather than "the English" is measurably better, and not only for other
languages. See [docs/local-model.md](docs/local-model.md).

It goes both ways round. Opening it from a line that already has a meaning
seeds the box with that meaning, selected, so `nǐ hǎo` glossed "hello" opens on
"hello" — a starting point, not a submission. Only an answer worth asking about
is carried: not a word-by-word list, and not a list of candidates, since `nǐ`
alone is honestly answered "you / doubtful / you (used to address a deity)".

**Practise this** hands the answer back to the compose screen as `Word`s rather
than text, so it lands in the input area already broken into syllables — every
gesture the keyboard offers works on it at once, with nothing to parse.

#### Why a wrong answer here is the dangerous kind

Going the other way, a bad translation is visibly bad English. Going this way
the learner cannot read the characters and the pinyin comes back perfectly
fluent either way, so **nothing on screen would give it away**.

And this direction has a failure of its own. Asked for Chinese, an 0.8B model
drifts into being a polite Chinese assistant:

| typed | came back as | which means |
| --- | --- | --- |
| I would like two beers please | 您好，请问您想要两瓶啤酒吗？ | "hello, would you like two beers?" |
| can you speak more slowly? | 您说得对，我说话确实有点快。 | "you're right, I do speak fast" |

Three of twenty phrases went that way, and the instruction forbidding it was
already in the prompt. Two worked examples fixed all three, and the same twenty
came back clean — so the examples in
[`english_prompt.dart`](lib/translation/english_prompt.dart) are load-bearing,
not illustrative.

Belt and braces, the answer is then **translated straight back into English**
and shown as "reads back as…". It costs one more generation and it is the only
thing that can catch a fluent answer to the wrong question, because it goes
through the direction that is measured and reliable.

#### The residue

Reading characters back is not quite exact, and the gaps are worth naming:

- **Equal-rank readings** used to be settled by whichever entry CC-CEDICT
  listed first, which is how 得 came out `dé`: its particle reading `de` and
  its verb reading `dé` are both rank 58, so 说得慢 read back as `shuō dé màn`.
  On a tie the neutral tone now wins — a full-tone reading of a character that
  common almost always sits inside a compound, which longest match has already
  taken as a word.
- **Tone sandhi** is not applied: 一 and 不 come back in their dictionary
  tones, so `yī diǎn` where a speaker says `yì diǎn`. The same limit as the
  spoken output below.
- **Inverting a dictionary offers candidates, not answers.** "hot" is 热 or 辣
  and nothing in the English says which, so both are shown with what each
  means. The score is `rank × (1 + sense position)`, doubled for a word outside
  the syllabus: rank alone answers "eat" with 用, sense position alone answers
  "thank you" with 三克油, and the syllabus tie-break is what separates 啤酒
  from 啤 and 朋友 from 朋 — a compound's rank leaks onto its first character,
  leaving both on 2622 and 280 respectively. An alternative scoring more than
  ten times worse than the best is dropped, which is about where a choice
  stops being a choice: "thank you" ends up with only 谢谢, where before it
  offered 三克油 (a joke transliteration) beside it.
- **Candidates that share a meaning say what tells them apart.** That is the
  usual case, not an edge one: 64% of English headwords with several
  candidates show the same gloss on two of them, and "lunch" offered three
  rows each reading "lunch". Under each such row is a note — a sense only that
  word has ("also: luncheon", "also: Chinese meal; Chinese food"), "only this
  meaning" for the plain one left over, and, where CC-CEDICT records no
  difference at all, which word is commoner. That last covers 35% of them —
  near-synonyms like 湖 and 湖泊 — and it says "no difference recorded" rather
  than inventing one: asked to explain such pairs, the 0.8B model was right
  about three in eight and confidently wrong about the rest, and a learner
  cannot tell which is which. See [docs/local-model.md](docs/local-model.md).
- **"to land" asks for the verb and "a leak" for the noun.** CC-CEDICT writes
  every verb sense "to …", so the typed form decides which comes first.
- **The gloss shown is the sense that was asked about**, not the entry's
  first. 热 leads with "to warm up", so somebody typing "hot" was choosing
  between 辣 "hot (spicy)" and 热 "to warm up" — one answer and one
  non-answer.
- **0.34% of entries cannot be spelled by this keyboard** — 359 of them keyed
  on the erhua suffix `r5`, the rest interjections like `hm` and `ng`. Those
  decline rather than come back with a hole in them.

### The app bar

Five trailing icons: **speak**, **star**, **translate**, a **⋮ group**, and
**start again**, last and furthest from the thumb.

That is one more than Material 3 advises, and it is a decision rather than an
oversight. The star belongs beside the speaker, because saving happens once a
line and tucking it away would hide it. What five costs is the title, which
gives way on the narrowest phones; the buttons keep their full 48pt, and a
test at 320pt holds both of those.

Behind the ⋮ are the things that are set-up rather than use: **Favourites**,
**Whole phrases** (the 533MB download), the keyboard arrangement, and the hints
and credits.

### Favourites

The star keeps the line on screen and the meaning showing beside it. It is on
both screens — a phrase looked up on purpose is the likeliest thing to want
again — and it shows state: filled when the line is already kept, so a line
cannot be saved twice, and outlined again as soon as the line is edited.

The list is under **⋮ → Favourites**, and the "Saved" message has a **View**
button that opens it at once. Tapping a row puts that line back in the input
area; from the translate screen it goes straight on to the compose screen, as
"Practise this" would.

**Holding a row and dragging it** puts the list in your own order, which is
kept. New favourites still arrive at the top. It is Flutter's
`ReorderableListView`, which picks the gesture by platform — hold on a phone, a
drag handle on a desktop — and gives a screen reader "move up" and "move down"
as well, which a hand-built gesture would not. Swiping a row asks before it removes anything, and so
does tapping a filled star — there is one way to lose a favourite and it
always asks first.

Two things about how it is built are not obvious from the screen:

- **A favourite is stored as syllables, not as text.** Opening one rebuilds the
  line, and written pinyin cannot be split back reliably — `wanan` is two
  words — while each syllable's dictionary key reads back exactly. The text is
  derived whenever it is shown.
- **The meaning is kept as it was.** It is what the learner decided was worth
  keeping, so a later model answer, or switching the model off, does not
  change the list under them.

It is kept in the platform's preferences — `SharedPreferences` on Android,
`NSUserDefaults` on iOS, `localStorage` in a browser — through
`shared_preferences`, because that is the one store that works on every target
this app builds for; `path_provider` has no directory to offer a browser.

### Which language the app works in, and why

English, and not as a default that localisation would lift. The content is
English all the way down, because **CC-CEDICT is a Chinese-English
dictionary**:

- Meanings come back in English, since that is what the glosses are.
- The reverse index is built from those same glosses, so looking a word up
  means typing English. "water" resolves; "eau" does not, and would not
  whatever language the interface were in.

Translating the interface is an ordinary Flutter job — there is no
`flutter_localizations` here and every string is hardcoded, but that is
mechanical. It would give a French interface wrapped around an English
dictionary, which is worse than it sounds: the one part that would genuinely
serve a French speaker is the model, and that needs no help.

The model works out for itself what it is reading, so a *sentence* in another
language usually does work — `Bonjour !` comes back as `nǐ hǎo`. Nothing on
screen promises it. It is the model being good at languages rather than a
feature, it is measured only as far as the table in
[docs/local-model.md](docs/local-model.md), and the round-trip check reads back
in English whatever was typed, so it is a weaker safety net from another
language. The ⓘ dialog says as much, under "Why it is in English".

Properly supporting another language means a different dictionary source for
it — CFDICT for French, HanDeDict for German, both much smaller and patchier
than CC-CEDICT — plus its own reverse index and its own ranking work. That is
a project, not an l10n pass.

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
