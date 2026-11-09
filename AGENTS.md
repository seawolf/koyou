# AGENTS.md

Notes for AI agents working in this repo. Human-facing setup and usage live in
[README.md](README.md) — read that first; this file only adds what isn't
obvious from the code.

This file holds what applies everywhere. The traps that belong to one part of
the app are in [`docs/agents/`](docs/agents/), and each is worth its length
only when you are in that part — so check the table below before you start,
not after something has gone wrong.

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

## Before you touch…

| If you are working on… | Read first |
| --- | --- |
| `lib/pinyin/`, the keyboard, the composed line and its caret | [composing.md](docs/agents/composing.md) |
| `lib/translation/`, the translate screen, prompts, what an answer shows | [translation.md](docs/agents/translation.md) |
| `web/wllama/`, the on-device backends, the `ollama`/`llama` test tags | [model.md](docs/agents/model.md) |
| `tool/build_*.dart`, anything under `assets/dictionary/`, `assets/examples/` or `assets/notes/` | [data.md](docs/agents/data.md) |
| `lib/favourites/`, the star, the favourites screen | [favourites.md](docs/agents/favourites.md) |
| `android/`, Gradle, a warning from `flutter build apk` | [android.md](docs/agents/android.md) |
| Building the app to look at it, or something that looks broken on web | [verifying.md](docs/agents/verifying.md) |
| Fonts, Hanzi on screen, localisation | [decisions.md](docs/agents/decisions.md) |

Several can apply at once: a change to the translate screen's answer list is
both translation and favourites if it touches the star. When a note in one of
those files stops being true, fix it there; when one turns out to apply
everywhere, move it here.

## Verifying a change actually runs

`flutter test` covers widget behaviour, but for anything visual, build and look
at it, in light and dark. Web is the fastest route:

```bash
flutter build web --release
```

Always `--release`: a debug web build shows a blank page in a browser that
can't attach the Dart debug service. That and the other web artefacts that look
like bugs but aren't are in [verifying.md](docs/agents/verifying.md).

## Generated files — do not hand-edit

- `assets/icon/kouyu_icon.svg`, `kouyu_icon.png`, `kouyu_icon_foreground.png`
- `android/app/src/main/res/mipmap-*/`, `.../drawable-*/ic_launcher_foreground.png`,
  `.../values/colors.xml`
- `ios/Runner/Assets.xcassets/AppIcon.appiconset/`
- `web/icons/`, `web/favicon.png`

All of the above come from `tool/generate_icons.sh`. Change the geometry
variables at the top of that script and re-run it.

- `assets/dictionary/` (all three listings, and its `LICENCE`) comes from
  `tool/build_dictionary.dart`.
- `assets/examples/` comes from `tool/build_examples.dart`, which must run
  **after** the dictionary tool.

`assets/notes/word_notes.tsv` is the exception: hand-written, edited directly.
How each is built, the order, the licences, and the traps that have each cost a
common word are in [data.md](docs/agents/data.md).

## Decisions that look like omissions

Each of these was chosen, and undoing one is a decision to raise, not a fix.
The reasoning is in the linked file.

- **No CJK font is bundled.** The learning surface is pinyin, which system
  fonts cover. ([decisions.md](docs/agents/decisions.md))
- **Every string is English, with no `flutter_localizations`.** The dictionary
  is English, so a translated interface would not translate the app.
  ([decisions.md](docs/agents/decisions.md))
- **Five app-bar icons**, one over Material 3's advice, so the star sits beside
  the speaker. ([favourites.md](docs/agents/favourites.md))

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
- **Never style a label with a `TextTheme` entry inside a button.**
  `theme.textTheme.headlineSmall` and friends carry a colour, and it beats the
  button's own foreground — which once put near-white text on the light fill of
  the tone keys at 1.3:1. Put sizing on the `ButtonStyle`'s `textStyle` as a
  bare `TextStyle`, and let the button colour its own text.
  `test/screens/key_contrast_test.dart` measures every kind of key against WCAG
  AA in both themes; run it after touching colours.
- **No `print`.** The lint set forbids it.

### Speech

- **Speech is not a tier of translation.** It answers how the pinyin sounds,
  not what it means, and the two fail independently — a phrase with no
  translation is still worth hearing, which is why `wǒ ài nǐ` must not go
  silent just because the phrasebook answered it and carries no characters.
  So `lib/audio/` resolves the characters itself and `Speech` is wired
  separately in `app.dart`. Screens may import `audio/speech.dart` and nothing
  else from there.
- **Never speak unasked.** Reading the line back as it grows would say a
  fragment of a sentence after every syllable. The speaker is a button, any
  edit stops what is playing, and there is a test that nothing is spoken
  without a tap.
- **Audio needs characters, and is immune to the ambiguity translation is
  not.** A voice handed `wǒ mài shū` says nothing useful, so the dictionary
  resolves 我卖书 first. But because a key carries its tone, every word
  matching it is pronounced identically — 前 and 钱 are both `qián` — so a
  wrong pick that ruins a translation still sounds right. Do not add
  disambiguation machinery for audio's sake.

## Identifiers that are expensive to change

The bundle/application ID `com.seawolfsanctuary.kouyu` is set in
`android/app/build.gradle.kts` and the Xcode project, and the Dart package name
`kouyu` is baked into every `package:kouyu/...` import. Don't change either as a
side effect of other work.

`kSeedColor` in `lib/theme.dart` and `RED` in `tool/generate_icons.sh` are the
same colour in two places and must be updated together.
