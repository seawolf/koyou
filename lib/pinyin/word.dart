import 'package:flutter/foundation.dart';

import 'syllable.dart';

/// One word of a composed line.
///
/// Sealed because there are exactly two kinds and the difference matters at
/// every layer: one has pinyin and can be looked up, the other is a run of
/// letters that is only ever carried. A learner writing `wǒ jiào Steve` needs
/// both in the same line.
@immutable
sealed class Word {
  const Word();

  /// As it appears on screen.
  String get written;

  /// How many places inside this word the caret can sit, so a caret index runs
  /// 0 to [length]. A [Literal] is one indivisible unit: the caret goes either
  /// side of `Steve`, never into the middle of it.
  int get length;

  bool get isEmpty => length == 0;

  /// The first [count] units, as written — everything before a caret at
  /// [count].
  String writtenTake(int count);

  /// Everything from [count] onwards, as written.
  String writtenSkip(int count);
}

/// A word made of Mandarin syllables, which is what the keyboard builds.
final class Spoken extends Word {
  const Spoken([this.syllables = const <Syllable>[]]);

  final List<Syllable> syllables;

  @override
  int get length => syllables.length;

  @override
  String get written => syllables.map((syllable) => syllable.written).join();

  @override
  String writtenTake(int count) =>
      syllables.take(count).map((syllable) => syllable.written).join();

  @override
  String writtenSkip(int count) =>
      syllables.skip(count).map((syllable) => syllable.written).join();

  /// The form a dictionary is keyed on: `ni3 hao3`.
  String get key => syllables.map((syllable) => syllable.numbered).join(' ');

  @override
  bool operator ==(Object other) =>
      other is Spoken && listEquals(other.syllables, syllables);

  @override
  int get hashCode => Object.hashAll(syllables);

  @override
  String toString() => 'Spoken($written)';
}

/// A word that is not Mandarin — a name, a brand, a borrowed word.
///
/// Carried through untouched rather than looked up or pronounced from pinyin.
/// Nothing has to be invented for it downstream: Chinese writes foreign names
/// in Latin letters as a matter of course, so `我叫Steve` is ordinary text and
/// a model reads it without being told anything about it.
final class Literal extends Word {
  const Literal(this.text);

  final String text;

  @override
  int get length => 1;

  @override
  String get written => text;

  // Indivisible, so a caret before it takes nothing and a caret after it takes
  // the lot.
  @override
  String writtenTake(int count) => count <= 0 ? '' : text;

  @override
  String writtenSkip(int count) => count <= 0 ? text : '';

  @override
  bool operator ==(Object other) => other is Literal && other.text == text;

  @override
  int get hashCode => text.hashCode;

  @override
  String toString() => 'Literal($text)';
}
