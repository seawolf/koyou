import 'package:flutter/foundation.dart';

import '../pinyin/word.dart';

/// One way of saying what was asked for, as pinyin the keyboard could have
/// built.
///
/// [Word]s rather than a string, because the point of an answer here is that
/// it can be taken into the input area and worked on — retoned, corrected,
/// spoken. A string would have to be split back into syllables, and splitting
/// written pinyin is ambiguous.
@immutable
class Rendering {
  const Rendering({
    required this.words,
    this.meaning,
    this.distinction,
    this.example,
    this.register,
    this.hskLevel,
  });

  final List<Word> words;

  /// What this actually means, back in English.
  ///
  /// Not the English that was asked for — the gloss of the Chinese word being
  /// offered. That is the difference between "hot" answered with 热 and with
  /// 辣, and a learner who cannot read the characters has nothing else to
  /// choose by.
  final String? meaning;

  /// What tells this candidate apart from another showing the same [meaning],
  /// or null where nothing needs telling apart. Where this project's own
  /// notes say what a word is used for, that is shown instead, whether or not
  /// the meaning is shared — it was written to tell words apart.
  ///
  /// 64% of English headwords with several candidates show the same gloss on
  /// two of them — "lunch" offered 午餐, 午饭 and 中餐, each glossed "lunch" —
  /// which left a learner choosing between three identical rows. So wherever
  /// [meaning] is shared, this says what differs: a sense only this word has
  /// ("also: Chinese meal; Chinese food"), that it has no other sense, or —
  /// where the dictionary records no difference at all — which is commoner.
  final String? distinction;

  /// A sentence using the word, where one is known.
  ///
  /// Shows what a note cannot: 会员 is a member of a club, and its example
  /// is about a membership card; 成员 is a member of a group, and its example
  /// is a committee. Where two words share a meaning, this is what a learner
  /// chooses by.
  final Example? example;

  /// Whether this is the everyday or the formal word, where that is known.
  final Register? register;

  /// The HSK band of the word, 1 being the most elementary, or null where it
  /// is outside the syllabus or the answer spans several words.
  final int? hskLevel;

  /// The pinyin, as written, with a space between words.
  String get written => words
      .where((word) => !word.isEmpty)
      .map((word) => word.written)
      .join(' ');

  @override
  bool operator ==(Object other) =>
      other is Rendering &&
      listEquals(other.words, words) &&
      other.meaning == meaning &&
      other.distinction == distinction &&
      other.example == example &&
      other.register == register &&
      other.hskLevel == hskLevel;

  @override
  int get hashCode => Object.hash(
    Object.hashAll(words),
    meaning,
    distinction,
    example,
    register,
    hskLevel,
  );

  @override
  String toString() => meaning == null ? written : '$written ($meaning)';
}

/// A sentence showing a word in use: as pinyin, with the word itself marked,
/// and in English.
@immutable
class Example {
  const Example({
    required this.words,
    required this.target,
    required this.english,
  });

  /// The sentence, read into words the way the rest of the app reads them.
  final List<Word> words;

  /// Which of [words] is the word being shown, so it can stand out.
  final int target;

  final String english;

  @override
  bool operator ==(Object other) =>
      other is Example &&
      listEquals(other.words, words) &&
      other.target == target &&
      other.english == english;

  @override
  int get hashCode => Object.hash(Object.hashAll(words), target, english);
}

/// How formal an answer should be, where the learner says.
///
/// Two values and no more, because that is what the data can honour. A word
/// is labelled with one only where `assets/notes/word_notes.tsv` says so, and
/// a preference reorders the candidates that carry a label without hiding
/// the ones that do not.
enum Register {
  /// What you would say in conversation.
  everyday,

  /// What you would write, or say on an occasion.
  formal,
}

/// Where an answer came from.
///
/// Stated rather than deduced. The screen needs to know whether it is showing
/// a dictionary's candidates or a model's sentence, and the two are not
/// reliably told apart by shape: a dictionary answer can have one candidate
/// and a generated one can be a single word.
enum Phrasing {
  /// A dictionary entry, or a phrase from the hand-written list.
  ///
  /// Exact and repeatable. Ambiguous where English is vaguer than Chinese,
  /// which is what the extra candidates are for.
  entry,

  /// Written by a model.
  ///
  /// The only thing that can answer a sentence, and the only thing here that
  /// can be confidently wrong — see [Said.readsBackAs].
  generated,
}

/// What an [EnglishTranslator] came back with.
@immutable
class Said {
  const Said({required this.options, required this.phrasing, this.readsBackAs});

  /// Best first. One for a sentence; up to three for a word, because English
  /// is often vaguer than Chinese and picking silently would be worse than
  /// offering the choice.
  final List<Rendering> options;

  final Phrasing phrasing;

  /// The answer translated straight back into English, where that check was
  /// made.
  ///
  /// The reason this exists: going this way round, a wrong answer is invisible.
  /// Asked for Chinese, an 0.8B model sometimes stops translating and starts
  /// being a polite Chinese assistant — "I would like two beers please" came
  /// back as 您好，请问您想要两瓶啤酒吗？, which is "hello, would you like two
  /// beers?". A learner cannot read the characters and the pinyin is perfectly
  /// fluent, so nothing on screen would give it away. Reading it back through
  /// the direction that is measured and reliable is what does.
  final String? readsBackAs;

  Rendering get best => options.first;

  @override
  bool operator ==(Object other) =>
      other is Said &&
      listEquals(other.options, options) &&
      other.phrasing == phrasing &&
      other.readsBackAs == readsBackAs;

  @override
  int get hashCode =>
      Object.hash(Object.hashAll(options), phrasing, readsBackAs);

  @override
  String toString() => options.join(' / ');
}

/// Turns English into pinyin a learner can say.
///
/// The other direction from [Translator], and deliberately a separate seam
/// rather than a flag on it. The two share their data and nothing else: one
/// resolves pinyin the learner typed, the other has to choose the Chinese in
/// the first place, which is a different problem with different failure modes.
abstract interface class EnglishTranslator {
  /// Pinyin for [english], or null if this translator has none to offer.
  ///
  /// [register] is the learner's preference, if they gave one. It orders an
  /// answer; it never empties one.
  Future<Said?> say(String english, {Register? register});
}

/// Asks each translator in turn and takes the first answer.
class CompositeEnglishTranslator implements EnglishTranslator {
  const CompositeEnglishTranslator(this.translators);

  final List<EnglishTranslator> translators;

  @override
  Future<Said?> say(String english, {Register? register}) async {
    for (final translator in translators) {
      final said = await translator.say(english, register: register);
      if (said != null) return said;
    }
    return null;
  }
}
