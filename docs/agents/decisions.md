# Deliberate decisions, so don't "fix" them

Part of the notes for AI agents; start from [AGENTS.md](../../AGENTS.md). Read
this before bundling a font, adding Hanzi to the screen, or localising
anything.

## No CJK font is bundled

**No CJK font is bundled**, chosen for the bundle size saved. This costs much
less than it first appears, because the learning surface is pinyin: tone-marked
vowels (ǎ ē ǐ ò ǔ ǚ) are Latin, covered by system fonts everywhere, and not
subject to the tofu or CDN problems in [verifying.md](verifying.md) at
all.

What it does mean: any Hanzi the app does show is at the mercy of whatever font
the device picks, which on web needs Google's CDN, and on a device preferring a
Japanese font renders some characters in non-simplified forms (直, 骨, 次 among
others). That is wrong stroke information for a learner — but it only matters
if Hanzi is put on the learning surface, which is against the product's grain
anyway. Bundling Noto Sans SC (full, or subset to the ~3,500 standard
characters) is the fix if that ever changes. Raise it as a decision; don't just
add the asset.

## English is structural here, not a missing translation

Every string is hardcoded English and there is no `flutter_localizations`.
Before adding one: **translating the interface would not translate the app.**
CC-CEDICT is a Chinese-English dictionary, so the glosses are English, and the
reverse index is built from those same glosses — looking a word up means typing
"water", never "eau", whatever locale the phone is in. A localised build would
be a French interface wrapped around an English dictionary.

The exception is the model, which works out for itself what it is reading;
`Bonjour !` comes back as `nǐ hǎo`. Do not turn that into a promise on screen.
It is not measured beyond the table in `docs/local-model.md`, and the
round-trip check reads back in English whatever was typed, so it is a weaker
check for anyone not working from English. The ⓘ dialog explains this under
"Why it is in English"; keep that section if you touch the dialog.

Supporting another language properly means a second dictionary source for it
(CFDICT, HanDeDict), its own reverse index and its own ranking work. Raise it
as a decision; it is not an l10n pass.
