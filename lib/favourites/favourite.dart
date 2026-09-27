import 'package:flutter/foundation.dart';

import '../pinyin/reading.dart';
import '../pinyin/word.dart';

/// A line the learner chose to keep: the pinyin, and what it means.
///
/// The pinyin is kept as syllables, not as the text on screen. Opening a
/// favourite puts it back in the input area, and that needs syllables —
/// written pinyin cannot be split back reliably (`wanan` is two words), while
/// a syllable's dictionary key reads back exactly. The text is derived from
/// them whenever it is shown.
@immutable
class Favourite {
  const Favourite({required this.words, this.meaning, required this.saved});

  /// The line, word breaks included. Two favourites are the same favourite
  /// when these are equal: `nǐ hǎo` and `nǐhǎo` are different lines, and so
  /// are two lines that differ only in a tone.
  final List<Word> words;

  /// What it meant when it was saved, or null where nothing was showing.
  ///
  /// Kept as it was rather than looked up again, because it is what the
  /// learner decided was worth keeping — a later model answer, or no model at
  /// all, should not change their list under them.
  final String? meaning;

  final DateTime saved;

  /// The pinyin as written, with a space between words.
  String get pinyin => words
      .where((word) => !word.isEmpty)
      .map((word) => word.written)
      .join(' ');

  /// Whether this is the favourite for [line].
  bool isFor(List<Word> line) => listEquals(words, kept(line));

  /// [line] without the empty words a composition carries, which are never
  /// part of what was typed and would stop two identical lines matching.
  static List<Word> kept(List<Word> line) =>
      line.where((word) => !word.isEmpty).toList();

  Map<String, Object?> toJson() => {
    'words': [
      for (final word in words)
        switch (word) {
          Spoken() => {
            's': [for (final syllable in word.syllables) syllable.numbered],
          },
          Literal() => {'l': word.text},
        },
    ],
    'meaning': meaning,
    'saved': saved.toUtc().toIso8601String(),
  };

  /// The favourite [json] describes, or null if any of it no longer reads.
  ///
  /// Null rather than a partial line: a syllable that no longer reads means
  /// the inventory changed since it was saved, and half a line is not a line
  /// anyone can say. The rest of the list is unaffected.
  static Favourite? fromJson(Object? json) {
    if (json is! Map) return null;
    final saved = DateTime.tryParse(json['saved'] as String? ?? '');
    final rawWords = json['words'];
    if (saved == null || rawWords is! List) return null;

    final words = <Word>[];
    for (final raw in rawWords) {
      if (raw is! Map) return null;
      final literal = raw['l'];
      final syllables = raw['s'];
      if (literal is String) {
        words.add(Literal(literal));
      } else if (syllables is List) {
        final read = syllablesFor(syllables.whereType<String>().join(' '));
        if (read == null || read.length != syllables.length) return null;
        words.add(Spoken(read));
      } else {
        return null;
      }
    }
    if (words.isEmpty) return null;
    return Favourite(
      words: words,
      meaning: json['meaning'] as String?,
      saved: saved,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is Favourite &&
      listEquals(other.words, words) &&
      other.meaning == meaning &&
      other.saved == saved;

  @override
  int get hashCode => Object.hash(Object.hashAll(words), meaning, saved);

  @override
  String toString() => meaning == null ? pinyin : '$pinyin — $meaning';
}
