import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../audio/speech.dart';
import '../pinyin/composition.dart';
import '../pinyin/keyboard_layout.dart';
import '../translation/model_store.dart';
import '../translation/translator.dart';
import '../widgets/blinking_cursor.dart';
import '../widgets/pinyin_keyboard.dart';
import 'model_screen.dart';

/// Compose Mandarin as pinyin with tone marks, and see what it means.
///
/// The app's reason to exist: dictionary apps take pinyin but only a word at a
/// time, and translation apps take phrases but want Hanzi, so there is nowhere
/// to simply type `nǐ hǎo, shìjiè`. This screen is that missing box.
class ComposeScreen extends StatefulWidget {
  const ComposeScreen({
    super.key,
    required this.translator,
    required this.modelStore,
    this.phraseTranslator,
    this.speech,
  });

  /// Passed through to the model screen. Owned above this screen so a download
  /// carries on when the learner navigates away from it.
  final ModelStore modelStore;

  /// Supplied by the caller, and typed as the interface only, so this screen
  /// never names a translation implementation. Swapping in a real model is a
  /// change in `app.dart` and nowhere else.
  ///
  /// Answers on every keystroke, so it has to be quick: a dictionary, or
  /// anything else that reads local data.
  final Translator translator;

  /// Asked only once typing pauses, and allowed to take its time.
  ///
  /// Two tiers rather than one chain, because they want opposite things. Word
  /// meanings should appear as the syllable is committed, and a model should
  /// not be woken five times while a five-word phrase is typed — every one of
  /// those calls but the last is about a phrase nobody has finished writing,
  /// and on a phone each costs a second or two of CPU.
  ///
  /// Still just a [Translator]: this screen knows there is a considered tier,
  /// not what is in it. Null where there is none.
  final Translator? phraseTranslator;

  /// Says the pinyin aloud, on demand. Null where nothing can.
  final Speech? speech;

  @override
  State<ComposeScreen> createState() => _ComposeScreenState();
}

class _ComposeScreenState extends State<ComposeScreen> {
  Composition _composition = const Composition();

  /// The quick answer: word meanings, and set phrases the dictionary knows.
  Translation? _translation;

  /// The considered answer, when one has arrived for what is on screen now.
  Translation? _phrase;

  /// Whether a lookup has been running long enough to be worth mentioning.
  bool _lookingUp = false;
  Timer? _admitToLookingUp;

  /// Whether the considered tier is working on what is on screen.
  bool _thinking = false;
  Timer? _settle;

  /// How long typing must pause before the considered tier is asked.
  ///
  /// Long enough to sit between syllables of one word without firing, short
  /// enough not to feel like a wait once the phrase is done.
  static const _settleDelay = Duration(milliseconds: 600);

  /// How long a lookup may take before the screen says it is working.
  ///
  /// Deliberately longer than a lookup normally takes. Reading a dictionary
  /// shard costs 1-24ms from local assets, and flashing a message for 24ms is
  /// worse than saying nothing. Over the web the same shard is an HTTP fetch,
  /// which has no upper bound — that is the case this exists for.
  static const _worthMentioning = Duration(milliseconds: 250);

  /// Whether this device has a Mandarin voice, once asked.
  ///
  /// Null until the answer arrives, and the control stays hidden until then —
  /// it appears at most once, rather than flickering in and out.
  bool _canSpeak = false;

  /// Which initial-bank arrangement is in use, switchable from the app bar.
  ///
  /// QWERTY by default: it is what most hands already know, and its three rows
  /// fit a landscape phone, where articulation order's seven shorter rows have
  /// to scroll.
  KeyArrangement _arrangement = KeyArrangement.qwerty;

  @override
  void initState() {
    super.initState();
    _askAboutSpeech();
  }

  Future<void> _askAboutSpeech() async {
    final speech = widget.speech;
    if (speech == null) return;
    final can = await speech.available();
    if (!mounted || !can) return;
    setState(() => _canSpeak = true);
  }

  void _edit(Composition next) {
    // Whatever is being said is about the text as it was, so it is now wrong.
    widget.speech?.stop();
    setState(() => _composition = next);
    _translate(next);
  }

  /// Speaks what has been typed, on the learner's say-so and never otherwise.
  ///
  /// Deliberately manual. Speaking as the line grows would say a fragment of
  /// a sentence after every syllable, which is both unusable and the fastest
  /// way to make someone put the phone down.
  Future<void> _speak() async {
    final speech = widget.speech;
    if (speech == null) return;
    final said = await speech.speak(TranslationRequest(_composition.words));
    if (said || !mounted) return;
    // A button that appears to do nothing is worse than one that explains.
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        key: Key('no-audio'),
        content: Text(
          'No audio for this — a word here is not in the dictionary.',
        ),
      ),
    );
  }

  @override
  void dispose() {
    _admitToLookingUp?.cancel();
    _settle?.cancel();
    super.dispose();
  }

  Future<void> _translate(Composition composition) async {
    final request = TranslationRequest(composition.words);
    _admitToLookingUp?.cancel();
    _settle?.cancel();

    if (request.isEmpty) {
      setState(() {
        _translation = null;
        _phrase = null;
        _lookingUp = false;
        _thinking = false;
      });
      return;
    }

    // Any edit invalidates the considered answer: it was about different words.
    setState(() {
      _phrase = null;
      _thinking = false;
    });
    _schedulePhrase(composition);

    _admitToLookingUp = Timer(_worthMentioning, () {
      if (mounted && _composition.text == composition.text) {
        setState(() => _lookingUp = true);
      }
    });

    final result = await widget.translator.translate(request);
    _admitToLookingUp?.cancel();
    if (!mounted) return;
    // A slower earlier lookup must not overwrite a newer one.
    if (_composition.text != composition.text) return;
    setState(() {
      _translation = result;
      _lookingUp = false;
    });
  }

  void _schedulePhrase(Composition composition) {
    final translator = widget.phraseTranslator;
    if (translator == null) return;
    // One word is a dictionary's job, and asking a model would only invite it
    // to sound certain about a syllable forty words share.
    if (TranslationRequest(composition.words).wordKeys.length < 2) return;

    _settle = Timer(_settleDelay, () async {
      if (!mounted || _composition.text != composition.text) return;
      setState(() => _thinking = true);
      final result = await translator.translate(
        TranslationRequest(composition.words),
      );
      if (!mounted || _composition.text != composition.text) return;
      setState(() {
        _phrase = result;
        _thinking = false;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Kǒuyǔ'),
        backgroundColor: theme.colorScheme.primaryContainer,
        actions: [
          IconButton(
            key: const Key('arrangement'),
            onPressed: () => setState(() {
              _arrangement = _arrangement == KeyArrangement.articulatory
                  ? KeyArrangement.qwerty
                  : KeyArrangement.articulatory;
            }),
            icon: const Icon(Icons.keyboard_outlined),
            tooltip: switch (_arrangement) {
              KeyArrangement.articulatory => 'Switch to QWERTY order',
              KeyArrangement.qwerty => 'Switch to articulation order',
            },
          ),
          if (_canSpeak)
            IconButton(
              key: const Key('speak'),
              // Nothing committed means nothing to say: a lone draft syllable
              // has no tone yet, so it is not a syllable anyone can pronounce.
              onPressed: _composition.text.isEmpty ? null : _speak,
              icon: const Icon(Icons.volume_up_outlined),
              tooltip: 'Say it',
            ),
          IconButton(
            key: const Key('model'),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (context) => ModelScreen(store: widget.modelStore),
              ),
            ),
            icon: const Icon(Icons.auto_awesome_outlined),
            tooltip: 'Whole phrases',
          ),
          // CC-CEDICT asks for attribution under CC BY-SA 4.0. This is it.
          IconButton(
            key: const Key('credits'),
            onPressed: () => showAboutDialog(
              context: context,
              applicationName: 'Kǒuyǔ',
              children: const [
                Text(
                  'Word meanings come from CC-CEDICT, a community maintained '
                  'free Chinese-English dictionary published by MDBG.\n\n'
                  'Used under the Creative Commons Attribution-ShareAlike 4.0 '
                  'International licence.\n'
                  'https://creativecommons.org/licenses/by-sa/4.0/\n\n'
                  'Word frequency and HSK levels from '
                  'complete-hsk-vocabulary, copyright Yanis Zafirópulos, used '
                  'under the MIT licence.',
                ),
              ],
            ),
            icon: const Icon(Icons.info_outline),
            tooltip: 'Credits',
          ),
          // Away from the thumb: rare, and it throws away everything typed.
          IconButton(
            key: const Key('clear'),
            onPressed: _composition.isEmpty
                ? null
                : () => _edit(_composition.cleared()),
            icon: const Icon(Icons.clear_all),
            tooltip: 'Clear',
          ),
        ],
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final landscape = constraints.maxWidth > constraints.maxHeight;
          final reading = _Reading(
            composition: _composition,
            translation: _translation,
            phrase: _phrase,
            lookingUp: _lookingUp,
            thinking: _thinking,
          );
          // The keyboard's height now follows the stage on show rather than a
          // fixed fraction, which is safe because it is anchored to the far
          // edge: text appearing in the reading area cannot move it, since the
          // reading area takes what is left rather than the other way round.
          final keyboard = PinyinKeyboard(
            fillHeight: landscape,
            arrangement: _arrangement,
            draft: _composition.draft,
            onInitial: (initial) => _edit(_composition.withInitial(initial)),
            onRime: (rime) => _edit(_composition.withRime(rime)),
            onTone: (tone) => _edit(_composition.commit(tone)),
            onBackTo: (stage) => _edit(_composition.backTo(stage)),
            onSpace: () => _edit(_composition.space()),
            onBackspace: () => _edit(_composition.backspace()),
          );

          if (landscape) {
            return Row(
              children: [
                Expanded(child: reading),
                SizedBox(width: _panelWidth(constraints), child: keyboard),
              ],
            );
          }
          return Column(
            children: [
              Expanded(child: reading),
              // Capped so a tall bank cannot squeeze the reading area away; it
              // scrolls beyond this.
              ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: constraints.maxHeight * 0.75,
                ),
                child: keyboard,
              ),
            ],
          );
        },
      ),
    );
  }
}

/// How wide the landscape side panel needs to be.
///
/// A quarter of the screen is the aim, but the widest bank sets a floor: a ten
/// column row squeezed into 25% of a landscape phone gives 13pt keys, which is
/// not a keyboard. So it takes the wider of the two, capped so the panel can
/// never take more than half the screen.
double _panelWidth(BoxConstraints constraints) {
  const minimumKeyWidth = 28.0;
  const gap = 6.0;
  const padding = 24.0;

  // The widest row of any arrangement, not just the one on show, so switching
  // arrangement never resizes the panel and shifts everything in it.
  final columns = [
    for (final arrangement in KeyArrangement.values)
      for (final row in initialRows(arrangement)) row.length,
  ].reduce(math.max);
  final needed = columns * minimumKeyWidth + (columns - 1) * gap + padding;

  return math
      .max(constraints.maxWidth * 0.25, needed)
      .clamp(0.0, constraints.maxWidth * 0.5);
}

/// What has been typed, and what it means.
class _Reading extends StatelessWidget {
  const _Reading({
    required this.composition,
    required this.translation,
    required this.phrase,
    required this.lookingUp,
    required this.thinking,
  });

  final Composition composition;

  /// The quick answer.
  final Translation? translation;

  /// The considered answer, if one has arrived.
  final Translation? phrase;

  final bool lookingUp;
  final bool thinking;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final quick = translation;
    final whole = phrase;

    // The parts come from whichever answer knows them. Both fill them in, and
    // the quick one offers several candidates per word where the pinyin is
    // ambiguous, so it is preferred.
    final parts = quick?.words.isNotEmpty ?? false
        ? quick!.words
        : whole?.words ?? const <WordGloss>[];

    // A word-by-word answer has no headline: the list is the answer, and
    // joining it into a sentence is exactly the misreading to avoid.
    final headline =
        whole?.text ?? (quick?.wordByWord ?? false ? null : quick?.text);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Keyed off the preview, not off whether anything has been chosen: the
          // vowel keys spell nothing on their own, so choosing `a` used to
          // blank this area instead of leaving the prompt up.
          if (composition.preview.isEmpty)
            Text(
              'Your pinyin appears here',
              style: theme.textTheme.titleMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            )
          else
            Text.rich(
              key: const Key('composed'),
              TextSpan(
                children: [
                  TextSpan(text: composition.text),
                  // The draft is dimmed: it has no tone yet, so it is not yet
                  // a syllable anyone should read aloud.
                  TextSpan(
                    text: composition.draftSuffix,
                    style: TextStyle(
                      color: theme.colorScheme.onSurfaceVariant.withValues(
                        alpha: 0.55,
                      ),
                    ),
                  ),
                  // The space a pending word break stands for, which the text
                  // itself does not carry.
                  if (composition.hasPendingWordBreak)
                    const TextSpan(text: ' '),
                  WidgetSpan(
                    alignment: PlaceholderAlignment.middle,
                    child: BlinkingCursor(
                      height: theme.textTheme.displaySmall?.fontSize ?? 36,
                    ),
                  ),
                ],
              ),
              style: theme.textTheme.displaySmall,
            ),
          // Plain text, not a spinner. An indeterminate spinner never stops
          // animating, and for something that usually takes under 25ms the
          // motion would be the only thing anyone noticed.
          if (lookingUp && quick == null) ...[
            const SizedBox(height: 20),
            Text(
              'looking it up…',
              key: const Key('looking-up'),
              style: theme.textTheme.titleMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
          if (headline != null) ...[
            const SizedBox(height: 20),
            Text(
              headline,
              key: const Key('headline'),
              style: theme.textTheme.titleLarge?.copyWith(
                color: theme.colorScheme.primary,
              ),
            ),
          ],
          // Say what kind of answer this is. "word by word" is dropped once
          // the parts are a list, because a list of words says so itself.
          if (_label(quick, whole) case final label?) ...[
            Text(
              label,
              key: const Key('answer-kind'),
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
          if ((whole?.hskLevel ?? quick?.hskLevel) case final band?)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                'HSK $band',
                key: const Key('hsk-level'),
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          // A spinner is warranted here, unlike for a dictionary read: a model
          // on a phone takes a second or two, and nothing else on screen
          // changes while it does.
          if (thinking) ...[
            const SizedBox(height: 20),
            Row(
              key: const Key('thinking'),
              children: [
                SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(width: 10),
                // Expanded so it wraps rather than overflowing: the spinner
                // plus this line is 60pt wider than a 375pt screen allows.
                Expanded(
                  child: Text(
                    'translating the whole phrase…',
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
          ],
          if (parts.isNotEmpty) ...[
            const SizedBox(height: 20),
            // Under a phrase translation these are the components it was built
            // from; on their own they are the answer.
            if (headline != null)
              Text(
                'word by word',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            _Words(key: const Key('word-list'), words: parts),
          ],
        ],
      ),
    );
  }

  /// The qualifications worth putting under an answer, or null for none.
  static String? _label(Translation? quick, Translation? whole) {
    // Homophone ambiguity is the quick tier's to report: it is the one that
    // looked several words up.
    final uncertain = quick?.uncertain ?? false;
    if (!uncertain) return null;
    return whole == null
        ? 'several words sound like this'
        : 'some of these words sound like other words';
  }
}

/// One word per line, so a word-by-word answer cannot be read as a sentence.
class _Words extends StatelessWidget {
  const _Words({super.key, required this.words});

  final List<WordGloss> words;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final word in words)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 2, right: 8),
                  child: Text(
                    '\u2022',
                    style: theme.textTheme.bodyLarge?.copyWith(color: muted),
                  ),
                ),
                // The pinyin the learner typed, so a line can be matched to
                // the syllables it came from.
                Text(
                  word.pinyin,
                  style: theme.textTheme.bodyLarge?.copyWith(
                    color: theme.colorScheme.primary,
                  ),
                ),
                Text('  ', style: theme.textTheme.bodyLarge),
                // Wraps rather than truncates: an ambiguous syllable offers
                // three candidates and they are the whole point of the line.
                Expanded(
                  child: Text(
                    word.english,
                    style: theme.textTheme.bodyLarge?.copyWith(color: muted),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
