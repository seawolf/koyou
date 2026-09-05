import 'package:flutter/material.dart';

import 'screens/compose_screen.dart';
import 'theme.dart';
import 'translation/dictionary.dart';
import 'translation/dictionary_translator.dart';
import 'translation/phrasebook_translator.dart';
import 'translation/translator.dart';

class KouyuApp extends StatelessWidget {
  const KouyuApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Kǒuyǔ',
      theme: kLightTheme,
      darkTheme: kDarkTheme,
      // The one place translation implementations are named. Everything below
      // here knows only the Translator interface.
      //
      // Curated phrases first, because they cover whole utterances a dictionary
      // cannot; the dictionary behind them for everything else. A network
      // service or an on-device model would join the end of this list.
      home: ComposeScreen(
        translator: CompositeTranslator([
          const PhrasebookTranslator(),
          DictionaryTranslator(Dictionary.bundled()),
        ]),
      ),
    );
  }
}
