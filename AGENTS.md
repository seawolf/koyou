# AGENTS.md

Notes for AI agents working in this repo. Human-facing setup and usage live in
[README.md](README.md) — read that first; this file only adds what isn't
obvious from the code.

## What this app is for, and what it deliberately isn't

Kǒuyǔ is for learners who want to **speak** Mandarin: tones, pronunciation,
comprehension. It is not for learning to read or write characters.

That single constraint decides a lot, so check features against it rather than
against what other language apps do:

- **Pinyin is the input and the output.** The gap this app exists to fill is
  that nothing lets you simply type `nǐ hǎo, shìjiè`. Dictionary apps take
  pinyin but one word at a time; translation apps take phrases but want Hanzi,
  and every phone IME converts pinyin to characters at the first opportunity.
  Do not add a Hanzi conversion step — that is the thing being avoided.
- **Don't teach in small locked steps.** Duolingo-style gating was rejected on
  purpose: a learner should be able to type a whole phrase on day one.
- **Hanzi is not part of the learning surface.** It may be fine in incidental
  places, but it is never what the learner is asked to read, recognise or
  produce.

## Always run before finishing

All three must pass. `flutter analyze` is configured to be clean, so treat any
output from it as a failure, not a warning:

```bash
dart format --output=none --set-exit-if-changed .
flutter analyze
flutter test
```

Add or update tests for behaviour you change. `test/` mirrors `lib/`:
`lib/screens/compose_screen.dart` → `test/screens/compose_screen_test.dart`.

## Verifying a change actually runs

`flutter test` covers widget behaviour, but for anything visual, build and look
at it. Web is the fastest route and the only target that builds on a machine
without Xcode and the Android SDK:

```bash
flutter build web --release
```

Note that **debug** web builds do not boot in a browser that can't attach the
Dart debug service — you get a blank page and a failed
`$dwdsSseHandler` WebSocket, which is not an app bug. Use `--release` when
serving the app for inspection; `.claude/launch.json` is already set up that
way.

Two more web-only artefacts that look like bugs but aren't, both observed while
setting this up:

- **Hanzi renders as tofu (`□`) on first paint.** No CJK font is bundled;
  Flutter web downloads Noto fallbacks from Google's CDN at runtime, character
  range by character range. Reload once they're cached before judging any text
  rendering. If Hanzi is *persistently* tofu, the CDN is unreachable.
- **The app renders into a small box in the corner.** Flutter laid out against
  the viewport size it saw at load and missed a later resize. Reload.

## Deliberate decisions, so don't "fix" them

**No CJK font is bundled**, chosen for the bundle size saved. This costs much
less than it first appears, because the learning surface is pinyin: tone-marked
vowels (ǎ ē ǐ ò ǔ ǚ) are Latin, covered by system fonts everywhere, and not
subject to the tofu or CDN problems above at all.

What it does mean: any Hanzi the app does show is at the mercy of whatever font
the device picks, which on web needs Google's CDN, and on a device preferring a
Japanese font renders some characters in non-simplified forms (直, 骨, 次 among
others). That is wrong stroke information for a learner — but it only matters
if Hanzi is put on the learning surface, which is against the product's grain
anyway. Bundling Noto Sans SC (full, or subset to the ~3,500 standard
characters) is the fix if that ever changes. Raise it as a decision; don't just
add the asset.

## Generated files — do not hand-edit

- `assets/icon/kouyu_icon.svg`, `kouyu_icon.png`, `kouyu_icon_foreground.png`
- `android/app/src/main/res/mipmap-*/`, `.../drawable-*/ic_launcher_foreground.png`,
  `.../values/colors.xml`
- `ios/Runner/Assets.xcassets/AppIcon.appiconset/`
- `web/icons/`, `web/favicon.png`

All of the above come from `tool/generate_icons.sh`. Change the geometry
variables at the top of that script and re-run it.

- `assets/dictionary/*.tsv` and `assets/dictionary/LICENCE` come from
  `tool/build_dictionary.dart`, which joins the CC-CEDICT export with HSK
  frequency data. Change the filtering there and re-run it; never edit a shard.

CC-CEDICT is CC BY-SA 4.0 and the HSK data is MIT. The generated shards carry
both notices and the app credits them under the ⓘ button. Keep that credit if
you touch the app bar.

Two traps in that tool, both of which cost a common word once:

- **Do not drop a gloss because it mentions a character.** 你 is glossed "you
  (informal, as opposed to courteous 您[nin2])", and discarding such glosses
  discarded the commonest word for "you". Remove the bracketed aside, keep the
  gloss.
- **Join HSK ranks on the word *and its reading*.** 解 is common as `jiě` and
  rare as `xiè`; ranking the rare reading by the common one put "acrobatic
  display" ahead of "to thank" for `xiè`. And CC-CEDICT writes ü as `u:` where
  the HSK data writes `ü`, so the join needs normalising or it silently misses
  every ü word.
- **A word's frequency is not its reading's frequency.** The HSK data gives one
  `frequency` per word and lists every reading under it in `forms[]`, so
  joining on the reading is not enough on its own: the rank still has to be kept
  off the readings that did not earn it. 的 is the commonest word in the
  language as `de5` and carried rank 1 into `di4` as well, offering "bull's-eye;
  target" to anyone typing `dì`. `docs/local-model.md` is what turned it up.

## Conventions

- **Theme, not literals.** Colours and text styles come from
  `Theme.of(context)`. The one hard-coded colour is `kSeedColor` in
  `lib/theme.dart`; everything else derives from it. Every screen must be
  legible in both light and dark — test both.
- **One screen per file** in `lib/screens/`. Keep `lib/main.dart` to `runApp`
  and put app-level wiring in `lib/app.dart`.
- **Pinyin with tone marks is the content; Hanzi is not.** Write `Nǐ hǎo`,
  never `Ni hao` or `Ni3 hao3`. Tones distinguish words, so a toneless syllable
  is not a simplified one, it is an ambiguous one — never strip or normalise
  tones away, including in lookup keys and cache keys. UI chrome stays in
  English.
- **Keep the UI and translation apart.** Nothing under `lib/screens/` or
  `lib/widgets/` may import a translation implementation — only
  `translation/translator.dart`. `lib/app.dart` is the one place an
  implementation is named. The UI is under active design and translation is
  not; neither should churn because of the other.
- **`inventory.dart` decides what can be typed.** The keyboard's banks are
  derived from it, so a syllable is made reachable by adding it there, never by
  adding a key to a widget. Anything the inventory omits is unreachable by
  design — that is what stops the keyboard offering `qong`.
- **Never style a label with a `TextTheme` entry inside a button.**
  `theme.textTheme.headlineSmall` and friends carry a colour, and it beats the
  button's own foreground — which once put near-white text on the light fill of
  the tone keys at 1.3:1. Put sizing on the `ButtonStyle`'s `textStyle` as a
  bare `TextStyle`, and let the button colour its own text.
  `test/screens/key_contrast_test.dart` measures every kind of key against WCAG
  AA in both themes; run it after touching colours.
- **Pinyin does not identify a word, so never present a lookup as certain
  when it isn't.** Only 17% of one-syllable pinyin keys map to a single word,
  against 91% for two syllables. `Translation.uncertain` exists for this and
  the UI says "several words sound like this"; a plausible-looking single
  answer where there are forty candidates is worse than a list.
- **No `print`.** The lint set forbids it.

## Identifiers that are expensive to change

The bundle/application ID `com.seawolfsanctuary.kouyu` is set in
`android/app/build.gradle.kts` and the Xcode project, and the Dart package name
`kouyu` is baked into every `package:kouyu/...` import. Don't change either as a
side effect of other work.

`kSeedColor` in `lib/theme.dart` and `RED` in `tool/generate_icons.sh` are the
same colour in two places and must be updated together.
