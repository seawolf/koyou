# AGENTS.md

Notes for AI agents working in this repo. Human-facing setup and usage live in
[README.md](README.md) — read that first; this file only adds what isn't
obvious from the code.

## Always run before finishing

All three must pass. `flutter analyze` is configured to be clean, so treat any
output from it as a failure, not a warning:

```bash
dart format --output=none --set-exit-if-changed .
flutter analyze
flutter test
```

Add or update tests for behaviour you change. `test/` mirrors `lib/`:
`lib/screens/home_screen.dart` → `test/screens/home_screen_test.dart`.

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

Neither affects iOS or Android, where system fonts cover Hanzi.

## Deliberate decisions, so don't "fix" them

**No CJK font is bundled** — text falls back to the platform's own fonts, and
on web to Flutter's runtime Noto download. This was weighed and chosen for the
bundle size saved. Two consequences to keep in mind rather than work around:

- The web tofu flash above is expected, and web Hanzi depends on Google's CDN
  being reachable.
- Glyph forms are whatever each device picks. A device preferring a Japanese
  font renders some characters in non-simplified forms (直, 骨, 次 among
  others), which is wrong stroke information for a learner. If a learner ever
  reports odd-looking characters, this is the cause, and bundling Noto Sans SC
  — full or subset to the ~3,500 standard characters — is the fix. Raise it as
  a decision; don't just add the asset.

## Generated files — do not hand-edit

- `assets/icon/kouyu_icon.svg`, `kouyu_icon.png`, `kouyu_icon_foreground.png`
- `android/app/src/main/res/mipmap-*/`, `.../drawable-*/ic_launcher_foreground.png`,
  `.../values/colors.xml`
- `ios/Runner/Assets.xcassets/AppIcon.appiconset/`
- `web/icons/`, `web/favicon.png`

All of the above come from `tool/generate_icons.sh`. Change the geometry
variables at the top of that script and re-run it.

## Conventions

- **Theme, not literals.** Colours and text styles come from
  `Theme.of(context)`. The one hard-coded colour is `kSeedColor` in
  `lib/theme.dart`; everything else derives from it. Every screen must be
  legible in both light and dark — test both.
- **One screen per file** in `lib/screens/`. Keep `lib/main.dart` to `runApp`
  and put app-level wiring in `lib/app.dart`.
- **UI chrome is in English**; Mandarin appears as study content, and pairs
  Hanzi with pinyin that carries tone marks (`Nǐ hǎo`, never `Ni hao` or
  `Ni3 hao3`). Tones are the point of this app — never strip them.
- **No `print`.** The lint set forbids it.

## Identifiers that are expensive to change

The bundle/application ID `com.seawolfsanctuary.kouyu` is set in
`android/app/build.gradle.kts` and the Xcode project, and the Dart package name
`kouyu` is baked into every `package:kouyu/...` import. Don't change either as a
side effect of other work.

`kSeedColor` in `lib/theme.dart` and `RED` in `tool/generate_icons.sh` are the
same colour in two places and must be updated together.
