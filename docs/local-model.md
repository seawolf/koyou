# Putting a local model behind the translation

Notes from measuring whether an on-device LLM can translate what this app lets
you type. Everything below was run locally on 2026-09-05; nothing here is
shipped yet, and no model integration exists in the code.

## The short version

**The dictionary stays, and does the hard half.** It resolves tone-marked
pinyin to characters — deterministic, tone-exact, and now correctly ranked. The
model only translates Chinese to English, which is what it is actually good at.

On that split, **a 0.8B model is enough**: 17 of 19 learner sentences correct,
byte-identical across repeated runs, in under a tenth of a second. On-device is
viable on current hardware, and by a wider margin than expected.

This reverses an earlier conclusion in this same document. The first round had
0.8B unusable and 2B weak, but both were being asked the wrong question — and
the dictionary underneath them was handing out 前 for "money". Neither was a
limit of the model.

## The models

Qwen 3.5's small series (March 2026) is Apache 2.0, 262K context, and aimed at
on-device use. Sizes 0.8B, 2B, 4B, 9B.

| model | Q4_K_M | notes |
| ----- | ------ | ----- |
| 0.8B  | —      | below the floor, see below |
| 2B    | 1.28GB | plausible default |
| 4B    | 2.74GB | needs an 8GB device; untested |
| 9B    | —      | not a phone model |

Apache 2.0 needs attribution, which the ⓘ dialog already does for CC-CEDICT and
the HSK data.

**Caveat on the numbers below.** The tests used Ollama's default tags —
`qwen3.5:0.8b` (1.0GB) and `qwen3.5:2b` (2.7GB) — which are a *higher*
precision than the Q4_K_M weights an app would ship. A 4-bit build is likely to
do slightly worse than what is recorded here, not better.

## What was measured

Three prompt shapes, temperature 0, thinking disabled, on an M4 Pro.

1. **Bare pinyin.** Hand the model `wǒ mài shū` and ask for English.
2. **The bridge.** Hand it the pinyin *and* the dictionary's tone-exact
   candidates per word, and ask it to choose.
3. **Characters first.** Let the dictionary resolve pinyin to characters and
   ask the model to translate those.

### Tones survive only through the dictionary

Minimal pairs — mǎi/mài (buy/sell), wèn/wěn (ask/kiss), and four more:

| prompt | 0.8B | 27B |
| ------ | ---- | --- |
| bare pinyin | 0/6 | 2/6 |
| bare pinyin, "tones are phonemic" | 0/6 | 4/6 |
| via the bridge | 4/4 | 4/4 |

A 27B model — far larger than anything that fits a phone — loses half the tone
distinctions on its own. `tā wěn wǒ` ("he kissed me") came back as "held my
hand", then "pinched me": fluent, confident, wrong. That is the failure this
app can least afford, and the dictionary is what prevents it.

Telling the model that tones matter helps the large model and makes the small
one *worse*: 0.8B produced "I am sorry, but I cannot translate this sentence".
Long instructions crowd out small models.

### Size, on realistic learner sentences

Nineteen ordinary phrases, three architectures, measured after the ranking fix:

| architecture | 0.8B | 2B | 27B |
| ------------ | ---- | -- | --- |
| bare pinyin | unusable | fails tones | 9/10 |
| pinyin + gloss candidates | unstable | ~10/15 | 15/15 |
| **dictionary → characters → model** | **17/19** | **17/19** | — |
| identical across 3 runs | **19/19** | **19/19** | — |
| median latency (M4 Pro) | **0.09s** | 0.16s | 3.5s |

0.8B and 2B score the same, and **both remaining failures are the same
dictionary error, not a model error**: `qián` resolves to 前 (rank 127) rather
than 钱 (218), so "how much money" becomes "how much did this come from". The
model translates faithfully what it is given.

0.8B's instability — `nǐ hǎo shìjiè` flipping between "Hello world" and "You are
good" — is gone. It was a symptom of the harder task, not of the size.

### Why characters first wins

Characters are what the model was trained on. Glosses are not, and a small model
reads a per-word gloss list literally — which is why 2B rendered
`nǐ jiào shénme míngzi` as "You asked what name" rather than "What is your
name?". Given 你叫什么名字 it answers correctly at 0.8B.

Two failure modes had to be designed out, and both were mine rather than the
model's:

- **It answered the questions instead of translating them** — 你叫什么名字 came
  back as "My name is Qwen3.5." Fixed by telling it the input is always text to
  translate and never a conversation to join, with a translated question as the
  worked example.
- **It parroted whatever the prompt explained.** Offering alternative readings,
  and describing them in the system prompt, produced "I am British. I could
  instead be a maid". Removing the explanation was not enough — the models copy
  any candidate list they are shown.

Offering a close runner-up inline (`他没有前|钱`) was tried to fix the 钱 case
and made things worse: both models then translated *both* options, giving "I
bought a book and lost it" for 我买书|输. **Hand the model one reading and let
it translate.** Any change here needs measuring, not reasoning about.

## What ships on a phone

Ollama is a development harness, not a shipping path — nothing on a phone runs
an HTTP model server. It earns its place by letting the pipeline be tested
against a real model on a laptop; `OllamaBackend` therefore lives in the test
file, not in `lib/`.

What replaces it is a [`TranslationBackend`](../lib/translation/translation_backend.dart),
whose whole job is Chinese in, English out. **That narrowing is the important
consequence of the characters-first design**: the thing behind the seam no
longer has to be a language model at all, because it no longer has to read
pinyin. It has to translate Chinese, and phones already do that.

| backend | weights | platforms | notes |
| ------- | ------- | --------- | ----- |
| **ML Kit Translation** | Play-managed pack | Android, iOS | `google_mlkit_translation`; the same models as Google Translate offline |
| **Apple Translation** | shared system model | iOS 18+ | free, on-device, shared across apps; SwiftUI-only API, so needs a platform channel |
| **llama.cpp + Qwen3.5-0.8B** | 533MB | Android, iOS, desktop | **built** — `on_device_backend_native.dart` |
| Ollama | — | dev only | the harness, in the tests |

The platform APIs are the cheap ones and should be tried first: no bundle cost,
no first-run download to manage, and the models are shared system-wide. Neither
is measured yet, and dedicated translation models may well beat a general 0.8B
model on short sentences — but they give no prompt control, and the two prompt
failures above show how much of the quality here came from prompt shape. **The
0.8B numbers in this document are the bar a platform backend has to clear.**

If a model does ship instead, the weights cannot ride along inside the app:
Google Play caps the base AAB download at 200MB and the release APK is already
48MB. That makes it a first-run download. Apple deprecated On-Demand Resources
in iOS 27, so Background Assets is the route there.

### Web keeps the dictionary

No backend runs on the web, and that is a reason to keep the web target rather
than drop it. `TranslationBackend.translate` returns null when there is nothing
to offer, so the web build falls through to the dictionary with no code removed
and no branch to maintain — and the dictionary is a genuinely useful product on
its own. Web is also the fastest place to check anything visual. Dropping a
target later is easy; the loop is worth more than the tidiness.

### What is built

`llama_cpp_dart` (MIT) is the plugin: it bundles a matching `libllama.so` for
`arm64-v8a` as a native asset, so the APK carries llama.cpp with no Gradle
edits, and it runs generation in its own isolate so the keyboard never stalls.
`flutter_llama` was rejected — it is under the NativeMind **NONC** licence,
which is non-commercial, and pub.dev reports that as "unknown".

`ModelTranslator` sits **between** the phrasebook and the dictionary, not at
the end of the chain. The first answer wins and the dictionary always has one —
a word-by-word gloss — so anything behind it would never be reached.

Measured on this Mac against the real library and the real weights, every one
correct and about 180ms each:

| Chinese | English |
| ------- | ------- |
| 我卖书 / 我买书 | I sell books / I bought a book |
| 他吻我 / 他问我 | He kissed me / He asked me |
| 你叫什么名字 | What is your name? |
| 这个多少钱 | How much does that cost? |
| 请慢一点说 | Please speak more slowly. |

Two things had to be worked out to get there, and both are in the code:

- **Qwen3.5 is a hybrid reasoning model and its own chat template turns
  thinking on.** Every token of the budget went inside `<think>` and the reply
  was literally `<think>`. The prompt therefore writes Qwen's markup by hand
  with an already-closed empty think block, which makes it answer instead. This
  is what `think: false` was doing for the Ollama harness.
- **The native library has to match the llama.cpp revision the package pins**
  (tag `b10182`). Built against HEAD instead, the layout of
  `llama_model_params` differs and the FFI call crashes the isolate rather than
  failing cleanly. Android is immune, since the bundled `libllama.so` is built
  at the pin; only a desktop build has to be told.

### What the development machine can actually do

An earlier draft of this document said none of this could be built here. That
was wrong, and only ever true of iOS.

- **Android builds and runs.** `flutter build apk` works — 21s for a debug
  build, 32s for release, and the release APK is 48MB with the dictionary in
  it. The SDK also carries NDK 28.2 and CMake 3.22.1, which is what a native
  llama.cpp plugin needs, so even that route is open. A device is reachable
  over wireless adb.
- **Web builds**, and is the fastest loop for anything visual.
- **iOS is the only blocked target.** There is no full Xcode — Command Line
  Tools only — and CocoaPods is absent. Both need the user's password, so
  neither can be fixed from a session here:

```bash
sudo xcode-select --switch /Applications/Xcode.app/Contents/Developer
sudo gem install cocoapods
```

`sdkmanager` is also missing, but nothing above needs it; it only matters for
managing SDK packages from the command line.

## Suggested tiers

The dictionary is tier zero and always on: it is what makes the tones survive,
what resolves the characters, and the only tier that works on the web.

| tier | adds | weights | offline / web |
| ---- | ---- | ------- | ------------- |
| Dictionary only | — | 7.5MB | yes, everywhere |
| **Light (proposed default)** | Qwen3.5-0.8B | ~0.55GB | native only |
| Full | Qwen3.5-2B | ~1.3GB | native only |

0.8B is now the proposed default rather than something to leave out. It matches
2B on this set at a third of the weights and twice the speed, which on a phone
is the difference between a feature that fits and one that does not. 4B is not
worth pursuing until 0.8B is shown to fail at something.

## Open questions

- **`qián` → 前.** Both remaining failures, and purely dictionary-side. Neither
  extra pinyin nor inline alternatives fixed it; a phrase-level entry would,
  but 多少钱 is not one in CC-CEDICT.
- How much does a real Q4_K_M build lose? These numbers come from Ollama's
  default tags, which are higher precision than the weights an app would ship.
- What does it cost on an actual phone rather than an M4 Pro?
- Nineteen sentences is a small set, chosen by me. It should grow before any of
  this is taken as settled.
