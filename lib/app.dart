import 'package:flutter/material.dart';

import 'screens/compose_screen.dart';
import 'theme.dart';
import 'translation/dictionary.dart';
import 'translation/dictionary_translator.dart';
import 'translation/model_translator.dart';
import 'translation/on_device_backend.dart';
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
      // Order matters, because the first answer wins. Curated phrases first,
      // since they cover whole utterances nothing else can. Then the model,
      // which declines anything shorter than two words and anything the
      // dictionary cannot resolve to characters. The dictionary last, because
      // it always has an answer — a word-by-word gloss — so anything after it
      // would never be reached.
      //
      // On the web, and on a device that has not downloaded the weights, the
      // model declines everything and this is the pair it always was.
      home: ComposeScreen(
        translator: CompositeTranslator([
          const PhrasebookTranslator(),
          ModelTranslator(
            dictionary: Dictionary.bundled(),
            backend: onDeviceBackend(),
          ),
          DictionaryTranslator(Dictionary.bundled()),
        ]),
      ),
    );
  }
}
