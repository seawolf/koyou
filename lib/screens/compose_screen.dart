import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';

import '../audio/speech.dart';
import '../pinyin/composition.dart';
import '../pinyin/keyboard_layout.dart';
import '../pinyin/word.dart';
import '../translation/english_translator.dart';
import '../translation/model_store.dart';
import '../translation/tone_suggestion.dart';
import '../translation/translator.dart';
import '../widgets/blinking_cursor.dart';
import '../widgets/pinyin_keyboard.dart';
import 'model_screen.dart';
import 'translate_screen.dart';

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
    this.englishTranslator,
    this.englishPhraseTranslator,
    this.speech,
    this.suggester,
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

  /// Answers the other direction, on its own screen: English in, pinyin out.
  ///
  /// Null leaves the screen unreachable and its button off the app bar, which
  /// is what the widget tests of this screen get — they are about composing,
  /// and a translator they never use would be a fixture to maintain.
  final EnglishTranslator? englishTranslator;

  /// The model tier of that screen, passed straight through. Null where there
  /// is none, and the screen then says it does words only.
  final EnglishTranslator? englishPhraseTranslator;

  /// Says the pinyin aloud, on demand. Null where nothing can.
  final Speech? speech;

  /// Notices a mistyped tone. Asked on every edit, because it is a handful
  /// of dictionary lookups rather than anything that needs thinking about.
  final Suggester? suggester;

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

  /// A tone that looks like a slip, if one does.
  ToneSuggestion? _suggestion;

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

  /// Opens the small editor for a word that is not Mandarin.
  ///
  /// A dialog rather than another bank of keys, and deliberately a modal one:
  /// this is the one place the app hands over to the phone's own keyboard,
  /// because a name is arbitrary letters with capitals in it and that is what
  /// a phone keyboard is for. Everything about pinyin stays on the app's
  /// keyboard, which is the whole premise.
  ///
  /// [existing] is the name already there when an existing one was tapped, so
  /// correcting `Steve` opens with `Steve` in the field rather than blank.
  Future<void> _askForWord({Caret? at, String existing = ''}) async {
    final typed = await showDialog<String>(
      context: context,
      builder: (context) => _WordDialog(existing: existing),
    );
    if (typed == null || !mounted) return;
    final moved = at == null ? _composition : _composition.movedTo(at);
    _edit(moved.withLiteral(typed));
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
        _suggestion = null;
        _lookingUp = false;
        _thinking = false;
      });
      return;
    }

    _suggest(composition, request);

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

  /// Whether the quick tier matched everything typed as a single entry.
  ///
  /// Set by whoever answered rather than deduced here: a curated phrase and a
  /// dictionary entry covering the whole line are both exact, and both better
  /// than a paraphrase assembled from per-word guesses. False for a
  /// word-by-word gloss, which is precisely where a model earns its place.
  bool get _dictionaryHasTheWhole => _translation?.matchedWhole ?? false;

  Future<void> _suggest(
    Composition composition,
    TranslationRequest request,
  ) async {
    final suggester = widget.suggester;
    if (suggester == null) return;
    final found = await suggester.check(request);
    if (!mounted || _composition.text != composition.text) return;
    setState(() => _suggestion = found);
  }

  void _schedulePhrase(Composition composition) {
    final translator = widget.phraseTranslator;
    if (translator == null) return;
    // One word is a dictionary's job, and asking a model would only invite it
    // to sound certain about a syllable forty words share.
    if (composition.words.where((word) => !word.isEmpty).length < 2) return;

    _settle = Timer(_settleDelay, () async {
      if (!mounted || _composition.text != composition.text) return;
      // The model is for what a dictionary cannot do. Where the dictionary has
      // matched the whole line as one entry there is nothing left to ask, and
      // asking anyway makes it worse: the model is handed one character per
      // word, so `yuán fèn` reaches it as 元份 — not a word — and its
      // paraphrase displaced 缘分, "fate or chance that brings people
      // together", which the dictionary had already found. A second of a
      // phone's CPU saved, as well.
      if (_dictionaryHasTheWhole) return;
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

  /// Opens the other direction, and takes whatever comes back.
  ///
  /// Seeded with the meaning already on screen, so the two directions join up:
  /// from `nǐ hǎo` glossed "hello" the box opens on "hello", ready to be
  /// edited into the thing actually wanted. It arrives selected, and nothing
  /// is looked up until it is asked for, so a seed nobody wants costs one
  /// keystroke. Not every answer is worth carrying — see [seedFrom].
  ///
  /// The answer comes back as words rather than text, so it lands in the line
  /// already broken into syllables — ready to be retoned, corrected or spoken,
  /// with nothing to parse.
  Future<void> _startFromEnglish(EnglishTranslator english) async {
    final words = await Navigator.of(context).push<List<Word>>(
      MaterialPageRoute<List<Word>>(
        builder: (context) => TranslateScreen(
          translator: english,
          phraseTranslator: widget.englishPhraseTranslator,
          modelStore: widget.modelStore,
          speech: widget.speech,
          initial: seedFrom(_translation, _phrase),
        ),
      ),
    );
    if (words == null || !mounted) return;
    _edit(Composition.of(words));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Kǒuyǔ'),
        backgroundColor: theme.colorScheme.primaryContainer,
        // Four, which is what Material 3 allows a top app bar, and grouped
        // by how often each is wanted. Speaking and translating happen once a
        // line; the three behind ⋮ are set-up — a layout preference, a 533MB
        // download, and the credits — and belong out of the way rather than
        // competing with them. Clearing stays last, on its own, furthest from
        // the thumb.
        actions: [
          if (_canSpeak)
            IconButton(
              key: const Key('speak'),
              // Nothing committed means nothing to say: a lone draft syllable
              // has no tone yet, so it is not a syllable anyone can pronounce.
              onPressed: _composition.text.isEmpty ? null : _speak,
              icon: const Icon(Icons.volume_up_outlined),
              tooltip: 'Say it',
            ),
          if (widget.englishTranslator case final english?)
            IconButton(
              key: const Key('translate'),
              onPressed: () => _startFromEnglish(english),
              // The standard glyph for it, and the one Material names
              // `translate`: there is no arguing with a convention this
              // settled.
              icon: const Icon(Icons.translate),
              tooltip: 'Translate into pinyin',
            ),
          MenuAnchor(
            key: const Key('more'),
            builder: (context, controller, _) => IconButton(
              key: const Key('more-button'),
              onPressed: () =>
                  controller.isOpen ? controller.close() : controller.open(),
              icon: const Icon(Icons.more_vert),
              tooltip: 'More',
            ),
            menuChildren: [
              MenuItemButton(
                key: const Key('model'),
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (context) => ModelScreen(store: widget.modelStore),
                  ),
                ),
                leadingIcon: const Icon(Icons.auto_awesome_outlined),
                child: const Text('Whole phrases'),
              ),
              MenuItemButton(
                key: const Key('arrangement'),
                onPressed: () => setState(() {
                  _arrangement = _arrangement == KeyArrangement.articulatory
                      ? KeyArrangement.qwerty
                      : KeyArrangement.articulatory;
                }),
                // Not a keyboard glyph: on every platform that means "show the
                // keyboard", and this does not show anything — it swaps one
                // arrangement for the other.
                leadingIcon: const Icon(Icons.swap_horiz),
                // Named as the act, not the state: a menu lists things to
                // do, and "Articulation order" on its own could as easily be
                // the setting you are already on.
                child: Text(switch (_arrangement) {
                  KeyArrangement.articulatory => 'Switch to QWERTY',
                  KeyArrangement.qwerty => 'Switch to articulation',
                }),
              ),
              // CC-CEDICT asks for attribution under CC BY-SA 4.0. This is it.
              MenuItemButton(
                key: const Key('credits'),
                onPressed: () => showAboutDialog(
                  context: context,
                  applicationName: 'Kǒuyǔ',
                  // Folded away rather than listed. There is more worth saying
                  // than fits a dialog, and a wall of it is read by nobody —
                  // so the hints and the licences each sit behind their own
                  // heading.
                  children: const [_Sections()],
                ),
                leadingIcon: const Icon(Icons.info_outline),
                child: const Text('Hints and credits'),
              ),
            ],
          ),
          // Away from the thumb: rare, and it throws away everything typed.
          IconButton(
            key: const Key('clear'),
            onPressed: _composition.isEmpty
                ? null
                : () => _edit(_composition.cleared()),
            // `clear_all` is drawn as a stack of lines, which reads as a
            // list or a menu rather than as throwing anything away. This is a
            // reset: everything typed goes and the line starts again.
            icon: const Icon(Icons.restart_alt),
            tooltip: 'Start again',
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
            onMoveCaret: (caret) => _edit(_composition.movedTo(caret)),
            onReopen: (word, syllable, stage) =>
                _edit(_composition.redraft(word, syllable, stage)),
            onEditLiteral: (word, text) => _askForWord(
              at: Caret(word: word, syllable: 0),
              existing: text,
            ),
            suggestion: _suggestion,
            onAccept: (suggestion) => _edit(
              _composition.retoned(
                suggestion.word,
                suggestion.syllable,
                suggestion.tone,
              ),
            ),
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
            onAddWord: _askForWord,
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

/// Whichever answer stands as the meaning of everything typed, or null where
/// none does.
///
/// An exact match for the whole line beats a model's paraphrase of it, so a
/// late answer about words the dictionary already knew cannot displace them —
/// see `_dictionaryHasTheWhole`.
///
/// A word-by-word answer is not one of these: the list is the answer, and
/// joining it into a sentence is exactly the misreading to avoid.
Translation? meaningOf(Translation? quick, Translation? whole) =>
    (quick?.matchedWhole ?? false) ? quick : whole;

/// The meaning as something worth asking to have translated back, or null.
///
/// Stricter than [meaningOf], and it has to be. `nǐ` on its own is answered
/// "you / doubtful / you (used to address a deity)" — three candidates, which
/// is the honest answer to an ambiguous syllable and is not a sentence anybody
/// would type into a translator. Only an answer the dictionary was sure of, or
/// one a model wrote, is worth carrying to the other screen.
String? seedFrom(Translation? quick, Translation? whole) {
  final meaning = meaningOf(quick, whole);
  if (meaning == null || meaning.uncertain) return null;
  return meaning.text;
}

/// What has been typed, and what it means.
class _Reading extends StatelessWidget {
  const _Reading({
    required this.composition,
    required this.translation,
    required this.phrase,
    required this.lookingUp,
    required this.thinking,
    required this.onMoveCaret,
    required this.onEditLiteral,
    required this.onReopen,
    required this.suggestion,
    required this.onAccept,
  });

  final Composition composition;

  /// The quick answer.
  final Translation? translation;

  /// The considered answer, if one has arrived.
  final Translation? phrase;

  final bool lookingUp;
  final bool thinking;

  final ValueChanged<Caret> onMoveCaret;
  final void Function(int word, String text) onEditLiteral;
  final void Function(int word, int syllable, ComposeStage stage) onReopen;

  final ToneSuggestion? suggestion;
  final ValueChanged<ToneSuggestion> onAccept;

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

    // An exact match for the whole line beats a model's paraphrase of it, so
    // a late answer about words the dictionary already knew cannot displace
    // them — see `_dictionaryHasTheWhole`.
    //
    // A word-by-word answer has no headline: the list is the answer, and
    // joining it into a sentence is exactly the misreading to avoid.
    final exact = quick?.matchedWhole ?? false;
    final headline = exact ? quick!.text : whole?.text;

    return SingleChildScrollView(
      // Horizontal padding is applied per child rather than here, so the
      // composed line can run edge to edge: its tap area has to include the
      // margin beside the text, or reaching the start of the line means
      // hitting the left half of one 18pt syllable.
      padding: const EdgeInsets.symmetric(vertical: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Nothing stands in for an empty line. "Your pinyin appears here"
          // said the same thing as "Start a syllable" directly above the keys,
          // and the keyboard's own prompt is where someone about to type is
          // already looking.
          //
          // Still keyed off the preview rather than off whether anything has
          // been chosen: the vowel keys spell nothing on their own, so
          // choosing `a` would otherwise blank the line it is building.
          if (composition.preview.isNotEmpty)
            _ComposedLine(
              composition: composition,
              onMoveCaret: onMoveCaret,
              onEditLiteral: onEditLiteral,
              onReopen: onReopen,
            ),
          _Rest(
            children: [
              // Directly under the line it is about, and above the meaning:
              // if the tone is wrong, the meaning below is answering the
              // wrong question.
              if (suggestion case final suggestion?)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: _Suggestion(
                    suggestion: suggestion,
                    onAccept: () => onAccept(suggestion),
                  ),
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

/// The composed line, with a caret in it that can be moved by tapping.
///
/// One paragraph rather than a row of separate widgets, so the text kerns,
/// wraps and aligns as text — and so the whole line stays readable as a single
/// [Text] to anything that wants to read it. The taps therefore hang off the
/// spans, which means gesture recognizers, which means this has to be
/// stateful: a recognizer outlives a build and has to be disposed.
class _ComposedLine extends StatefulWidget {
  const _ComposedLine({
    required this.composition,
    required this.onMoveCaret,
    required this.onEditLiteral,
    required this.onReopen,
  });

  final Composition composition;
  final ValueChanged<Caret> onMoveCaret;

  /// Asked to reopen the editor on the name at this word index.
  final void Function(int word, String text) onEditLiteral;

  /// Asked to lift a committed syllable back into the draft, at a stage.
  final void Function(int word, int syllable, ComposeStage stage) onReopen;

  @override
  State<_ComposedLine> createState() => _ComposedLineState();
}

class _ComposedLineState extends State<_ComposedLine> {
  /// Where each unit of the line sits in the paragraph's own text, so a touch
  /// can be turned into "which syllable".
  final List<_Unit> _units = [];

  /// The paragraph itself, for turning a point into a text position. It knows
  /// about wrapping; arithmetic over glyph widths does not.
  final GlobalKey _paragraph = GlobalKey();

  /// The last tap, for spotting a second one on the same syllable.
  ///
  /// Timed off the frame clock rather than the wall clock: it is monotonic,
  /// and it is the one a test can advance, so the window below is something
  /// that can actually be checked rather than asserted.
  _Unit? _lastTapped;
  Duration _lastTapAt = Duration.zero;

  /// A second tap on the same syllable reopens its tone.
  ///
  /// Done by hand rather than with `onDoubleTap`, which would put every single
  /// tap behind the double-tap timeout — and placing the caret is the commonest
  /// thing anyone does here. So the first tap moves the caret at once, and a
  /// second one within the window supersedes it. Nothing is ever waited for.
  static const _secondTapWindow = Duration(milliseconds: 300);

  /// The paragraph that actually holds the glyphs.
  ///
  /// Not simply what the key finds: a [Text] wraps its paragraph in a
  /// semantics node, which is a render object too, so asking the key directly
  /// hands back something that cannot answer where a touch landed — and every
  /// tap then looked like a miss and snapped to the end of the line.
  RenderParagraph? get _rendered {
    RenderParagraph? found;
    void search(RenderObject object) {
      if (found != null) return;
      if (object is RenderParagraph) {
        found = object;
        return;
      }
      object.visitChildren(search);
    }

    final root = _paragraph.currentContext?.findRenderObject();
    if (root != null) search(root);
    return found;
  }

  /// The unit under [local], or null where the touch missed the text.
  _Unit? _unitAt(Offset local) {
    final paragraph = _rendered;
    if (paragraph == null) return null;
    if (!(Offset.zero & paragraph.size).contains(local)) return null;

    final position = paragraph.getPositionForOffset(local);
    for (final unit in _units) {
      // Inclusive of the end: a touch on the right half of a unit's last
      // character reports the position *after* it, which is still that unit
      // being touched. Excluding it sent every such tap to the margin, and
      // the caret to the end of the line.
      //
      // Where two units meet inside a word the first wins, which is the same
      // place either way: after this one is before the next.
      if (position.offset >= unit.start && position.offset <= unit.end) {
        return unit;
      }
    }
    return null;
  }

  /// [global] in the paragraph's own coordinates.
  Offset? _local(Offset global) => _rendered?.globalToLocal(global);

  void _onTap(Offset global) {
    final local = _local(global);
    if (local == null) return;
    final unit = _unitAt(local);

    if (unit == null) {
      // Beside the line, or above or below it: snap to whichever end is
      // nearer rather than doing nothing, since the glyphs are a thin target.
      widget.onMoveCaret(
        local.dx < 0
            ? const Caret(word: 0, syllable: 0)
            : widget.composition.end,
      );
      return;
    }
    if (unit.literal != null) {
      // A name is one thing, and tapping it asks to correct it rather than to
      // put a caret somewhere inside it.
      widget.onEditLiteral(unit.word, unit.literal!);
      return;
    }

    // The *system* timestamp: the other one asserts when read outside a frame,
    // and a gesture callback is exactly that. It threw silently and the caret
    // stopped moving at all.
    final now = SchedulerBinding.instance.currentSystemFrameTimeStamp;
    final again = _lastTapped == unit && now - _lastTapAt < _secondTapWindow;
    _lastTapped = unit;
    _lastTapAt = now;
    if (again) {
      _lastTapped = null;
      widget.onReopen(unit.word, unit.index, ComposeStage.tone);
      return;
    }

    // Before or after, as in any other text field. Measured in characters
    // rather than pixels, because the paragraph has already done the hard part
    // of deciding which line and which glyph was hit.
    final position = _rendered?.getPositionForOffset(local);
    final middle = unit.start + (unit.end - unit.start) / 2;
    final before = (position?.offset ?? unit.start) < middle;
    widget.onMoveCaret(
      Caret(word: unit.word, syllable: before ? unit.index : unit.index + 1),
    );
  }

  void _onLongPress(Offset global) {
    final local = _local(global);
    if (local == null) return;
    final unit = _unitAt(local);
    if (unit == null || unit.literal != null) return;
    // Held, rather than tapped twice: going back further is the rarer fix.
    widget.onReopen(unit.word, unit.index, ComposeStage.rime);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final style = theme.textTheme.displaySmall;
    final composition = widget.composition;
    _units.clear();

    final spans = <InlineSpan>[];
    var characters = 0;
    var anythingBefore = false;

    void add(InlineSpan span, String text) {
      spans.add(span);
      characters += text.length;
    }

    void addCaret() {
      add(
        TextSpan(
          text: composition.draftSuffix,
          // The draft is dimmed: it has no tone yet, so it is not yet a
          // syllable anyone should read aloud.
          style: TextStyle(
            color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.55),
          ),
        ),
        composition.draftSuffix,
      );
      // A placeholder is one character of the paragraph's text, so it has to
      // be counted or every offset after the caret is wrong.
      add(
        WidgetSpan(
          alignment: PlaceholderAlignment.middle,
          child: BlinkingCursor(height: style?.fontSize ?? 36),
        ),
        '￼',
      );
    }

    for (var word = 0; word < composition.words.length; word++) {
      final here = composition.words[word];
      // An empty word still renders something if the caret is sitting in it —
      // the draft, or the caret alone — and it still needs the space that
      // separates it from the word before. Without this the space after a
      // word break was invisible, and `wǒài` looked like `wǒ ài`.
      final visible = !here.isEmpty || composition.caret.word == word;
      if (anythingBefore && visible) add(const TextSpan(text: ' '), ' ');
      // Only words that actually put something on screen count as text before.
      // A word holding nothing but the caret — what backspacing the first
      // syllable of a line leaves — must not put a space in front of the word
      // after it. A draft is different: lifting a syllable back out to retone
      // it leaves its word empty, and the draft standing in its place is very
      // much text.
      final drafting =
          composition.caret.word == word && composition.draftSuffix.isNotEmpty;
      if (!here.isEmpty || drafting) anythingBefore = true;

      for (var index = 0; index <= here.length; index++) {
        if (composition.caret.word == word &&
            composition.caret.syllable == index) {
          addCaret();
        }
        if (index == here.length) break;

        final start = characters;
        switch (here) {
          case Literal():
            // Shown in the same size but not as pinyin: it has no tones and is
            // not something to pronounce syllable by syllable.
            add(
              TextSpan(
                text: here.text,
                style: TextStyle(
                  color: theme.colorScheme.tertiary,
                  fontStyle: FontStyle.italic,
                ),
              ),
              here.text,
            );
            _units.add(
              _Unit(
                word: word,
                index: index,
                start: start,
                end: characters,
                literal: here.text,
              ),
            );
          case Spoken():
            final written = here.syllables[index].written;
            add(TextSpan(text: written), written);
            _units.add(
              _Unit(word: word, index: index, start: start, end: characters),
            );
        }
      }
    }

    return GestureDetector(
      key: const Key('composed-margin'),
      behavior: HitTestBehavior.opaque,
      onTapUp: (details) => _onTap(details.globalPosition),
      onLongPressStart: (details) => _onLongPress(details.globalPosition),
      child: Padding(
        // Vertical room so a tap a little above or below the text still
        // counts, and the horizontal margin the rest of the reading area has,
        // here as part of the tappable band rather than outside it.
        padding: _sides + const EdgeInsets.symmetric(vertical: 10),
        // A widget takes one key, and two things need one: the paragraph has
        // to be findable to be asked where a touch landed, and the line is
        // read back by its own key elsewhere. KeyedSubtree has no render
        // object of its own, so finding one through it lands on the paragraph.
        child: KeyedSubtree(
          key: _paragraph,
          child: Text.rich(
            key: const Key('composed'),
            TextSpan(children: spans),
            style: style,
          ),
        ),
      ),
    );
  }
}

/// One tappable piece of the line, and where it sits in the paragraph's text.
class _Unit {
  const _Unit({
    required this.word,
    required this.index,
    required this.start,
    required this.end,
    this.literal,
  });

  final int word;
  final int index;

  /// Character range within the paragraph, which is what a hit test reports.
  final int start;
  final int end;

  /// The name, when this unit is one. Null for a syllable.
  final String? literal;

  @override
  bool operator ==(Object other) =>
      other is _Unit && other.word == word && other.index == index;

  @override
  int get hashCode => Object.hash(word, index);
}

/// The horizontal margin the reading area keeps, except where a child needs
/// the full width to be tappable.
const _sides = EdgeInsets.symmetric(horizontal: 24);

/// Everything in the reading area apart from the composed line, which is the
/// one child that runs edge to edge.
class _Rest extends StatelessWidget {
  const _Rest({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Padding(
    padding: _sides,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: children,
    ),
  );
}

/// A tone that looks like a slip, offered rather than applied.
///
/// Offered, never corrected automatically: the learner may have meant the
/// obscure word, and silently retoning what someone typed in a language they
/// are learning would be the rudest thing this app could do.
class _Suggestion extends StatelessWidget {
  const _Suggestion({required this.suggestion, required this.onAccept});

  final ToneSuggestion suggestion;
  final VoidCallback onAccept;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Align(
      alignment: Alignment.centerLeft,
      child: Material(
        color: theme.colorScheme.secondaryContainer,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          key: const Key('suggestion'),
          onTap: onAccept,
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.spellcheck,
                  size: 16,
                  color: theme.colorScheme.onSecondaryContainer,
                ),
                const SizedBox(width: 8),
                // The corrected line, and the word it would make, so the
                // reason is on show rather than implied.
                Flexible(
                  child: Text.rich(
                    TextSpan(
                      children: [
                        const TextSpan(text: 'did you mean '),
                        TextSpan(
                          text: suggestion.written,
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        TextSpan(text: '? — ${suggestion.gloss}'),
                      ],
                    ),
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: theme.colorScheme.onSecondaryContainer,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Asks for a word that is not Mandarin.
///
/// Small, and modal, so it reads as the exception it is: everything else in
/// this app is typed on the app's own keyboard, one piece of a syllable at a
/// time. A name has no syllables to choose and no tone to pick.
class _WordDialog extends StatefulWidget {
  const _WordDialog({required this.existing});

  final String existing;

  @override
  State<_WordDialog> createState() => _WordDialogState();
}

class _WordDialogState extends State<_WordDialog> {
  late final TextEditingController _controller =
      TextEditingController(text: widget.existing)
        ..selection = TextSelection(
          baseOffset: 0,
          extentOffset: widget.existing.length,
        );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _accept() => Navigator.pop(context, _controller.text);

  @override
  Widget build(BuildContext context) {
    final correcting = widget.existing.isNotEmpty;

    return AlertDialog(
      title: const Text('Untranslated Word'),
      content: TextField(
        key: const Key('literal-field'),
        controller: _controller,
        autofocus: true,
        // Names are not sentences, and autocorrect would fight a name it has
        // never seen. Capitals are left to the learner.
        autocorrect: false,
        enableSuggestions: false,
        textCapitalization: TextCapitalization.words,
        textInputAction: TextInputAction.done,
        onSubmitted: (_) => _accept(),
        decoration: const InputDecoration(
          hintText: 'Steve',
          helperText: 'Carried through as you type it',
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        TextButton(
          key: const Key('literal-accept'),
          onPressed: _accept,
          child: Text(correcting ? 'Correct' : 'Add'),
        ),
      ],
    );
  }
}

/// What the ⓘ button opens: how to use the app, then who the data belongs to.
///
/// Collapsed by default. Anyone opening this is usually after one of the two,
/// and showing both at once means reading past the one they did not want.
class _Sections extends StatelessWidget {
  const _Sections();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _Section(
          id: 'hints',
          title: 'Getting around',
          children: [
            for (final hint in _hints) _Hint(icon: hint.$1, text: hint.$2),
          ],
        ),
        _Section(
          id: 'credits',
          title: 'Credits and licences',
          children: [
            Text(
              'Word meanings come from CC-CEDICT, a community maintained free '
              'Chinese-English dictionary published by MDBG. Used under the '
              'Creative Commons Attribution-ShareAlike 4.0 International '
              'licence.\n'
              'https://creativecommons.org/licenses/by-sa/4.0/',
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 12),
            Text(
              'Word frequency and HSK levels from complete-hsk-vocabulary, '
              'copyright Yanis Zafirópulos, used under the MIT licence.',
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 12),
            Text(
              'Whole-phrase translation runs Qwen3.5 0.8B on this device, '
              'under the Apache 2.0 licence, through llama.cpp — wllama in a '
              'browser — under the MIT licence.',
              style: theme.textTheme.bodyMedium,
            ),
          ],
        ),
      ],
    );
  }
}

/// The things that are not obvious from looking at the screen.
const _hints = <(IconData, String)>[
  (
    Icons.touch_app_outlined,
    'Tap a syllable to put the caret before or after '
        'it, or tap beside the line to jump to its start or end.',
  ),
  (
    Icons.replay,
    'Tap a syllable twice to choose its tone again, or hold it to choose '
        'what follows the initial again.',
  ),
  (
    Icons.space_bar,
    'Space starts a new word. Backspace steps back a piece at '
        'a time, then a syllable, then a word break.',
  ),
  (
    Icons.keyboard_alt_outlined,
    'Beside the prompt, "or type a word" adds '
        'something that is not Chinese — a name. Tap it later to correct it.',
  ),
  (
    Icons.spellcheck,
    'When a tone looks like a slip, a suggestion appears '
        'under the line. Tap it to accept.',
  ),
  (
    Icons.volume_up_outlined,
    'The speaker reads the line aloud, slowly. It '
        'only appears if this device has a Mandarin voice.',
  ),
  (
    Icons.translate,
    'Going the other way: type what you want to say, get '
        'the pinyin, then bring it back here to practise or correct it.',
  ),
  (
    Icons.auto_awesome_outlined,
    'Whole sentences need a model, downloaded '
        'once from the ✨ button. Without it, words and set phrases still work.',
  ),
  (
    Icons.keyboard_outlined,
    'The keyboard button swaps between QWERTY order '
        'and articulation order — how pinyin is taught.',
  ),
];

/// One collapsible part of the ⓘ dialog.
class _Section extends StatelessWidget {
  const _Section({
    required this.id,
    required this.title,
    required this.children,
  });

  final String id;
  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Theme(
      // The divider a Material expansion tile draws above and below itself is
      // noise inside a dialog that is already bounded.
      data: theme.copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        key: Key('about-$id'),
        title: Text(title, style: theme.textTheme.titleSmall),
        tilePadding: EdgeInsets.zero,
        childrenPadding: const EdgeInsets.only(bottom: 8),
        expandedCrossAxisAlignment: CrossAxisAlignment.start,
        children: children,
      ),
    );
  }
}

class _Hint extends StatelessWidget {
  const _Hint({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 2, right: 10),
            child: Icon(icon, size: 18, color: theme.colorScheme.tertiary),
          ),
          Expanded(child: Text(text, style: theme.textTheme.bodyMedium)),
        ],
      ),
    );
  }
}
