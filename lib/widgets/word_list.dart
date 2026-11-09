import 'package:flutter/material.dart';

import '../translation/translator.dart';

/// Words or characters one per line, each with what it means.
///
/// One per line so a word-by-word answer cannot be read as a sentence: `nǐ ·
/// hǎo · shì · jiè` along one line invites exactly the misreading it is there
/// to prevent. The same list takes a word apart into its characters.
class WordList extends StatelessWidget {
  const WordList({super.key, required this.words, this.dense = false});

  final List<WordGloss> words;

  /// Smaller, for a list that sits under one candidate among several rather
  /// than under the whole answer.
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    final style = dense
        ? theme.textTheme.bodyMedium
        : theme.textTheme.bodyLarge;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final word in words)
          Padding(
            padding: EdgeInsets.only(top: dense ? 2 : 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 2, right: 8),
                  child: Text('•', style: style?.copyWith(color: muted)),
                ),
                // The pinyin, so a line can be matched to the syllables it
                // came from.
                Text(
                  word.pinyin,
                  style: style?.copyWith(color: theme.colorScheme.primary),
                ),
                Text('  ', style: style),
                // Wraps rather than truncates: an ambiguous syllable offers
                // three candidates and they are the whole point of the line.
                Expanded(
                  child: Text(
                    word.english,
                    style: style?.copyWith(color: muted),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
