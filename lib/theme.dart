import 'package:flutter/material.dart';

/// The brand colour, also used as the launcher icon background.
///
/// Keep in sync with `RED` in `tool/generate_icons.sh`.
const Color kSeedColor = Color(0xFFC8342A);

/// Themes for each platform brightness, both derived from [kSeedColor].
final ThemeData kLightTheme = _themeFor(Brightness.light);
final ThemeData kDarkTheme = _themeFor(Brightness.dark);

ThemeData _themeFor(Brightness brightness) {
  return ThemeData(
    colorScheme: ColorScheme.fromSeed(
      seedColor: kSeedColor,
      brightness: brightness,
    ),
  );
}
