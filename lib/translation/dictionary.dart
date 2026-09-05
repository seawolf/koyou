import 'package:flutter/services.dart';

/// One dictionary entry: a pinyin key, the word, and its English glosses.
class DictionaryEntry {
  const DictionaryEntry({
    required this.key,
    required this.simplified,
    required this.glosses,
    required this.properNoun,
    this.rank,
    this.hskLevel,
  });

  final String key;

  /// The word in simplified characters.
  ///
  /// Never shown — this app keeps characters off the learning surface — but
  /// kept because it is the bridge to everything else. Any translation service
  /// or model worth calling takes characters, not pinyin, so the value of this
  /// dictionary is as much in resolving pinyin to a word as in the glosses.
  final String simplified;

  final List<String> glosses;

  /// Whether CC-CEDICT capitalised the pinyin, which marks a name.
  final bool properNoun;

  /// How common the word is: 1 is the commonest in Mandarin, and null means it
  /// falls outside the HSK vocabulary altogether.
  ///
  /// This is what makes a pinyin lookup useful at all. CC-CEDICT lists forty
  /// words for `shi4` in no meaningful order, so without a rank the answer
  /// offered was whichever sorted first — "life", where the learner almost
  /// certainly meant 是, "to be", the fourth commonest word in the language.
  final int? rank;

  /// HSK band, 1 being the most elementary, or null if the word is not in it.
  final int? hskLevel;

  /// Order among candidates for the same pinyin: commonest first, unranked
  /// words after them, and among those, names and forms marked `(literary)` or
  /// `(bound form)` last.
  int compareForDisplay(DictionaryEntry other) {
    final mine = rank ?? _unranked;
    final theirs = other.rank ?? _unranked;
    if (mine != theirs) return mine.compareTo(theirs);
    return _tieBreak.compareTo(other._tieBreak);
  }

  static const _unranked = 1 << 30;

  int get _tieBreak =>
      (properNoun ? 2 : 0) + (glosses.first.startsWith('(') ? 1 : 0);
}

/// The CC-CEDICT lookup, read from the sharded assets.
///
/// Sharded by the key's first letter and parsed on demand, so a lookup touches
/// one file of at most about 650KB rather than holding 115,000 entries in
/// memory. Loaded shards are kept, since a learner keeps returning to the same
/// handful of letters.
class Dictionary {
  Dictionary({required this.loadShard});

  /// Reads the shard for a letter. Injected so tests need no asset bundle.
  final Future<String> Function(String letter) loadShard;

  /// Reads the shards shipped with the app.
  factory Dictionary.bundled([AssetBundle? bundle]) {
    final assets = bundle ?? rootBundle;
    return Dictionary(
      loadShard: (letter) => assets.loadString('assets/dictionary/$letter.tsv'),
    );
  }

  final Map<String, Map<String, List<DictionaryEntry>>> _shards = {};

  /// Entries for [key], best candidate first, or empty if it is not a word.
  Future<List<DictionaryEntry>> lookUp(String key) async {
    if (key.isEmpty) return const [];
    final shard = await _shard(key[0]);
    final entries = shard[key];
    if (entries == null) return const [];
    return entries.toList()..sort((a, b) => a.compareForDisplay(b));
  }

  Future<Map<String, List<DictionaryEntry>>> _shard(String letter) async {
    final loaded = _shards[letter];
    if (loaded != null) return loaded;

    String contents;
    try {
      contents = await loadShard(letter);
    } on Object {
      // No shard for that letter, which is not a fault: pinyin never starts a
      // syllable with i, u or v, so those shards are never built.
      //
      // Caught broadly on purpose. A missing asset raises FlutterError, which
      // is an Error and not an Exception, so `on Exception` let it through —
      // and reading a string has no other failure worth telling apart.
      return _shards[letter] = const {};
    }

    final shard = <String, List<DictionaryEntry>>{};
    for (final line in contents.split('\n')) {
      if (line.isEmpty) continue;
      final fields = line.split('\t');
      if (fields.length < 6) continue;
      shard
          .putIfAbsent(fields[0], () => [])
          .add(
            DictionaryEntry(
              key: fields[0],
              simplified: fields[1],
              properNoun: fields[2] == 'p',
              rank: int.tryParse(fields[3]),
              hskLevel: int.tryParse(fields[4]),
              glosses: fields[5].split('/'),
            ),
          );
    }
    return _shards[letter] = shard;
  }
}
