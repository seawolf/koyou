import 'package:flutter/foundation.dart';

import '../pinyin/syllable.dart';
import '../pinyin/word.dart';
import '../pinyin/tone.dart';
import 'dictionary.dart';
import 'translator.dart';

/// A tone that looks like a slip, and what it was probably meant to be.
///
/// One syllable at a time. A tone is the most likely thing to go wrong when
/// typing pinyin — it is the part of the syllable a learner is least sure of —
/// and it is also the only part that can be corrected without guessing at what
/// was typed, because the letters stay put.
@immutable
class ToneSuggestion {
  const ToneSuggestion({
    required this.written,
    required this.gloss,
    required this.word,
    required this.syllable,
    required this.tone,
  });

  /// The whole line as it would read, so the learner can compare it to what
  /// is on screen rather than decode a description of a change.
  final String written;

  /// The word the correction would make, for a "did you mean" that says why.
  final String gloss;

  final int word;
  final int syllable;
  final Tone tone;
}

/// Notices a mistyped tone.
///
/// A seam, but a thin one: this is a dictionary question, and the answer is a
/// dictionary lookup rather than a judgement.
abstract interface class Suggester {
  Future<ToneSuggestion?> check(TranslationRequest request);
}

/// Finds a mistyped tone by asking whether the same letters with a different
/// tone are a better word.
///
/// Deliberately not a model's job. A model would have to be asked a second
/// question, doubling the wait, and this is the least reliable thing to ask a
/// small one: it does not know which tone is right, it knows which sentence
/// sounds likely, and it will nag confidently about correct input. Frequency
/// data is not an opinion.
///
/// Two signals, both narrow enough to stay quiet on correct pinyin:
///
/// - **What was typed is not a word, and the same letters with another tone
///   are.** Not a judgement at all. `nǐ hāo` is nothing; `nǐ hǎo` is 你好.
/// - **What was typed is a word, but one no standard syllabus contains, while
///   a tone-neighbour is common.** `xiè xiè` is 泄泻, "(TCM) to have
///   diarrhea", and unranked; `xiè xie` is 谢谢. Restricted to words of more
///   than one syllable, because a single obscure character can be a deliberate
///   pick from the candidate list.
///
/// Measured against ten ordinary inputs — 你好, 我, 时, 妈, 呢, 埋, 世界, 朋友,
/// 谢谢, 老师 — it stays silent on all of them.
class DictionarySuggester implements Suggester {
  const DictionarySuggester(this.dictionary);

  final Dictionary dictionary;

  @override
  Future<ToneSuggestion?> check(TranslationRequest request) async {
    // Names are skipped: there is no tone in `Steve` to have got wrong.
    final words = [
      for (final word in request.words)
        if (word is Spoken && !word.isEmpty) word,
    ];
    for (final word in words) {
      final typed = await dictionary.lookUp(word.key);
      final isWord = typed.isNotEmpty;
      if (isWord) {
        // A word the learner may well have meant.
        if (typed.first.rank != null) continue;
        if (word.length < 2) continue;
      }

      // Where what was typed is nothing at all, any real word is a better
      // guess than silence — 你好 carries no frequency rank and is still the
      // obvious answer to `nǐ hāo`. Where what was typed *is* a word, only a
      // ranked neighbour is worth offering: swapping one obscure word for
      // another helps nobody.
      final better = await _bestNeighbour(
        word.syllables,
        requireRanked: isWord,
      );
      if (better == null) continue;

      final corrected = [
        for (var position = 0; position < word.syllables.length; position++)
          position == better.syllable
              ? _retone(word.syllables[position], better.tone)
              : word.syllables[position],
      ];
      // The whole line, with this one word corrected in place. Names included,
      // as themselves, so the learner compares it to what is on screen.
      final shown = [
        for (final other in request.words)
          if (!other.isEmpty)
            identical(other, word) ? _write(corrected) : other.written,
      ].join(' ');

      return ToneSuggestion(
        written: shown,
        gloss: better.gloss,
        word: request.words.indexOf(word),
        syllable: better.syllable,
        tone: better.tone,
      );
    }
    return null;
  }

  /// The commonest word reachable by changing one tone in [word].
  Future<_Neighbour?> _bestNeighbour(
    List<Syllable> word, {
    required bool requireRanked,
  }) async {
    _Neighbour? best;
    for (var position = 0; position < word.length; position++) {
      for (final tone in Tone.values) {
        if (tone == word[position].tone) continue;
        final candidate = [
          for (var other = 0; other < word.length; other++)
            other == position ? _retone(word[other], tone) : word[other],
        ];
        final entries = await dictionary.lookUp(Spoken(candidate).key);
        if (entries.isEmpty) continue;
        final rank = entries.first.rank;
        if (rank == null && requireRanked) continue;
        // Unranked sorts last, so a common neighbour always wins over an
        // obscure one when both exist.
        final ordered = rank ?? _unranked;
        if (best == null || ordered < best.rank) {
          best = _Neighbour(
            rank: ordered,
            syllable: position,
            tone: tone,
            gloss: entries.first.glosses.first,
          );
        }
      }
    }
    return best;
  }

  static Syllable _retone(Syllable syllable, Tone tone) =>
      Syllable(initial: syllable.initial, rime: syllable.rime, tone: tone);

  static String _write(List<Syllable> word) =>
      word.map((syllable) => syllable.written).join();
}

/// Sorts after every real rank.
const _unranked = 1 << 30;

class _Neighbour {
  const _Neighbour({
    required this.rank,
    required this.syllable,
    required this.tone,
    required this.gloss,
  });

  final int rank;
  final int syllable;
  final Tone tone;
  final String gloss;
}
