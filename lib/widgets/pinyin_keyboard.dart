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
    this.arrangement = KeyArrangement.articulatory,
  });

  /// How the initial bank is laid out. Only affects that one bank — the rime
  /// keys are multi-letter and have no keyboard positions to borrow.
  final KeyArrangement arrangement;

  final Draft draft;
  final ValueChanged<InitialKey> onInitial;
  final ValueChanged<String> onRime;
  final ValueChanged<Tone> onTone;
  final ValueChanged<ComposeStage> onBackTo;
  final VoidCallback onSpace;
  final VoidCallback onBackspace;

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
    ComposeStage.initial => _Rows(
      rows: [
        for (final row in initialRows(arrangement))
          [
            for (final initial in row)
              _Key(
                id: 'initial-${initial.label}',
                label: initial.label,
                onPressed: () => onInitial(initial),
              ),
          ],
      ],
    ),
    // Grouped by starting vowel, one block per group. Unlike the initial bank
    // these are not uniform-width rows: rime labels run from one letter to
    // four, and a group of ten would have to squeeze to fit on one line.
    ComposeStage.rime => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: 14,
      children: [
        for (final group in rimeRowsFor(draft.initial!))
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final rime in group)
                _Key(
                  id: 'rime-${rime.label}',
                  label: rime.label,
                  onPressed: () => onRime(rime.rime),
                ),
            ],
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

  /// The two controls that get used constantly, at half the width each.
  ///
  /// They were icon buttons in the corner. Clearing everything is not in this
  /// row on purpose — it lives in the app bar, away from the thumb, because it
  /// is rare and destructive.
  Widget _controls(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
      child: Row(
        children: [
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(right: 4),
              child: _Control(
                id: 'space',
                icon: Icons.space_bar,
                label: 'New word',
                onPressed: onSpace,
              ),
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(left: 4),
              child: _Control(
                id: 'backspace',
                icon: Icons.backspace_outlined,
                label: 'Back',
                onPressed: onBackspace,
              ),
            ),
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
    // One line, always, shrinking to fit rather than wrapping. The digraphs are
    // the reason: in a ten-across row a key is about 30pt wide, and `zh` was
    // wrapping to a stacked "z/h" that read as two separate letters.
    final child = FittedBox(
      fit: BoxFit.scaleDown,
      child: Text(
        label,
        semanticsLabel: semanticsLabel,
        maxLines: 1,
        softWrap: false,
      ),
    );
    // The size goes on the button, and carries no colour of its own.
    //
    // A TextTheme style here instead of a bare TextStyle brings its colour with
    // it, and that colour wins over the button's own foreground — which put
    // near-white text on the light fill of the tone keys, at 1.3:1.
    final style = ButtonStyle(
      textStyle: prominent
          ? WidgetStatePropertyAll(
              TextStyle(
                fontSize: theme.textTheme.headlineSmall?.fontSize,
                fontWeight: FontWeight.w500,
              ),
            )
          : null,
      // Barely any horizontal padding: _Rows sets the width, and padding here
      // was eating almost all of it.
      padding: WidgetStatePropertyAll(
        EdgeInsets.symmetric(horizontal: prominent ? 14 : 4),
      ),
      minimumSize: WidgetStatePropertyAll(Size(prominent ? 72 : 44, 52)),
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

/// Lays keys out in fixed rows, every key the same width.
///
/// Width comes from the longest row, so a nine-across row fits the screen and
/// every other row lines up with it. Capped, so an arrangement of short rows
/// does not turn into a few enormous keys.
class _Rows extends StatelessWidget {
  const _Rows({required this.rows});

  final List<List<Widget>> rows;

  static const double _gap = 6;
  static const double _maxKeyWidth = 64;

  @override
  Widget build(BuildContext context) {
    final longest = rows.fold<int>(
      0,
      (most, row) => row.length > most ? row.length : most,
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = ((constraints.maxWidth - _gap * (longest - 1)) / longest)
            .clamp(0.0, _maxKeyWidth);
        // Spacing between keys only, never after the last one: a trailing gap
        // made the widest row overflow by exactly one gap.
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          spacing: _gap,
          children: [
            for (final row in rows)
              Row(
                spacing: _gap,
                children: [
                  for (final key in row) SizedBox(width: width, child: key),
                ],
              ),
          ],
        );
      },
    );
  }
}

/// A wide control key, labelled by icon.
class _Control extends StatelessWidget {
  const _Control({
    required this.id,
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  final String id;
  final IconData icon;
  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: label,
      child: FilledButton.tonal(
        key: Key(id),
        onPressed: onPressed,
        style: FilledButton.styleFrom(
          minimumSize: const Size(0, 48),
          padding: EdgeInsets.zero,
        ),
        child: Icon(icon, semanticLabel: label),
      ),
    );
  }
}
