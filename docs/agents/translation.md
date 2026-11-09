# Translation and the model

Part of the notes for AI agents; start from [AGENTS.md](../../AGENTS.md). Read
this before touching anything under `lib/translation/`,
`lib/screens/translate_screen.dart`, or what a screen shows of an answer.

## The direction a translation goes in

`TranslationBackend` has two methods, `intoEnglish` and `intoChinese`, rather
than one with a flag. That is on purpose. **A model is never asked to read a
tone mark or to write one**: the dictionary resolves pinyin to characters on
the way in and reads characters back to pinyin on the way out, and that
indirection is the only reason an 0.8B model is good enough at all.

Passing the directions the wrong way round is the one mistake in this app that
nothing on screen would reveal — going into English a bad answer is visibly bad
English, but coming back the learner cannot read the characters and the pinyin
is fluent either way. Which is also why `EnglishModelTranslator` translates its
own answer straight back and shows it as "reads back as…", and why the fake
backend in `model_translator_test.dart` throws if asked the wrong direction.

The two prompts are separate files and neither is a mirror of the other. Going
into Chinese, the model stops translating and starts being a polite Chinese
assistant — measured, three phrases in twenty — and the two worked examples in
`english_prompt.dart` are what stop it. They are load-bearing; taking them out
brings the failure back.

That prompt also says "translate the input" rather than "translate the
English", which is deliberate and measured. Naming English rendered `Je
voudrais deux bières` as 我想喝两杯咖啡 — *coffee* — and, on the English set,
turned "my phone is broken" into 您的手机坏了，能帮我修一下吗？. Other languages
are not promised on screen: they work because the model generalises, and the
round-trip check reads back in English whatever was typed.

## Conventions

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
- **An example shows the word in the reading it was offered with.**
  `EnglishDictionaryTranslator` reads the sentence either side of the word
  and puts the word back as the candidate's own syllables, rather than reading
  the whole sentence: a word with several readings would otherwise carry one
  tone in its row and another in its example. Do not "simplify" it to one
  `read` of the sentence.
- **A breakdown is the dictionary's, at one level.** `Breakdown` takes a word
  apart into its characters, each looked up in the reading the word's own key
  gives it; a model's sentence is taken apart into its words, glossed by
  looking each up — never by asking the model what it meant. A neutral tone
  falls back to the same letters in a full tone, because it is the weakened
  form of the same syllable; a full tone with no entry does **not**, because
  the nearest reading is often a different word (漂 *piào* in 漂亮 against 漂
  *piāo*, "to float"). Where several words sound alike, `Translation.madeOf`
  stays empty: taking the first apart would present a guess as fact.
- **A register preference leans; it never filters.** Most words carry no
  register label, so hiding the unlabelled ones would empty most answers.
  The chosen register goes first, unlabelled words keep their order, and the
  other register goes last. A typed part of speech ("to land") is applied
  after it and wins, because it is stated outright and a register is only a
  preference.
- **Do not put a register in the model's prompt.** One line asking for formal
  or informal Mandarin took the reverse prompt from one failure in twelve to
  five or six — it answered questions, flipped the speaker, and brought back
  the waiter — and in informal mode it used the formal 您 anyway.
  `EnglishModelTranslator.say` accepts the register and ignores it on purpose;
  the screen says a sentence is translated as written.
- **Do not have the model write example sentences.** Asked for one per word,
  0.8B swapped in the commoner sibling in 7 of 20 — 月亮 for 月球, 去世 for
  逝世, 实验 for 试验 — always the rarer word of the pair, which is the one that
  needed the example. Tatoeba's are written and translated by people.
- **Do not ask the model what separates two near-synonyms.** Where several
  candidates share a gloss, `EnglishDictionaryTranslator` notes what tells them
  apart from the dictionary alone — a sense only one has, "only this meaning",
  or which is commoner — and says "no difference recorded" where CC-CEDICT
  records none. Asked to fill that gap, 0.8B was right about three pairs in
  eight and fluently wrong about the rest (`docs/local-model.md`); a learner
  cannot tell which is which, so an invented difference is worse than none.
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
