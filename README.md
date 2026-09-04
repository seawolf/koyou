# Kǒuyǔ

A Flutter app for practising spoken Mandarin.

> **Status: foundations.** The project scaffold, theme, icon, and test suite
> are in place, and the app builds and runs. The home screen is still a
> placeholder greeting — the real functionality comes next.

## Requirements

- Flutter 3.47 or newer (Dart SDK `^3.13.2`)
- Platform toolchains for whichever targets you build: Xcode + CocoaPods for
  iOS, the Android SDK command-line tools for Android, Chrome for web
- [ImageMagick](https://imagemagick.org) 7, only if you need to regenerate the
  app icon

Run `flutter doctor` to check what your machine is missing.

## Getting started

```bash
flutter pub get
flutter run
```

`flutter run` picks a connected device; pass `-d chrome`, `-d ios`, or
`-d android` to choose one. To serve the web build without launching a browser:

```bash
flutter run -d web-server --web-port 5123
```

## Checks

These three are the gate — run them before every commit:

```bash
dart format --output=none --set-exit-if-changed .
flutter analyze
flutter test
```

## Layout

| Path                     | What lives there                                     |
| ------------------------ | ---------------------------------------------------- |
| `lib/main.dart`          | Entry point; nothing but `runApp`                    |
| `lib/app.dart`           | Root `MaterialApp` — routing and theme wiring        |
| `lib/theme.dart`         | Brand seed colour and the light/dark themes          |
| `lib/screens/`           | One file per screen                                  |
| `test/`                  | Mirrors `lib/` (`lib/screens/x.dart` → `test/screens/x_test.dart`) |
| `assets/icon/`           | Generated icon sources — see below                   |
| `tool/generate_icons.sh` | Regenerates the icon; the source of truth for it     |

## The app icon

The mark is 口 (_kǒu_, "mouth") with a calligraphic speech flick sweeping off
its bottom-left corner — mouth plus speech, for spoken language.

Two things keep the 口 reading as a Hanzi character rather than a chat bubble.
It is built from the character's three real strokes rather than as a rounded
rectangle, so it keeps the square corners, the slight inward taper of both
verticals, and the bottom stroke's overshoot past the right-hand vertical. And
the flick hangs below the bottom stroke instead of interrupting it — 口 has to
stay closed to still be 口, which is why a solid tail fused into the outline
doesn't work.

`tool/generate_icons.sh` holds the icon's geometry and emits everything else:
the SVG in `assets/icon/`, the master and Android-adaptive PNGs beside it, and
then the per-platform icons via
[`flutter_launcher_icons`](https://pub.dev/packages/flutter_launcher_icons).
Edit the geometry at the top of that script and re-run it — never edit the
generated files:

```bash
tool/generate_icons.sh
```

The brand colour lives in two places that must agree: `RED` in that script and
`kSeedColor` in [`lib/theme.dart`](lib/theme.dart).

## Platform identifiers

The bundle/application ID is `com.seawolfsanctuary.kouyu` on both iOS and
Android. The display name is `Kǒuyǔ`; the Dart package name is `kouyu`, since
package names must be ASCII.
