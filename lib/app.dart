import 'package:flutter/material.dart';

import 'screens/compose_screen.dart';
import 'theme.dart';
import 'translation/phrasebook_translator.dart';

class KouyuApp extends StatelessWidget {
  const KouyuApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Kǒuyǔ',
      theme: kLightTheme,
      darkTheme: kDarkTheme,
      // The one place a translation implementation is named. Everything below
      // here knows only the Translator interface.
      home: const ComposeScreen(translator: PhrasebookTranslator()),
    );
  }
}
