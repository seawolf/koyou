# The generated data and the tools that build it

Part of the notes for AI agents; start from [AGENTS.md](../../AGENTS.md). Read
this before running or changing `tool/build_dictionary.dart` or
`tool/build_examples.dart`, or editing `assets/notes/word_notes.tsv`.

- `assets/dictionary/*.tsv`, `assets/dictionary/english/*.tsv`,
  `assets/dictionary/characters/*.tsv` and `assets/dictionary/LICENCE` all come
  from `tool/build_dictionary.dart`, which joins the CC-CEDICT export with HSK
  frequency data and writes it out three ways — pinyin to meaning, English to
  Chinese words, and characters to the pinyin they read as. Change the
  filtering there and re-run it; never edit a shard, and remember that all
  three listings are needed in `pubspec.yaml` because Flutter's asset
  directories are not recursive.

- `assets/examples/*.tsv` and `assets/examples/LICENCE` come from
  `tool/build_examples.dart`, which picks one Tatoeba sentence per word. It
  reads the dictionary's generated character and English indexes, so run it
  **after** `build_dictionary.dart`; a dictionary rebuild without it leaves
  examples pointing at the old segmentation. Tatoeba is CC BY 2.0 FR and is
  credited under ⓘ alongside the others.

`assets/notes/word_notes.tsv` is **not** generated: it is hand-written, this
project's own, and edited directly. It was drafted by Claude for the
near-synonyms learners meet and wants a native speaker's review. Keep its
notes in pinyin, never characters, and run `test/translation/word_notes_test.dart`
after any edit — it checks each line against the real dictionary.

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
- **Do not break an equal-rank tie by file order.** Two readings of the same
  characters often share a rank, and the character index used to take whichever
  CC-CEDICT listed first. 得 is rank 58 as both the particle `de` and the verb
  `dé`, so 说得慢 read back as `shuō dé màn`. The neutral tone now wins a tie,
  which is right for a general reason rather than for that one character: a
  full-tone reading of a character this common almost always sits inside a
  compound, and longest match has already taken the compound as a word.
- **The English index needs both of its signals, and a third for the ties.**
  `rank × (1 + sense position)`, doubled outside the syllabus. Rank alone
  answers "eat" with 用 (a common word with "to eat" as a minor sense); sense
  position alone answers "thank you" with 三克油 (an unranked transliteration
  that leads with it). The syllabus tie-break is there because a compound's
  rank leaks onto its first character — 啤 and 啤酒 are both 2622, 朋 and 朋友
  both 280 — which left "beer" and "friend" answered with a character nobody
  says on its own.
- **Two gloss separators, not one.** CC-CEDICT divides senses with `/` and
  synonyms within a sense with `; `, so 你好 is glossed `hello; hi` and 我 is
  `I; me; my`. Splitting only on `/` finds neither "hello" nor "I", which is
  exactly what the first cut of the English index did.
