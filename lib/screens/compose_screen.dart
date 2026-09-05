import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../pinyin/composition.dart';
import '../pinyin/keyboard_layout.dart';
import '../translation/translator.dart';
import '../widgets/blinking_cursor.dart';
import '../widgets/pinyin_keyboard.dart';

/// Compose Mandarin as pinyin with tone marks, and see what it means.
///
/// The app's reason to exist: dictionary apps take pinyin but only a word at a
/// time, and translation apps take phrases but want Hanzi, so there is nowhere
/// to simply type `nǐ hǎo, shìjiè`. This screen is that missing box.
class ComposeScreen extends StatefulWidget {
  const ComposeScreen({super.key, required this.translator});

  /// Supplied by the caller, and typed as the interface only, so this screen
  /// never names a translation implementation. Swapping in a real model is a
  /// change in `app.dart` and nowhere else.
  final Translator translator;

  @override
  State<ComposeScreen> createState() => _ComposeScreenState();
}

class _ComposeScreenState extends State<ComposeScreen> {
  Composition _composition = const Composition();
  Translation? _translation;

  /// Whether a lookup has been running long enough to be worth mentioning.
  bool _lookingUp = false;
  Timer? _admitToLookingUp;

  /// How long a lookup may take before the screen says it is working.
  ///
  /// Deliberately longer than a lookup normally takes. Reading a dictionary
  /// shard costs 1-24ms from local assets, and flashing a message for 24ms is
  /// worse than saying nothing. Over the web the same shard is an HTTP fetch,
  /// which has no upper bound — that is the case this exists for.
  static const _worthMentioning = Duration(milliseconds: 250);

  /// Which initial-bank arrangement is in use, switchable from the app bar.
  ///
  /// QWERTY by default: it is what most hands already know, and its three rows
  /// fit a landscape phone, where articulation order's seven shorter rows have
  /// to scroll.
  KeyArrangement _arrangement = KeyArrangement.qwerty;

  void _edit(Composition next) {
    setState(() => _composition = next);
    _translate(next);
  }

  @override
  void dispose() {
    _admitToLookingUp?.cancel();
    super.dispose();
  }

  Future<void> _translate(Composition composition) async {
    final request = TranslationRequest(composition.words);
    _admitToLookingUp?.cancel();

    if (request.isEmpty) {
      setState(() {
        _translation = null;
        _lookingUp = false;
      });
      return;
    }

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
            lookingUp: _lookingUp,
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
    required this.lookingUp,
  });

  final Composition composition;
  final Translation? translation;
  final bool lookingUp;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final translation = this.translation;

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
          if (lookingUp && translation == null) ...[
            const SizedBox(height: 20),
            Text(
              'looking it up…',
              key: const Key('looking-up'),
              style: theme.textTheme.titleMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
          if (translation != null) ...[
            const SizedBox(height: 20),
            Text(
              translation.text,
              style: theme.textTheme.titleLarge?.copyWith(
                color: theme.colorScheme.primary,
              ),
            ),
            // Say what kind of answer this is. Without it, three candidate
            // meanings read as one confident translation.
            if (translation.wordByWord || translation.uncertain)
              Text(
                [
                  if (translation.wordByWord) 'word by word',
                  if (translation.uncertain) 'several words sound like this',
                ].join(' · '),
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            if (translation.hskLevel != null)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  'HSK ${translation.hskLevel}',
                  key: const Key('hsk-level'),
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
          ],
        ],
      ),
    );
  }
}
