import 'package:flutter/services.dart';

/// One Chinese word that means a given English headword.
class EnglishMeaning {
  const EnglishMeaning({required this.key, required this.simplified});

  /// The dictionary key, which is also the pinyin: `pi2 jiu3`.
  final String key;

  /// The word in simplified characters, which is what tells two entries with
  /// the same reading apart.
  final String simplified;

  @override
  bool operator ==(Object other) =>
      other is EnglishMeaning &&
      other.key == key &&
      other.simplified == simplified;

  @override
  int get hashCode => Object.hash(key, simplified);

  @override
  String toString() => '$simplified ($key)';
}

/// CC-CEDICT read the other way round: English in, Chinese words out.
///
/// An inversion of a Chinese-to-English dictionary, and it inherits what that
/// means. It is good on words, silent on sentences, and it offers candidates
/// rather than an answer where English is vaguer than Chinese — "hot" is 热 or
/// 辣 and a learner is better told so than guessed at.
///
/// Sharded by the headword's first letter and parsed on demand, as the pinyin
/// side is, so a lookup touches one file of about 160KB.
class EnglishIndex {
  EnglishIndex({required this.loadShard});

  /// Reads the shard for a letter. Injected so tests need no asset bundle.
  final Future<String> Function(String letter) loadShard;

  /// Reads the shards shipped with the app.
  factory EnglishIndex.bundled([AssetBundle? bundle]) {
    final assets = bundle ?? rootBundle;
    return EnglishIndex(
      loadShard: (letter) =>
          assets.loadString('assets/dictionary/english/$letter.tsv'),
    );
  }

  final Map<String, Map<String, List<EnglishMeaning>>> _shards = {};

  /// The Chinese words for [english], best first, or empty if it is not a
  /// headword.
  ///
  /// Three tries, in order: what was typed, then without a leading article,
  /// then singular. The index is keyed on the bare headword CC-CEDICT glosses
  /// with — "toilet", not "the toilet"; "book", not "books" — and a learner
  /// typing English writes English.
  Future<List<EnglishMeaning>> lookUp(String english) async {
    for (final query in queriesFor(english)) {
      final shard = await _shard(_shardFor(query));
      final found = shard[query];
      if (found != null) return found;
    }
    return const [];
  }

  /// Every form of [english] worth looking up, in order of preference.
  ///
  /// Public for the sake of a test that pins the normalisation against the
  /// build tool's, which has to agree with it exactly or the index is keyed on
  /// something nobody can ask for.
  static List<String> queriesFor(String english) {
    final headword = normalise(english);
    if (headword.isEmpty) return const [];
    final queries = [headword];
    for (final article in const ['a ', 'an ', 'the ']) {
      if (headword.startsWith(article)) {
        queries.add(headword.substring(article.length));
      }
    }
    final singular = _singular(queries.last);
    if (singular != null) queries.add(singular);
    return queries;
  }

  /// [english] reduced to the shape the index is keyed on.
  ///
  /// Has to match `_headword` in `tool/build_dictionary.dart`, minus its
  /// length guard: that one decides what is worth storing, and this one only
  /// has to ask for it the same way. A test pins the two together.
  static String normalise(String english) {
    var word = english
        .replaceAll(_parenthetical, ' ')
        .toLowerCase()
        .replaceAll(_classifier, ' ')
        .replaceAll(_notAHeadword, ' ')
        .replaceAll(_whitespace, ' ')
        .trim();
    if (word.startsWith('to ')) word = word.substring(3);
    return word;
  }

  /// [word] made singular, or null where no rule applies.
  ///
  /// Three rules and no dictionary of exceptions. It is a fallback — the
  /// plural is looked up first and most plurals of words a learner types are
  /// regular — so a wrong guess costs a second miss, not a wrong answer.
  static String? _singular(String word) {
    if (word.endsWith('ies') && word.length > 4) {
      return '${word.substring(0, word.length - 3)}y';
    }
    for (final ending in const ['ches', 'shes', 'sses', 'xes']) {
      if (word.endsWith(ending)) {
        return word.substring(0, word.length - 2);
      }
    }
    if (word.endsWith('s') && !word.endsWith('ss') && word.length > 3) {
      return word.substring(0, word.length - 1);
    }
    return null;
  }

  /// Which shard a headword is in. Anything not starting with a letter — a
  /// number, an apostrophe — shares one.
  static String _shardFor(String headword) {
    final letter = headword[0];
    return _letter.hasMatch(letter) ? letter : '0';
  }

  Future<Map<String, List<EnglishMeaning>>> _shard(String letter) async {
    final loaded = _shards[letter];
    if (loaded != null) return loaded;

    String contents;
    try {
      contents = await loadShard(letter);
    } on Object {
      // A letter no headword starts with. Caught broadly for the same reason
      // the pinyin side does: a missing asset raises FlutterError, which is an
      // Error rather than an Exception.
      return _shards[letter] = const {};
    }

    final shard = <String, List<EnglishMeaning>>{};
    for (final line in contents.split('\n')) {
      if (line.isEmpty) continue;
      final fields = line.split('\t');
      if (fields.length < 2) continue;
      shard[fields[0]] = [
        for (final candidate in fields.skip(1))
          if (candidate.split('|') case [final key, final simplified])
            EnglishMeaning(key: key, simplified: simplified),
      ];
    }
    return _shards[letter] = shard;
  }
}

final _parenthetical = RegExp(r'\([^)]*\)');
final _classifier = RegExp(r'\bcl:.*');
final _notAHeadword = RegExp(r"[^a-z0-9'\- ]");
final _whitespace = RegExp(r'\s+');
final _letter = RegExp('[a-z]');
