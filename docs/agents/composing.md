# Composing a line

Part of the notes for AI agents; start from [AGENTS.md](../../AGENTS.md). Read
this before touching `lib/pinyin/`, `lib/widgets/pinyin_keyboard.dart`, or the
composed line in `lib/screens/compose_screen.dart`.

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
- **A physical keyboard types through the on-screen keys' own labels.**
  `Composition.withLetter` checks each letter against `initialKeys` and
  `rimeKeysFor`, so typing reaches exactly what tapping can. Do not add a
  separate pinyin parser; the two would drift, and the first sign would be a
  syllable one can type and the other cannot.
- **Each typed letter moves on at once, and a later one may revise it.** `s`
  shows s's rimes straight away and an `h` after it turns the initial into sh,
  which is safe only because no rime begins with h. Waiting to see whether an
  `h` was coming left nothing on screen to say where typing had got to. Letters
  heading for a rime that they do not spell yet wait in `Draft.typed`, and the
  rime bank narrows to what still fits.
- **There is no setting for keyboard typing, and nothing to remember per
  device.** The screen listens with a `Focus`, not a text field, so a phone's
  own keyboard never comes up; where no physical keyboard is attached, no key
  events arrive. Keep text fields off the compose screen — the word dialog is
  a separate route on purpose — and there is a test that none is there.
- **The two backspaces differ on purpose.** The keyboard's takes back a letter,
  by typing the syllable again without it, so `sh` returns to `s` by the same
  rule that built it; the on-screen one takes back a stage, because a stage is
  what its keys chose. Either one, with nothing being built, removes the
  previous syllable whole.
- **Keys with a modifier held are left alone**, so Cmd+R reloads and Ctrl+A is
  not an `a`. Tones are digits, `ni3`, because that is the convention learners
  already type; the line still shows tone marks.
- **Paste reads written pinyin, and refuses it without tones.** `readWritten`
  in `lib/pinyin/written.dart` splits by the rule pinyin is written to — a
  syllable starting with a, o or e follows another only after an apostrophe,
  so `fāngàn` is `fān gàn` — relaxing it only when nothing else reads, for
  the common `xīān`. No syllable takes two tone marks. Text with no tones at
  all is refused, not read as neutral: that is the ambiguity the app exists to
  avoid. A toneless word of more than one syllable is a name, so `Anna` stays
  `Anna` rather than becoming `an na`. A paste is replayed through the same
  insertion typing uses (`Composition.withPasted`), never spliced in.
- **Cmd/Ctrl+C takes over the browser's copy only because nothing on this
  screen is selectable.** Put a `SelectableText` or `SelectionArea` here and
  the shortcut would hide what the learner selected; it would need to defer to
  a selection first.
- **A tone number with nothing being built retones the syllable before the
  caret** (`Composition.withTone`), so `ni3` then `4` is `nì`. The window
  closes by itself: a new syllable takes the number, and after a space the
  caret has nothing before it in its word. It is the same syllable a retone
  would reach by tapping, not a separate "last committed" memory — keep it
  that way, or moving the caret and retoning would disagree.
