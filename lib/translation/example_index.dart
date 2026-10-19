import 'package:flutter/services.dart';

import 'character_index.dart';

/// One sentence chosen to show a word in use, as `tool/build_examples.dart`
/// wrote it: the sentence in characters, where the word starts in it, and its
/// English.
typedef ExampleSentence = ({String chinese, int offset, String english});

/// Example sentences from Tatoeba, one per word.
///
/// Written and translated by people, not generated. The model was tried
/// first and it quietly swapped the word it was given for a commoner one —
/// asked for 月球 it wrote 月亮, asked for 逝世 it wrote 去世 — which is
/// exactly the distinction an example is there to show. See
/// `docs/local-model.md`.
///
/// Sharded the way the character index is, by where the word's first
/// character sits in Unicode, so a lookup reads one file of about 11KB.
class ExampleIndex {
  ExampleIndex({required this.loadShard});

  /// Reads the shard for a bucket. Injected so tests need no asset bundle.
  final Future<String> Function(String shard) loadShard;

  /// Reads the shards shipped with the app.
  factory ExampleIndex.bundled([AssetBundle? bundle]) {
    final assets = bundle ?? rootBundle;
    return ExampleIndex(
      loadShard: (shard) => assets.loadString('assets/examples/$shard.tsv'),
    );
  }

  final Map<String, Map<String, ExampleSentence>> _shards = {};

  /// The sentence chosen for [word], in simplified characters, or null.
  Future<ExampleSentence?> find(String word) async {
    if (word.isEmpty) return null;
    final name = CharacterIndex.shardFor(word);
    final shard = _shards[name] ??= await _load(name);
    return shard[word];
  }

  Future<Map<String, ExampleSentence>> _load(String name) async {
    String contents;
    try {
      contents = await loadShard(name);
    } on Object {
      // No word starting in this part of Unicode has an example. Caught
      // broadly: a missing asset raises FlutterError, an Error.
      return const {};
    }
    final shard = <String, ExampleSentence>{};
    for (final line in contents.split('\n')) {
      final fields = line.split('\t');
      if (fields.length < 4) continue;
      final offset = int.tryParse(fields[1]);
      if (offset == null) continue;
      shard[fields[0]] = (
        chinese: fields[2],
        offset: offset,
        english: fields[3],
      );
    }
    return shard;
  }
}
