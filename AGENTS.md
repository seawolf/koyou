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

## The web model tier

`web/wllama/` is staged by `tool/fetch_wllama.sh` and **not committed** — 9MB
of third-party browser build, for which npm is the source of truth. A build
without it degrades to the dictionary rather than failing, which is the same
contract a phone with no weights has, so do not add a hard error.

The version is pinned in that script for a reason. wllama's API changed shape
between majors and the failures are not readable:

- **`pathConfig` wants a `default` key** in 3.x, holding the URL of the single
  `wasm/wllama.wasm`. The 2.x `single-thread` / `multi-thread` keys throw
  `"default" is missing from pathConfig`.
- **`createCompletion` takes one options object**, llama.cpp-server shaped:
  `{prompt, n_predict, temperature, stop}`. There is no `nPredict`. Called the
  2.x way — `createCompletion(prompt, opts)` — the string lands where the
  options belong, the encoded worker message is garbage, and it surfaces as
  `RangeError: Invalid typed array length: 1163217991` from `runAction`
  reading a length out of the wasm heap. It looks like a broken model or a
  broken wasm and is neither.
- **`stop: ['\n']`** is a real stop sequence here, which the native side has to
  imitate by breaking out of its token stream.

Multi-threaded WASM needs `COOP`/`COEP` on the host for `SharedArrayBuffer`.
Not required where WebGPU is available, which is now every major browser.

The parts worth testing live in `web_model.dart`, which imports no
`dart:js_interop` and so runs on the VM with a fake engine. Keep it that way:
only the binding in `on_device_backend_web.dart` should need a browser.

## Two Android build warnings that are not bugs

Both appear on every `flutter build apk`. Neither breaks the build, and neither
is fixable here. Do not spend an afternoon on them again.

**`java.lang.System::load has been called by ... NativeLibraryLoader`** —
Gradle 9.3.1's own `native-platform` JAR calling a restricted method on a newer
JDK. Nothing in this repo is involved. Adding
`--enable-native-access=ALL-UNNAMED` to `org.gradle.jvmargs` was tried and does
**not** silence it: the call is in Gradle's launcher JVM, not the daemon those
args configure. It goes away when Gradle does.

**`Your app uses the following plugins that apply Kotlin Gradle Plugin (KGP):
flutter_tts`** — this one is real, and will eventually fail rather than warn.
The switch is `android.builtInKotlin` in `android/gradle.properties`, which the
Flutter template sets to `false`. Setting it to `true` fails immediately and
says exactly why:

```
> Failed to apply plugin 'kotlin-android'
  Solution: Remove the 'org.jetbrains.kotlin.android' plugin from this
  project's build file: .../flutter_tts-4.2.5/android/build.gradle
```

So the blocker is entirely inside `flutter_tts`, not here — **this app is
already on built-in Kotlin**: its `plugins` block applies only
`com.android.application` and the Flutter plugin, and the
`org.jetbrains.kotlin.android` line in `settings.gradle.kts` is `apply false`,
a version declaration rather than an application.

Switching packages does not help. `stts`, the obvious alternative, has not
migrated either — its changelog moved to the Kotlin Gradle *DSL*, which is a
different thing. The fix is upstream; when `flutter_tts` ships it, flip
`android.builtInKotlin` to `true` and check the build.

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
  Which reading earned it is inferred from two signals — the commonest HSK
  compound, and how many CC-CEDICT entries use the character in that reading —
  and a reading keeps the rank if either supports it. Both are needed: alone,
  the first loses 喝 "to drink" to "to shout", and the second loses the adverb
  readings of 都 and 还. Do not simplify it to one.

## Running the model tests

Two suites are tagged off by default, because both need something the machine
may not have. Neither is part of `flutter test`:

```bash
# the Ollama harness — a laptop check against a real model
ollama serve & ollama pull qwen3.5:0.8b
flutter test --tags ollama

# the real shipping path: llama.cpp plus the real weights
KOUYU_LLAMA_LIB=/path/to/libllama.dylib \
KOUYU_LLAMA_MODEL=/path/to/Qwen3.5-0.8B-Q4_K_M.gguf \
flutter test --tags llama
```

Two traps in there, both of which cost an afternoon:

- **`flutter_test` replaces `HttpClient` with a mock that answers 400 to
  everything**, so a test cannot reach the network by accident. Any test that
  means to must set `HttpOverrides.global = null` first. Without it the Ollama
  test decided Ollama was absent and skipped itself while Ollama was running —
  a green suite that had checked nothing.
- **A hand-built `libllama` must match the revision `llama_cpp_dart` pins**,
  named in its README (currently tag `b10182`). Build HEAD instead and the
  struct layout of `llama_model_params` differs, so the FFI call crashes the
  isolate instead of failing cleanly. Android never hits this: the package
  bundles a `libllama.so` built at the pin.

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
- **Keep the UI and translation apart.** Nothing under `lib/screens/` or
  `lib/widgets/` may import a translation implementation — only
  `translation/translator.dart`. `lib/app.dart` is the one place an
  implementation is named. The UI is under active design and translation is
  not; neither should churn because of the other.
- **Editing happens at the caret, not at the end.** `Composition.caret` is an
  insertion point between syllables, and `commit`, `space` and `backspace` all
  act there. It defaults to `Caret(word: 0, syllable: 0)`, which for an empty
  line is also the end, so anything built by typing keeps the caret at the end
  without tracking it — that is why adding the caret changed none of the
  existing behaviour. Never reintroduce `words.last`.
- **The composed line is hit-tested, not built from tappable spans.** A
  `TextSpan` takes exactly one recognizer, so tap, second-tap and long-press
  cannot all hang off one. Instead a single gesture layer asks the
  `RenderParagraph` where the touch landed and maps that character offset to a
  unit. Three traps, each of which cost a red test that looked like a broken
  feature:
  - A `Text` wraps its paragraph in a semantics node, so `findRenderObject()`
    does not return the paragraph. Search down for it.
  - The hit range must include a unit's **end** offset: a touch on the right
    half of its last character reports the position after it.
  - `currentFrameTimeStamp` asserts when read outside a frame, which a gesture
    callback is. Use `currentSystemFrameTimeStamp`, which is also the one a
    test can advance — the wall clock cannot be, so a timing window checked
    against `DateTime.now()` is untestable.
- **Never register `onDoubleTap` on the line.** It puts every single tap behind
  the double-tap timeout, and placing the caret is the commonest thing anyone
  does here. A second tap is spotted by hand: the first acts at once, the
  second supersedes it.
- **A word is not always syllables.** `Word` is sealed: `Spoken` has pinyin and
  a dictionary key, `Literal` is a name carried as written. Anything walking a
  line must handle both — switch on the type rather than reaching for
  syllables. `TranslationRequest.key` is null once a literal is present,
  because no entry covers `wǒ jiào Steve`.
- **A literal needs nothing invented for it downstream.** It goes to the model
  verbatim, because 我叫Steve is ordinary Chinese text and the model reads it
  without being told anything — there is a test against the real model. Do not
  add transliteration, a placeholder token, or a prompt explaining it.
- **Raw `Syllable`s take the phonological initial, not the key label.** The `w`
  key spells `w` but its initial is empty, so `Syllable(initial: 'w', rime:
  'uo')` is `wuǒ`, not `wǒ`. Build `wǒ` as `('w', 'o')` or `('', 'uo')`. Going
  through `withInitial(key('w')).withRime('uo')` does the right thing; a raw
  constructor in a test does not.
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
- **The model is only asked what the dictionary could not answer.** Its own
  doc says so, and the code has to agree: where the quick tier matched the
  whole line as one entry — a curated phrase, or a dictionary entry — the model
  is not asked and cannot displace it. The lookup key drops word breaks, so
  `yuán fèn` and `yuánfèn` both find 缘分; the model is handed one character per
  word, so the spaced one reached it as 元份 and its paraphrase won. Widening
  this to "ask always and prefer the model" brings that back.
- **`Translation.matchedWhole` is stated, never inferred.** Whoever answers
  says whether it is a single entry for everything typed; the screen only
  reads it. Deducing it from `!wordByWord` worked only while nothing
  generative sat in the quick chain — a model's answer is not word by word
  either, so it would have counted as an entry and outranked the dictionary it
  defers to. `app.dart` did once have `ModelTranslator` in that chain, so this
  is not hypothetical. `model_translator_test.dart` pins that a generated
  answer never sets it.
- **Do not route tone correction through the model.** It is a dictionary
  question — 0.16ms warm — and a model would mean a second generation on top of
  the translation, for the least reliable thing a small model does: it does not
  know which tone is right, it knows which sentence sounds likely, and it nags
  confidently about correct input.
- **Never rank-ratio one word against another to correct it.** 呢 is rank 96
  against 你 at 5, and 时 is 115 against 是 at 4; both are perfectly good words.
  `DictionarySuggester` only speaks when what was typed is *not a word*, or is
  a word no syllabus contains. Widening that will make it nag, and
  `bundled_dictionary_test.dart` pins twelve ordinary inputs it must stay
  silent on.
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
