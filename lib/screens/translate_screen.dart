import 'dart:async';

import 'package:flutter/material.dart';

import '../audio/speech.dart';
import '../pinyin/word.dart';
import '../translation/english_translator.dart';
import '../translation/model_asset.dart';
import '../translation/model_store.dart';
import '../translation/translator.dart';

/// Work out how to say something, starting from English.
///
/// The other way round from the compose screen, and a screen of its own rather
/// than a mode on it. The two share their data and nothing else: this one
/// takes ordinary Latin text, so it wants a plain text field — which brings
/// selection, copy and paste with it for free — where the compose screen wants
/// a keyboard that builds syllables. Finding a middle ground between the two
/// would make both worse.
///
/// Pops with the pinyin as [Word]s when the learner wants to practise it, so
/// the answer arrives in the input area as syllables rather than as text that
/// would have to be parsed back.
class TranslateScreen extends StatefulWidget {
  const TranslateScreen({
    super.key,
    required this.translator,
    this.phraseTranslator,
    this.modelStore,
    this.speech,
  });

  /// Answers a word, from local data, as fast as it can be typed: the
  /// hand-written phrases first, then CC-CEDICT inverted.
  final EnglishTranslator translator;

  /// Answers a sentence, and only when there is a model to answer it.
  ///
  /// Null where there is none, which is what the screen says: without it this
  /// is a word lookup, and saying so is better than declining sentences with
  /// no explanation.
  final EnglishTranslator? phraseTranslator;

  /// Whether the weights are actually there.
  ///
  /// Read only to get the explanation right, and it is worth the wiring: the
  /// model tier is always constructed and declines at run time, so a screen
  /// that went by whether it exists told every learner that sentences work,
  /// including the ones who have not downloaded 533MB. Null means the question
  /// cannot be asked, which is treated as no model.
  final ModelStore? modelStore;

  /// Says the answer aloud. Null where nothing can.
  final Speech? speech;

  @override
  State<TranslateScreen> createState() => _TranslateScreenState();
}

class _TranslateScreenState extends State<TranslateScreen> {
  final TextEditingController _english = TextEditingController();

  Said? _said;
  bool _thinking = false;

  /// Which candidate is selected, for the words where English is vaguer than
  /// Chinese. Reset whenever a new answer arrives.
  int _chosen = 0;

  Timer? _settling;

  /// Counts the asks so a slow answer to an earlier question cannot land on a
  /// later one. The model takes a second or two and English is typed quickly,
  /// so this happens whenever anyone changes their mind mid-word.
  int _asked = 0;

  bool _canSpeak = false;

  @override
  void initState() {
    super.initState();
    _english.addListener(_onTyped);
    widget.speech?.available().then((can) {
      if (mounted) setState(() => _canSpeak = can);
    });
  }

  @override
  void dispose() {
    _settling?.cancel();
    _english
      ..removeListener(_onTyped)
      ..dispose();
    super.dispose();
  }

  void _onTyped() {
    _settling?.cancel();
    final english = _english.text.trim();
    final asked = ++_asked;

    if (english.isEmpty) {
      setState(() {
        _said = null;
        _thinking = false;
        _chosen = 0;
      });
      return;
    }

    // The quick tier reads local data, so it answers as fast as anyone can
    // type and needs no debounce.
    widget.translator.say(english).then((said) {
      if (!mounted || asked != _asked) return;
      setState(() {
        _said = said;
        _chosen = 0;
      });
      // An entry beats a paraphrase of it, so the model is not asked about
      // English the dictionary already answered — the same hierarchy the
      // other direction settled over 缘分. It is asked about everything else,
      // once typing has stopped, because it costs a second of CPU and there
      // is no point spending it on half a sentence.
      if (said != null) {
        setState(() => _thinking = false);
        return;
      }
      final phrases = widget.phraseTranslator;
      if (phrases == null) return;
      _settling = Timer(_settle, () => _think(phrases, english, asked));
    });
  }

  /// Long enough that typing a sentence wakes the model once, not once a word.
  static const _settle = Duration(milliseconds: 700);

  Future<void> _think(
    EnglishTranslator phrases,
    String english,
    int asked,
  ) async {
    if (!mounted || asked != _asked) return;
    setState(() => _thinking = true);
    final said = await phrases.say(english);
    if (!mounted || asked != _asked) return;
    setState(() {
      _thinking = false;
      _said = said;
      _chosen = 0;
    });
  }

  Rendering? get _rendering {
    final said = _said;
    if (said == null) return null;
    return said.options[_chosen.clamp(0, said.options.length - 1)];
  }

  Future<void> _speak() async {
    final speech = widget.speech;
    final rendering = _rendering;
    if (speech == null || rendering == null) return;
    final said = await speech.speak(TranslationRequest(rendering.words));
    if (said || !mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        key: Key('no-audio'),
        content: Text('No audio for this one.'),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final store = widget.modelStore;
    if (store == null) return _body(context, hasModel: false);
    return ValueListenableBuilder<ModelStatus>(
      valueListenable: store.status,
      builder: (context, status, _) =>
          _body(context, hasModel: status.state == ModelState.ready),
    );
  }

  Widget _body(BuildContext context, {required bool hasModel}) {
    final theme = Theme.of(context);
    final said = _said;
    final rendering = _rendering;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Say it in Mandarin'),
        backgroundColor: theme.colorScheme.primaryContainer,
        actions: [
          if (_canSpeak)
            IconButton(
              key: const Key('speak'),
              onPressed: rendering == null ? null : _speak,
              icon: const Icon(Icons.volume_up_outlined),
              tooltip: 'Say it',
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          TextField(
            key: const Key('english'),
            controller: _english,
            autofocus: true,
            textCapitalization: TextCapitalization.sentences,
            // Plain English, so the platform keyboard does the work and
            // selection, copy and paste come with it.
            decoration: InputDecoration(
              labelText: 'English',
              hintText: hasModel
                  ? 'a word or a sentence'
                  : 'a word — tea, tomorrow, thank you',
              border: const OutlineInputBorder(),
              suffixIcon: _english.text.isEmpty
                  ? null
                  : IconButton(
                      key: const Key('clear-english'),
                      onPressed: _english.clear,
                      icon: const Icon(Icons.close),
                      tooltip: 'Clear',
                    ),
            ),
          ),
          const SizedBox(height: 24),
          if (said != null)
            _Answer(
              said: said,
              chosen: _chosen,
              onChoose: (index) => setState(() => _chosen = index),
              onPractise: () => Navigator.of(context).pop(rendering!.words),
            )
          else if (_thinking)
            Text(
              'working it out…',
              key: const Key('thinking'),
              style: theme.textTheme.titleMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            )
          else if (_english.text.trim().isNotEmpty)
            _Nothing(hasModel: hasModel)
          else
            _About(hasModel: hasModel),
        ],
      ),
    );
  }
}

/// The answer, and whatever is worth knowing about how it was arrived at.
class _Answer extends StatelessWidget {
  const _Answer({
    required this.said,
    required this.chosen,
    required this.onChoose,
    required this.onPractise,
  });

  final Said said;
  final int chosen;
  final ValueChanged<int> onChoose;
  final VoidCallback onPractise;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var index = 0; index < said.options.length; index++)
          _Option(
            rendering: said.options[index],
            selected: index == chosen,
            // One answer is not a choice, and a radio button beside it would
            // suggest there is something to decide.
            choosable: said.options.length > 1,
            onTap: () => onChoose(index),
          ),
        if (said.options.length > 1)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              'English is vaguer than Chinese here. Pick the one you mean.',
              key: const Key('ambiguous'),
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        if (said.phrasing == Phrasing.generated) ...[
          const SizedBox(height: 16),
          _Check(readsBackAs: said.readsBackAs),
        ],
        const SizedBox(height: 24),
        // The transfer the whole screen exists for: the answer goes into the
        // input area as syllables, where every gesture the keyboard offers
        // already works on it.
        FilledButton.icon(
          key: const Key('practise'),
          onPressed: onPractise,
          icon: const Icon(Icons.keyboard_return),
          label: const Text('Practise this'),
        ),
      ],
    );
  }
}

/// One way of saying it.
class _Option extends StatelessWidget {
  const _Option({
    required this.rendering,
    required this.selected,
    required this.choosable,
    required this.onTap,
  });

  final Rendering rendering;
  final bool selected;
  final bool choosable;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;

    return InkWell(
      onTap: choosable ? onTap : null,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (choosable)
              Padding(
                padding: const EdgeInsets.only(right: 8, top: 4),
                child: Icon(
                  selected
                      ? Icons.radio_button_checked
                      : Icons.radio_button_unchecked,
                  size: 20,
                  color: selected ? theme.colorScheme.primary : muted,
                ),
              ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Selectable, which is how the pinyin gets out of the app
                  // and into a message to somebody. The composed line cannot
                  // offer this — it is painted a syllable at a time so it can
                  // be tapped — and here there is no reason not to.
                  SelectableText(
                    rendering.written,
                    key: const Key('pinyin'),
                    // Its own tap handler, because a selectable text takes the
                    // gesture for itself: without this, tapping the pinyin of
                    // a candidate would do nothing, which is exactly where
                    // anybody would tap to choose it. A long press still
                    // selects the text.
                    onTap: choosable ? onTap : null,
                    style: theme.textTheme.headlineSmall?.copyWith(
                      color: selected && choosable
                          ? theme.colorScheme.primary
                          : theme.colorScheme.onSurface,
                    ),
                  ),
                  if (rendering.meaning case final meaning?)
                    Text(
                      meaning,
                      style: theme.textTheme.bodyMedium?.copyWith(color: muted),
                    ),
                  if (rendering.hskLevel case final level?)
                    Text(
                      'HSK $level',
                      style: theme.textTheme.labelSmall?.copyWith(color: muted),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The round trip, which is the only thing standing between a learner and a
/// fluent answer to the wrong question.
class _Check extends StatelessWidget {
  const _Check({required this.readsBackAs});

  final String? readsBackAs;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    final back = readsBackAs;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(right: 8, top: 2),
          child: Icon(Icons.autorenew, size: 16, color: muted),
        ),
        Expanded(
          child: Text(
            back == null
                ? 'Written by the model, and not checked back — compare it '
                      'with what you asked for.'
                : 'Reads back as: $back',
            key: const Key('reads-back'),
            style: theme.textTheme.bodyMedium?.copyWith(color: muted),
          ),
        ),
      ],
    );
  }
}

/// What to say when there is no answer.
class _Nothing extends StatelessWidget {
  const _Nothing({required this.hasModel});

  final bool hasModel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Text(
      hasModel
          ? 'Nothing for that. Try fewer words, or a plainer way of saying it.'
          : 'Nothing for that. Without the model this is a word lookup — try '
                'one word, or turn on whole phrases.',
      key: const Key('nothing'),
      style: theme.textTheme.bodyLarge?.copyWith(
        color: theme.colorScheme.onSurfaceVariant,
      ),
    );
  }
}

/// What this screen can and cannot do, said before it is asked.
class _About extends StatelessWidget {
  const _About({required this.hasModel});

  final bool hasModel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          hasModel
              ? 'Words come from the dictionary and sentences from the model. '
                    'Either way the tones come from the dictionary, so they '
                    'are right.'
              : 'Words come from the dictionary, read backwards. Turn on whole '
                    'phrases and this will do sentences too.',
          key: const Key('about'),
          style: theme.textTheme.bodyLarge?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 16),
        Text(
          'A dictionary read backwards has its limits: English is often '
          'vaguer than Chinese, so where there is more than one answer you '
          'will be asked which you meant.',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}
