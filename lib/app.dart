import 'package:flutter/material.dart';

import 'screens/compose_screen.dart';
import 'theme.dart';
import 'translation/dictionary.dart';
import 'translation/dictionary_translator.dart';
import 'translation/model_store.dart';
import 'translation/model_translator.dart';
import 'translation/on_device_backend.dart';
import 'translation/phrasebook_translator.dart';
import 'translation/translator.dart';

class KouyuApp extends StatefulWidget {
  const KouyuApp({super.key});

  @override
  State<KouyuApp> createState() => _KouyuAppState();
}

class _KouyuAppState extends State<KouyuApp> {
  /// Owned here, above the screens, so a 533MB download is not cancelled by
  /// navigating away from the screen that started it.
  final ModelStore _modelStore = modelStore();

  @override
  void dispose() {
    _modelStore.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Kǒuyǔ',
      theme: kLightTheme,
      darkTheme: kDarkTheme,
      // The one place translation implementations are named. Everything below
      // here knows only the Translator interface.
      //
      // Two tiers, because they want opposite things.
      //
      // The quick one answers every keystroke, so it only reads local data:
      // curated phrases first, since they cover whole utterances nothing else
      // can, then the dictionary, which always has an answer.
      //
      // The considered one is asked once typing pauses, and is the only place
      // a model belongs — woken on every keystroke it would spend a second of
      // a phone's CPU translating a phrase nobody has finished writing. On the
      // web, and on a device without the weights, it declines everything and
      // the dictionary answers alone.
      home: ComposeScreen(
        modelStore: _modelStore,
        translator: CompositeTranslator([
          const PhrasebookTranslator(),
          DictionaryTranslator(Dictionary.bundled()),
        ]),
        phraseTranslator: ModelTranslator(
          dictionary: Dictionary.bundled(),
          backend: onDeviceBackend(),
        ),
      ),
    );
  }
}
