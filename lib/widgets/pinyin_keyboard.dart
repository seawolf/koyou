import 'package:flutter/material.dart';

import '../pinyin/composition.dart';
import '../pinyin/keyboard_layout.dart';
import '../pinyin/tone.dart';

/// A pinyin keyboard that asks for one piece of a syllable at a time.
///
/// Deliberately not a character IME. Ordinary Chinese keyboards treat pinyin as
/// a route to Hanzi and convert it away at the first opportunity; here the
/// pinyin *is* the output, tone marks included.
///
/// It shows one bank at a time — a starting point, then what can follow it,
/// then the tone — with the pieces already chosen tucked to the left as a trail
/// that can be tapped to go back. Showing every key at once meant 60-odd
/// targets and no indication of which combinations were real; staging it means
/// each choice is short, and every key offered leads somewhere Mandarin
/// actually goes.
class PinyinKeyboard extends StatelessWidget {
  const PinyinKeyboard({
    super.key,
    required this.draft,
    required this.onInitial,
    required this.onRime,
    required this.onTone,
    required this.onBackTo,
    required this.onSpace,
    required this.onBackspace,
    required this.onClear,
  });

  final Draft draft;
  final ValueChanged<InitialKey> onInitial;
  final ValueChanged<String> onRime;
  final ValueChanged<Tone> onTone;
  final ValueChanged<ComposeStage> onBackTo;
  final VoidCallback onSpace;
  final VoidCallback onBackspace;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Material(
      color: theme.colorScheme.surfaceContainer,
      child: SafeArea(
        top: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _Trail(draft: draft, onBackTo: onBackTo),
            const Divider(height: 1),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
                child: _bank(context),
              ),
            ),
            const Divider(height: 1),
            _controls(context),
          ],
        ),
      ),
    );
  }

  Widget _bank(BuildContext context) => switch (draft.stage) {
    ComposeStage.initial => Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final initial in initialKeys)
          _Key(
            id: 'initial-${initial.label}',
            label: initial.label,
            semanticsLabel: initial.label == bareVowelLabel
                ? 'no initial'
                : initial.label,
            onPressed: () => onInitial(initial),
          ),
      ],
    ),
    ComposeStage.rime => Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final rime in rimeKeysFor(draft.initial!))
          _Key(
            id: 'rime-${rime.label}',
            label: rime.label,
            onPressed: () => onRime(rime.rime),
          ),
      ],
    ),
    // The candidates, not abstract tone marks: the choice is between words the
    // learner can hear, which is the point of a tone-first app.
    ComposeStage.tone => Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final candidate in draft.candidates)
          _Key(
            id: 'tone-${candidate.tone.number}',
            label: candidate.written,
            semanticsLabel:
                '${candidate.written}, tone ${candidate.tone.number}',
            prominent: true,
            onPressed: () => onTone(candidate.tone),
          ),
      ],
    ),
  };

  Widget _controls(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 4, 8, 4),
      child: Row(
        children: [
          IconButton(
            key: const Key('space'),
            onPressed: onSpace,
            icon: const Icon(Icons.space_bar),
            tooltip: 'New word',
          ),
          IconButton(
            key: const Key('backspace'),
            onPressed: onBackspace,
            icon: const Icon(Icons.backspace_outlined),
            tooltip: 'Back',
          ),
          const Spacer(),
          IconButton(
            key: const Key('clear'),
            onPressed: onClear,
            icon: const Icon(Icons.clear_all),
            tooltip: 'Clear',
          ),
        ],
      ),
    );
  }
}

/// The pieces already chosen, tucked to the left of the prompt for the piece
/// being chosen now. Each is a way back to that decision.
class _Trail extends StatelessWidget {
  const _Trail({required this.draft, required this.onBackTo});

  final Draft draft;
  final ValueChanged<ComposeStage> onBackTo;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final initial = draft.initial;
    final rimeLabel = draft.rimeLabel;

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      child: Row(
        children: [
          if (initial != null)
            _TrailChip(
              id: 'trail-initial',
              label: initial.label,
              onPressed: () => onBackTo(ComposeStage.initial),
            ),
          if (rimeLabel != null)
            _TrailChip(
              id: 'trail-rime',
              label: rimeLabel,
              onPressed: () => onBackTo(ComposeStage.rime),
            ),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(left: initial == null ? 0 : 10),
              child: Text(
                switch (draft.stage) {
                  ComposeStage.initial => 'Start a syllable',
                  ComposeStage.rime => 'then what follows it',
                  ComposeStage.tone => 'then its tone',
                },
                style: theme.textTheme.labelLarge?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TrailChip extends StatelessWidget {
  const _TrailChip({
    required this.id,
    required this.label,
    required this.onPressed,
  });

  final String id;
  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: ActionChip(
        key: Key(id),
        label: Text(label),
        onPressed: onPressed,
        tooltip: 'Change',
        visualDensity: VisualDensity.compact,
        backgroundColor: theme.colorScheme.secondaryContainer,
        side: BorderSide.none,
      ),
    );
  }
}

/// One key. Large targets on purpose — only one bank is on screen at a time, so
/// there is room for them, and they are easier to hit accurately.
class _Key extends StatelessWidget {
  const _Key({
    required this.id,
    required this.label,
    required this.onPressed,
    this.semanticsLabel,
    this.prominent = false,
  });

  final String id;
  final String label;
  final VoidCallback onPressed;
  final String? semanticsLabel;
  final bool prominent;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final child = Text(
      label,
      semanticsLabel: semanticsLabel,
      style: prominent ? theme.textTheme.headlineSmall : null,
    );
    final style = ButtonStyle(
      padding: WidgetStatePropertyAll(
        EdgeInsets.symmetric(horizontal: prominent ? 18 : 14),
      ),
      minimumSize: WidgetStatePropertyAll(Size(prominent ? 72 : 56, 52)),
    );

    return prominent
        ? FilledButton(
            key: Key(id),
            onPressed: onPressed,
            style: style,
            child: child,
          )
        : OutlinedButton(
            key: Key(id),
            onPressed: onPressed,
            style: style,
            child: child,
          );
  }
}
