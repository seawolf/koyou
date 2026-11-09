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
