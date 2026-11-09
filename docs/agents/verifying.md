# Verifying a change actually runs

Part of the notes for AI agents; start from [AGENTS.md](../../AGENTS.md). Read
this before building the app to look at it.

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
- **A swipe does nothing when driven by a browser automation tool.** Those
  tools send a drag as one jump, and a `Dismissible` needs the moves in
  between. Dispatch a sequence of `pointermove` events to `flt-glass-pane`
  instead; swiping a favourite away works that way, and by hand.
