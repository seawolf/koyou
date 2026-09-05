import 'package:flutter/services.dart';

/// One dictionary entry: a pinyin key, the word, and its English glosses.
class DictionaryEntry {
  const DictionaryEntry({
    required this.key,
    required this.simplified,
    required this.glosses,
    required this.properNoun,
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

  /// Rough obscurity, for ordering candidates.
  ///
  /// A weak signal, and known to be weak: CC-CEDICT carries no frequency data,
  /// so there is nothing here that reliably puts `有` ahead of `黝` for `you3`.
  /// It does at least push names and forms marked `(literary)`, `(archaic)` or
  /// `(bound form)` below plain ones.
  int get obscurity =>
      (properNoun ? 2 : 0) + (glosses.first.startsWith('(') ? 1 : 0);
}

/// The CC-CEDICT lookup, read from the sharded assets.
///
/// Sharded by the key's first letter and parsed on demand, so a lookup touches
/// one file of at most about 550KB rather than holding 109,000 entries in
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
    return entries.toList()..sort((a, b) => a.obscurity.compareTo(b.obscurity));
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
      if (fields.length < 4) continue;
      shard
          .putIfAbsent(fields[0], () => [])
          .add(
            DictionaryEntry(
              key: fields[0],
              simplified: fields[1],
              properNoun: fields[2] == 'p',
              glosses: fields[3].split('/'),
            ),
          );
    }
    return _shards[letter] = shard;
  }
}
