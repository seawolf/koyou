import 'package:flutter/material.dart';

import '../pinyin/composition.dart';
import '../pinyin/keyboard_layout.dart';
import '../pinyin/tone.dart';

/// A pinyin keyboard: pick an initial, pick a rime, pick a tone.
///
/// Deliberately not a character IME. Ordinary Chinese keyboards treat pinyin as
/// a way to reach Hanzi and convert it away at the first opportunity; here the
/// pinyin *is* the output, tone marks included.
///
/// Choosing the tone is what commits the syllable, because every Mandarin
/// syllable has exactly one — so it doubles as the enter key and there is no
/// way to enter a syllable without deciding its tone.
class PinyinKeyboard extends StatelessWidget {
  const PinyinKeyboard({
    super.key,
    required this.draft,
    required this.onInitial,
    required this.onRime,
    required this.onTone,
    required this.onSpace,
    required this.onBackspace,
    required this.onClear,
  });

  final Draft draft;
  final ValueChanged<String> onInitial;
  final ValueChanged<String> onRime;
  final ValueChanged<Tone> onTone;
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
            // Only the key banks scroll. The tone row below stays put: it is
            // pressed once per syllable, and on a short keyboard area it was
            // the first thing to disappear below the fold.
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _Section(
                      label: 'initial',
                      child: _keys(
                        context,
                        keys: initials,
                        selected: draft.initial,
                        onTap: onInitial,
                      ),
                    ),
                    for (final group in rimeGroups)
                      _Section(
                        label: group.label,
                        child: _keys(
                          context,
                          keys: group.keys,
                          selected: draft.rime,
                          onTap: onRime,
                          prefix: 'rime',
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
              child: _toneRow(context),
            ),
          ],
        ),
      ),
    );
  }

  Widget _keys(
    BuildContext context, {
    required List<String> keys,
    required String selected,
    required ValueChanged<String> onTap,
    String prefix = 'initial',
  }) {
    return Wrap(
      spacing: 5,
      runSpacing: 5,
      children: [
        for (final key in keys)
          ChoiceChip(
            key: Key('$prefix-$key'),
            label: Text(key),
            selected: selected == key,
            // Pressing the selected key again clears it, so a mistake does not
            // need a trip to backspace.
            onSelected: (_) => onTap(selected == key ? '' : key),
            visualDensity: VisualDensity.compact,
          ),
      ],
    );
  }

  Widget _toneRow(BuildContext context) {
    final theme = Theme.of(context);
    // A tone is only meaningful once there is a rime to put it on.
    final enabled = draft.isCommittable;

    return Row(
      children: [
        // The tone keys share whatever width the controls leave. They were
        // laid out at their natural size with a Spacer, which pushed the
        // controls clean off a 375pt screen.
        for (final tone in Tone.values)
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(right: 6),
              child: FilledButton(
                key: Key('tone-${tone.number}'),
                onPressed: enabled ? () => onTone(tone) : null,
                style: FilledButton.styleFrom(
                  padding: EdgeInsets.zero,
                  minimumSize: const Size(0, 44),
                  textStyle: theme.textTheme.titleMedium,
                ),
                child: Text(
                  tone == Tone.neutral ? 'a' : tone.on('a'),
                  semanticsLabel: 'tone ${tone.number}',
                ),
              ),
            ),
          ),
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
          tooltip: 'Backspace',
        ),
        IconButton(
          key: const Key('clear'),
          onPressed: onClear,
          icon: const Icon(Icons.clear_all),
          tooltip: 'Clear',
        ),
      ],
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.label, required this.child});

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 46,
            child: Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                label,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ),
          Expanded(child: child),
        ],
      ),
    );
  }
}
