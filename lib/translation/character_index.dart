import 'package:flutter/services.dart';

import '../pinyin/reading.dart';
import '../pinyin/word.dart';

/// Simplified characters to the pinyin they are read with.
///
/// The bridge back. Chinese to English works by resolving pinyin to characters
/// and letting a model translate those, because models cannot read tone-marked
/// pinyin; English to Chinese works by letting a model answer in characters,
/// which it is good at, and turning those into pinyin here. Either way the
/// tones come from the dictionary and never from the model.
///
/// Sharded on where the first character sits in Unicode — the high byte of its
/// code unit — which splits the CJK block into about a hundred files of ~30KB.
/// Sharding by the character itself would mean ten thousand files; not
/// sharding would mean parsing 2.7MB to read one sentence back.
class CharacterIndex {
  CharacterIndex({required this.loadShard});

  /// Reads the shard for a bucket. Injected so tests need no asset bundle.
  final Future<String> Function(String shard) loadShard;

  /// Reads the shards shipped with the app.
  factory CharacterIndex.bundled([AssetBundle? bundle]) {
    final assets = bundle ?? rootBundle;
    return CharacterIndex(
      loadShard: (shard) =>
          assets.loadString('assets/dictionary/characters/$shard.tsv'),
    );
  }

  final Map<String, _Shard> _shards = {};

  /// [chinese] as pinyin words, or null if any of it cannot be read.
  ///
  /// The word breaks are the dictionary's, which is the quiet win here: a
  /// model writes 明天我要去北京 with no spaces at all, and what comes back is
  /// `míngtiān wǒ yào qù běijīng` in five words a learner can edit one at a
  /// time.
  ///
  /// Null rather than a partial answer, and null for anything with no Chinese
  /// in it. A line with one syllable missing is not a line anybody can say,
  /// and the caller — see `EnglishModelTranslator` — would rather offer
  /// nothing than something with a hole in it.
  Future<List<Word>?> read(String chinese) async {
    final words = <Word>[];
    var at = 0;
    while (at < chinese.length) {
      if (!_isHan(chinese.codeUnitAt(at))) {
        final was = at;
        while (at < chinese.length && !_isHan(chinese.codeUnitAt(at))) {
          at++;
        }
        // Latin letters are carried through as they are: a model writing a
        // foreign name writes it in Latin, exactly as Chinese does. Anything
        // else in the gap is punctuation, and this app has none.
        final between = chinese.substring(was, at);
        final literal = between.replaceAll(_notLiteral, ' ').trim();
        if (literal.isNotEmpty) words.add(Literal(literal));
        continue;
      }

      final match = await _longestFrom(chinese, at);
      if (match == null) return null;
      final syllables = syllablesFor(match.key);
      // A word the dictionary knows but the keyboard cannot build — the erhua
      // suffix, an interjection. Rare enough to decline over.
      if (syllables == null) return null;
      words.add(Spoken(syllables));
      at += match.length;
    }
    // No Chinese in it at all is not an answer, whatever else came through.
    // A model that loses its footing and replies in English would otherwise
    // have its English handed back as the pinyin to say.
    return words.any((word) => word is Spoken) ? words : null;
  }

  /// The longest word starting at [at], or null if not even the one character
  /// is in the dictionary.
  ///
  /// Longest match wins, which is the whole reason this reads as Mandarin
  /// rather than as a character list: 明天 is one word and `míngtiān`, not
  /// `míng tiān`.
  Future<({String key, int length})?> _longestFrom(
    String chinese,
    int at,
  ) async {
    final shard = await _shard(shardFor(chinese, at));
    final longest = chinese.length - at < shard.longest
        ? chinese.length - at
        : shard.longest;
    for (var length = longest; length > 0; length--) {
      final key = shard.readings[chinese.substring(at, at + length)];
      if (key != null) return (key: key, length: length);
    }
    return null;
  }

  /// Which shard the word starting at [at] would be found in.
  ///
  /// Has to agree exactly with `charactersShardFor` in
  /// `tool/build_dictionary.dart`. Pinned by a test that names a real shard
  /// and checks it is the one holding the character.
  static String shardFor(String chinese, [int at = 0]) =>
      (chinese.codeUnitAt(at) >> 8).toRadixString(16).padLeft(2, '0');

  Future<_Shard> _shard(String name) async {
    final loaded = _shards[name];
    if (loaded != null) return loaded;

    String contents;
    try {
      contents = await loadShard(name);
    } on Object {
      // A Unicode bucket no Chinese word starts in. Caught broadly: a missing
      // asset raises FlutterError, which is an Error and not an Exception.
      return _shards[name] = const _Shard({}, 1);
    }

    final readings = <String, String>{};
    var longest = 1;
    for (final line in contents.split('\n')) {
      if (line.isEmpty) continue;
      final fields = line.split('\t');
      if (fields.length < 2) continue;
      readings[fields[0]] = fields[1];
      if (fields[0].length > longest) longest = fields[0].length;
    }
    return _shards[name] = _Shard(readings, longest);
  }
}

/// One parsed shard, and how far back a longest-match has to look in it.
class _Shard {
  const _Shard(this.readings, this.longest);

  final Map<String, String> readings;

  /// The longest word in this shard, so the search starts at a length that
  /// could actually match rather than at the length of the sentence.
  final int longest;
}

/// Whether a code unit is a Chinese character.
///
/// The CJK unified block, plus the surrogate range, which is where the rarer
/// characters live. A false positive costs a dictionary miss, which is
/// handled; a false negative would put a character into a [Literal].
bool _isHan(int unit) =>
    (unit >= 0x4e00 && unit <= 0x9fff) ||
    (unit >= 0x3400 && unit <= 0x4dbf) ||
    (unit >= 0xd800 && unit <= 0xdfff);

/// Anything in a gap between Chinese that is not worth carrying: Chinese
/// punctuation, Latin punctuation, digits' surrounding clutter.
final _notLiteral = RegExp(r"[^A-Za-z0-9'\- ]");
