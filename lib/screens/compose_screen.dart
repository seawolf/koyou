import 'package:flutter/material.dart';

import '../pinyin/composition.dart';
import '../pinyin/keyboard_layout.dart';
import '../translation/translator.dart';
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

  /// Which initial-bank arrangement is in use. Switchable from the app bar so
  /// the two can be compared by feel, which is the only way to choose between
  /// them — see the note in `keyboard_layout.dart`.
  KeyArrangement _arrangement = KeyArrangement.articulatory;

  void _edit(Composition next) {
    setState(() => _composition = next);
    _translate(next.text);
  }

  Future<void> _translate(String text) async {
    final result = text.isEmpty
        ? null
        : await widget.translator.translate(text);
    if (!mounted) return;
    // A slower earlier lookup must not overwrite a newer one.
    if (_composition.text != text) return;
    setState(() => _translation = result);
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
        builder: (context, constraints) => Column(
          children: [
            // A fixed height, deliberately not sized to its content. Letting
            // the reading area grow with the text moved the whole keyboard up
            // the moment the first syllable landed, so keys shifted under the
            // user's finger mid-word. Long text scrolls inside instead.
            SizedBox(
              height: (constraints.maxHeight * 0.3).clamp(140.0, 260.0),
              child: _Reading(
                composition: _composition,
                translation: _translation,
              ),
            ),
            Expanded(
              child: PinyinKeyboard(
                arrangement: _arrangement,
                draft: _composition.draft,
                onInitial: (initial) =>
                    _edit(_composition.withInitial(initial)),
                onRime: (rime) => _edit(_composition.withRime(rime)),
                onTone: (tone) => _edit(_composition.commit(tone)),
                onBackTo: (stage) => _edit(_composition.backTo(stage)),
                onSpace: () => _edit(_composition.space()),
                onBackspace: () => _edit(_composition.backspace()),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// What has been typed, and what it means.
class _Reading extends StatelessWidget {
  const _Reading({required this.composition, required this.translation});

  final Composition composition;
  final Translation? translation;

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
                ],
              ),
              style: theme.textTheme.displaySmall,
            ),
          if (translation != null) ...[
            const SizedBox(height: 20),
            Text(
              translation.text,
              style: theme.textTheme.titleLarge?.copyWith(
                color: theme.colorScheme.primary,
              ),
            ),
            if (translation.wordByWord)
              Text(
                'word by word',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
          ],
        ],
      ),
    );
  }
}
