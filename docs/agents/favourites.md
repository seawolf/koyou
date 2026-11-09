# Favourites

Part of the notes for AI agents; start from [AGENTS.md](../../AGENTS.md). Read
this before touching `lib/favourites/`, `lib/widgets/favourite_star.dart` or
`lib/screens/favourites_screen.dart`.

`lib/favourites/` is the store and `lib/widgets/favourite_star.dart` the star
both screens share, with the one confirmation dialog and the one "Saved"
message. Screens depend on the `Favourites` interface; `StoredFavourites` is
named only in `app.dart`, and it reads and writes through two closures so its
logic tests without a platform — `test/favourites/` needs no plugin except for
the one test of the real binding.

**Five app-bar icons is a decision, not drift.** It is one over Material 3's
advice, chosen so the star sits beside the speaker. Do not "tidy" it back to
four by moving something under ⋮. The test at 320pt checks what the choice may
and may not cost: the title may give way, the 48pt targets may not.

Three traps, each found while building it:

- **`SharedPreferencesAsync()` throws in its constructor** where no platform
  store is registered. Built eagerly, that stopped the app starting in a test,
  and would anywhere the plugin is missing. It is opened on first use, inside
  the handling that turns unreadable storage into an empty list.
- **A `SnackBar` with an action stays up until tapped** in this Flutter
  version — `persist` defaults to true once there is an action. The "Saved"
  message sets `persist: false`; it is a confirmation, not a question.
- **Long-press is not free on an app-bar icon.** Its tooltip already owns it on
  touch devices, and `IconButton` does not call `onLongPress` while
  `onPressed` is null — so a long-press on a disabled star would do nothing,
  which is exactly when someone opening their list would try it. That is why
  the list is a visible ⋮ item and a View action, not a gesture.

- **Symbols typed into text are at the mercy of the font.** `☆` in a
  sentence rendered as an empty box — no bundled font carries it, the same
  gap as the CJK font in [decisions.md](decisions.md). Draw an icon with a
  `WidgetSpan` instead; the Material icon font always ships. `⋮` happens to
  render, but prefer the icon where one exists.

- **Reordering is `onReorderItem`, not `onReorder`.** The older callback is
  deprecated in this Flutter version, and it hands over a `newIndex` that has
  not been adjusted for the row being lifted out — the off-by-one everyone
  used to write by hand. The new one has.
- **`Favourites.reorder` takes the whole order, not two indices.** The list on
  screen is not always the store's: a row just swiped away is hidden before the
  store has dropped it, so an index into one is not an index into the other.
- **A reordered list has to publish before the next frame.** Even awaiting a
  completed future yields, and a list published one frame late is drawn once in
  its old order — the dragged row jumps back before it settles.
  `StoredFavourites` publishes synchronously once it has loaded, and there is a
  test that the order changes before `reorder` returns.

Deleting always asks, through the star as well as by swiping, and the dialog
names the line. That was chosen over an undo message; keep the two routes
consistent if either changes.
