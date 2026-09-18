import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../audio/speech.dart';
import '../pinyin/composition.dart';
import '../pinyin/keyboard_layout.dart';
import '../pinyin/word.dart';
import '../translation/model_store.dart';
import '../translation/tone_suggestion.dart';
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
            onMoveCaret: (caret) => _edit(_composition.movedTo(caret)),
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
          // Keyed off the preview, not off whether anything has been chosen: the
          // vowel keys spell nothing on their own, so choosing `a` used to
          // blank this area instead of leaving the prompt up.
          if (composition.preview.isEmpty)
            Padding(
              padding: _sides,
              child: Text(
                'Your pinyin appears here',
                style: theme.textTheme.titleMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            )
          else
            _ComposedLine(
              composition: composition,
              onMoveCaret: onMoveCaret,
              onEditLiteral: onEditLiteral,
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
  });

  final Composition composition;
  final ValueChanged<Caret> onMoveCaret;

  /// Asked to reopen the editor on the name at this word index.
  final void Function(int word, String text) onEditLiteral;

  @override
  State<_ComposedLine> createState() => _ComposedLineState();
}

class _ComposedLineState extends State<_ComposedLine> {
  /// One per syllable on screen, rebuilt whenever the line changes.
  final List<TapGestureRecognizer> _taps = [];

  @override
  void dispose() {
    _disposeTaps();
    super.dispose();
  }

  void _disposeTaps() {
    for (final tap in _taps) {
      tap.dispose();
    }
    _taps.clear();
  }

  /// A tap on a syllable puts the caret at [before], or after that syllable if
  /// the tap landed past [midpoint] — which is what every other text field
  /// does, and the only way to reach the end of a word by tapping its last
  /// syllable.
  ///
  /// [midpoint] is measured from the text as the spans are built, because a
  /// paragraph does not hand a span its own bounds. It has to be captured per
  /// recognizer: held in a field instead, every syllable read the last one's
  /// midpoint and the right half never worked except on the final syllable.
  /// A tap on a name reopens the editor on it.
  TapGestureRecognizer _edit(int word, String text) {
    final recognizer = TapGestureRecognizer()
      ..onTap = () => widget.onEditLiteral(word, text);
    _taps.add(recognizer);
    return recognizer;
  }

  TapGestureRecognizer _tap(Caret before, Caret after, double midpoint) {
    final recognizer = TapGestureRecognizer()
      ..onTapUp = (details) {
        final box = context.findRenderObject();
        if (box is! RenderBox) return;
        final local = box.globalToLocal(details.globalPosition);
        widget.onMoveCaret(local.dx < midpoint ? before : after);
      };
    _taps.add(recognizer);
    return recognizer;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final style = theme.textTheme.displaySmall;
    final composition = widget.composition;
    _disposeTaps();

    final caret = WidgetSpan(
      alignment: PlaceholderAlignment.middle,
      child: BlinkingCursor(height: style?.fontSize ?? 36),
    );
    // The draft is dimmed: it has no tone yet, so it is not yet a syllable
    // anyone should read aloud.
    final draft = TextSpan(
      text: composition.draftSuffix,
      style: TextStyle(
        color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.55),
      ),
    );

    final spans = <InlineSpan>[];
    var painted = 0.0;
    var anythingBefore = false;

    void addCaret() {
      spans.add(draft);
      spans.add(caret);
    }

    for (var word = 0; word < composition.words.length; word++) {
      final here = composition.words[word];
      // An empty word still renders something if the caret is sitting in it —
      // the draft, or the caret alone — and it still needs the space that
      // separates it from the word before. Without this the space after a
      // word break was invisible, and `wǒài` looked like `wǒ ài`.
      final visible = !here.isEmpty || composition.caret.word == word;
      if (anythingBefore && visible) {
        spans.add(const TextSpan(text: ' '));
        painted += _widthOf(' ', style);
      }
      // Only real words count as text before. A word holding nothing but the
      // caret — what backspacing the first syllable of a line leaves — must
      // not put a space in front of the word after it.
      if (!here.isEmpty) anythingBefore = true;

      for (var index = 0; index <= here.length; index++) {
        if (composition.caret.word == word &&
            composition.caret.syllable == index) {
          addCaret();
        }
        if (index == here.length) break;

        // A name is one unit and a word of its own, so tapping it is not a
        // request to put the caret somewhere — it is a request to correct the
        // name. It is shown in the same size but not as pinyin, because it has
        // no tones and is not something to pronounce syllable by syllable.
        if (here is Literal) {
          final width = _widthOf(here.text, style);
          painted += width;
          spans.add(
            TextSpan(
              text: here.text,
              style: TextStyle(
                color: theme.colorScheme.tertiary,
                fontStyle: FontStyle.italic,
              ),
              recognizer: _edit(word, here.text),
            ),
          );
          continue;
        }

        final written = (here as Spoken).syllables[index].written;
        final width = _widthOf(written, style);
        final midpoint = painted + width / 2;
        painted += width;
        spans.add(
          TextSpan(
            text: written,
            recognizer: _tap(
              Caret(word: word, syllable: index),
              Caret(word: word, syllable: index + 1),
              midpoint,
            ),
          ),
        );
      }
    }

    return Stack(
      children: [
        // Behind the text, and hit-tested after it, so a tap on a syllable
        // still reaches that syllable's own recognizer. Only taps that miss
        // the glyphs — beside the line, or just above and below it — land
        // here, and those snap to whichever end they are nearer.
        Positioned.fill(
          child: GestureDetector(
            key: const Key('composed-margin'),
            behavior: HitTestBehavior.opaque,
            onTapUp: (details) => widget.onMoveCaret(
              details.localPosition.dx < _sides.left
                  ? const Caret(word: 0, syllable: 0)
                  : composition.end,
            ),
          ),
        ),
        Padding(
          // Vertical room so a tap a little above or below the text still
          // counts, and the horizontal margin the rest of the reading area
          // has, here as part of the tappable band rather than outside it.
          padding: _sides + const EdgeInsets.symmetric(vertical: 10),
          child: Text.rich(
            key: const Key('composed'),
            TextSpan(children: spans),
            style: style,
          ),
        ),
      ],
    );
  }

  /// How wide [text] is in [style], for splitting a syllable down the middle.
  double _widthOf(String text, TextStyle? style) {
    final painter = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: TextDirection.ltr,
    )..layout();
    final width = painter.width;
    painter.dispose();
    return width;
  }
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
      title: Text(
        correcting ? 'Correct the word' : 'A word that is not Chinese',
      ),
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
          helperText: 'Carried through as you type it, not translated',
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
