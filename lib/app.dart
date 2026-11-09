import 'package:flutter/material.dart';

import 'audio/mandarin_speech.dart';
import 'audio/speech.dart';
import 'favourites/favourites.dart';
import 'favourites/stored_favourites.dart';
import 'screens/compose_screen.dart';
import 'theme.dart';
import 'translation/character_index.dart';
import 'translation/dictionary.dart';
import 'translation/dictionary_translator.dart';
import 'translation/english_dictionary_translator.dart';
import 'translation/english_index.dart';
import 'translation/english_model_translator.dart';
import 'translation/english_translator.dart';
import 'translation/example_index.dart';
import 'translation/model_store.dart';
import 'translation/model_translator.dart';
import 'translation/on_device_backend.dart';
import 'translation/phrasebook_translator.dart';
import 'translation/tone_suggestion.dart';
import 'translation/word_notes.dart';
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

  /// The one place a voice is named, as with the translators. Speech is not a
  /// tier of translation — it answers how the pinyin sounds, not what it means
  /// — so it is wired separately and fails separately.
  final Speech _speech = MandarinSpeech(Dictionary.bundled());

  /// Owned here, above both screens that save to it, so the star on one and
  /// the list reached from the other are the same list.
  final Favourites _favourites = StoredFavourites.preferences();

  @override
  void dispose() {
    _favourites.dispose();
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
        speech: _speech,
        favourites: _favourites,
        // A dictionary question, not a model's: it stays quiet on correct
        // pinyin because frequency data is not an opinion.
        suggester: DictionarySuggester(Dictionary.bundled()),
        translator: CompositeTranslator([
          const PhrasebookTranslator(),
          DictionaryTranslator(Dictionary.bundled()),
        ]),
        phraseTranslator: ModelTranslator(
          dictionary: Dictionary.bundled(),
          backend: onDeviceBackend(),
        ),
        // The same two tiers the other way round, and the same reasoning: a
        // word is the dictionary's job and a sentence is the model's. The
        // hand-written phrases go first here too, because inverting a
        // dictionary cannot answer "hello" — see `EnglishPhrasebook`.
        englishTranslator: CompositeEnglishTranslator([
          const EnglishPhrasebook(),
          EnglishDictionaryTranslator(
            index: EnglishIndex.bundled(),
            dictionary: Dictionary.bundled(),
            examples: ExampleIndex.bundled(),
            characters: CharacterIndex.bundled(),
            notes: WordNotes.bundled(),
          ),
        ]),
        englishPhraseTranslator: EnglishModelTranslator(
          characters: CharacterIndex.bundled(),
          backend: onDeviceBackend(),
          dictionary: Dictionary.bundled(),
        ),
      ),
    );
  }
}
