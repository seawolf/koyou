# Putting a local model behind the translation

Notes from measuring whether an on-device LLM can translate what this app lets
you type. Everything below was run locally on 2026-09-05; nothing here is
shipped yet, and no model integration exists in the code.

## The short version

**The dictionary stays.** A model on its own cannot read tone-marked pinyin
reliably — it flattens tones, which is the one thing this app exists to teach.
Given the dictionary's tone-exact candidates it does much better. So the model
goes *behind* the dictionary and is grounded by it, not in front of it.

The open question is size. 0.8B is below the floor, 2B is stable but misses
first-lesson question forms, and the 27B that gets everything right is not
shippable.

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

Fifteen ordinary phrases through the bridge:

| | 0.8B | 2B | 27B |
| --- | --- | --- | --- |
| accuracy | unusable | ~10/15 | 15/15 |
| identical across 3 runs | no | **12/12** | — |
| median latency | 0.15s | 0.25s | 3.5s |

0.8B is not slow, it is unstable: `nǐ hǎo shìjiè` gave "Hello world" under one
prompt and **"You are good"** under another, and it twice echoed the prompt
back instead of answering. 2B fixed that completely — byte-identical output
across repeated runs — but fails on question forms, which is the worst place
for a speaking app to fail:

| typed | 2B | 27B |
| ----- | -- | --- |
| `nǐ jiào shénme míngzi` | "You asked what name." | "What is your name?" |
| `zhè ge duōshǎo qián` | "This much money is needed." | "How much does this cost?" |
| `nǐ jīnnián duō dà` | "You think this year is big." | "How old are you this year?" |
| `qǐng màn yīdiǎn shuō` | "Please ask for a small amount of time." | "Please speak a little more slowly." |

The pattern is that 2B reads the candidate list word by word and misses the
construction. Which suggests the gloss list itself is part of the problem.

### Characters first, and why it is not yet an answer

Letting the dictionary resolve to characters and translating those fixed
exactly those grammar failures — "Please speak more slowly", "Let's go
together" — because characters are what the model was trained on. It brought
two new problems:

- **The model answers the question instead of translating it.** 你叫什么名字 →
  "My name is Qwen3.5." A prompt problem, and probably fixable.
- **The dictionary picks the wrong character.** `qián` resolved to 前 (before)
  rather than 钱 (money). Not fixable by prompting — see the ranking trap in
  [AGENTS.md](../AGENTS.md), which this test is what uncovered.

Characters-first is the most promising shape, but it cannot be evaluated until
the ranking is right, because it depends entirely on the dictionary's top pick.

## What integration would cost

- **Package.** `llama_cpp_dart` (MIT) covers Android, iOS, macOS, Windows and
  Linux, and runs inference in an isolate so the UI never blocks. It ships **no
  prebuilt binaries** — llama.cpp has to be compiled per platform.
- **Delivery.** Google Play caps the base AAB download at 200MB, so the weights
  cannot ship inside the app; they are a first-run download. Apple deprecated
  On-Demand Resources in iOS 27, so the current route there is Background
  Assets.
- **Web gets nothing.** The package is native-only. The web build keeps the
  dictionary, which is a good reason not to demote it to a fallback.
- **The seams already exist.** `CompositeTranslator` takes another `Translator`
  at the end of the chain, and the screen's 250ms "looking it up…" delay
  already covers multi-second latency.

### The blocker to clear first

None of this can be built or tested on the current development machine. There
is no full Xcode (Command Line Tools only), and CocoaPods, the Android SDK,
cmake and ninja are all absent. Web-only development has hidden this so far; a
native plugin makes it a hard stop.

## Suggested tiers

The dictionary is tier zero and always on, because it is what makes the tones
survive:

| tier | adds | size | offline / web |
| ---- | ---- | ---- | ------------- |
| Dictionary only | — | 7.5MB | yes, everywhere |
| Mid (proposed default) | Qwen3.5-2B | ~1.3GB | native only |
| Full | Qwen3.5-4B | ~2.7GB | 8GB devices |

There is deliberately no 0.8B tier. A 0.55GB model that answers "You are good"
to `nǐ hǎo` is worse than the 7.5MB asset it would sit in front of.

## Open questions

- Does 4B close the question-form gap 2B misses? Untested, and it decides
  whether this is a mid-range feature or a high-end one.
- Does characters-first beat the gloss bridge once the ranking is fixed?
- How much does a real Q4_K_M build lose against the higher-precision tags
  tested here?
- What does any of this cost on an actual phone, as opposed to an M4 Pro?
