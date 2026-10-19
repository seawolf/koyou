// Picks one example sentence per word from Tatoeba, for the translate screen.
//
// Tatoeba is community-written and community-translated, under CC BY 2.0 FR.
// The generated shards carry that licence and the app credits it on screen —
// see assets/examples/LICENCE.
//
// Usage, from the repository root, after tool/build_dictionary.dart:
//
//   dart run tool/build_examples.dart
//
// It reads the dictionary's own output — the character index, to read each
// sentence back as words, and the English index, to know which words the
// translate screen can offer — so it has to run second. Downloads are cached
// under .dart_tool/tatoeba, which git ignores.
//
// Plain Dart on purpose, like the dictionary tool: any Dart SDK can run it.
import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';

const exports = 'https://downloads.tatoeba.org/exports';
const cache = '.dart_tool/tatoeba';
const outputDirectory = 'assets/examples';

/// Tags Tatoeba's own reviewers put on sentences that should not be shown as
/// models of usage, plus kinds that are real Mandarin but not plain usage.
///
/// The `@` tags are review flags: a native speaker has asked for a check, a
/// change, or a deletion. "Tatoeba" marks sentences about the site itself —
/// "the Japanese 'Tatoeba' means 'for example'" was the first one offered for
/// 例如. Quotations and set idioms are fine Mandarin, but an example of how a
/// word is used should not be a line of Mao or a four-character chengyu.
const excludedTags = {
  '@needs native check',
  '@change',
  '@check translation',
  '@change punctuation',
  '@wrong transliteration',
  '@delete',
  '@possible copyright infringement',
  'Tatoeba',
  'quote',
  'by Mao Zedong',
  '成语',
  'idiom',
  'proverb',
};

final _aboutTatoeba = RegExp('tatoeba', caseSensitive: false);

/// Sentences longer than this are not an example of a word, they are a text.
const longest = 24;

Future<void> main() async {
  final readings = _readings();
  final offered = _offered();
  stdout.writeln(
    'Read ${readings.length} readings and ${offered.length} offered words',
  );

  final mandarin = _table(await _fetch('per_language/cmn/cmn_sentences.tsv'));
  final pairs = <String, String>{};
  for (final row in _rows(await _fetch('per_language/cmn/cmn-eng_links.tsv'))) {
    if (row.length >= 2) pairs.putIfAbsent(row[0], () => row[1]);
  }
  final wanted = pairs.values.toSet();
  final english = <String, String>{};
  for (final row in _rows(await _fetch('per_language/eng/eng_sentences.tsv'))) {
    if (row.length >= 3 && wanted.contains(row[0])) english[row[0]] = row[2];
  }
  final flagged = <String>{};
  for (final row in _rows(await _fetch('tags.csv', archive: 'tags.tar'))) {
    if (row.length >= 2 && excludedTags.contains(row[1])) flagged.add(row[0]);
  }

  // The best sentence for each word, and where in it the word sits.
  final best = <String, _Pick>{};
  var usable = 0;
  for (final MapEntry(key: id, value: text) in mandarin.entries) {
    final translation = english[pairs[id]];
    if (translation == null || flagged.contains(id)) continue;
    // Sentences about the corpus itself, which its own tag does not always
    // catch: "the Japanese 'Tatoeba' means 'for example'" was untagged, and
    // was being offered as the example of 例如.
    if (_aboutTatoeba.hasMatch(text) || _aboutTatoeba.hasMatch(translation)) {
      continue;
    }
    final words = _segment(text, readings);
    if (words == null) continue;
    final han = words.fold<int>(0, (sum, word) => sum + word.text.length);
    if (han < 3 || han > longest) continue;
    usable++;

    final score = _score(text, words, readings);
    for (final word in words) {
      if (!offered.contains(word.text)) continue;
      final known = best[word.text];
      if (known == null || _better(score, known.score)) {
        best[word.text] = _Pick(
          text: text,
          offset: word.offset,
          english: translation,
          score: score,
        );
      }
    }
  }

  if (best.length < 1000) {
    throw StateError(
      'Only ${best.length} words found an example, which is far below what a '
      'real build gives. Refusing to overwrite $outputDirectory.',
    );
  }

  final directory = Directory(outputDirectory);
  if (directory.existsSync()) directory.deleteSync(recursive: true);
  directory.createSync(recursive: true);

  final shards = <String, List<String>>{};
  for (final MapEntry(key: word, value: pick) in best.entries) {
    shards
        .putIfAbsent(_shardFor(word), () => [])
        .add([word, pick.offset, pick.text, pick.english].join('\t'));
  }
  var bytes = 0;
  for (final name in shards.keys.toList()..sort()) {
    final file = File('$outputDirectory/$name.tsv');
    file.writeAsStringSync('${(shards[name]!..sort()).join('\n')}\n');
    bytes += file.lengthSync();
  }
  File('$outputDirectory/LICENCE').writeAsStringSync(
    'The files in this directory are selected from Tatoeba by\n'
    'tool/build_examples.dart, and carry its licence.\n\n'
    'Tatoeba (https://tatoeba.org), sentences and translations written by its\n'
    'contributors. Creative Commons Attribution 2.0 France.\n'
    'https://creativecommons.org/licenses/by/2.0/fr/\n'
    'Source: $exports\n',
  );

  stdout
    ..writeln('Tatoeba: ${mandarin.length} Mandarin sentences')
    ..writeln('  ${english.length} with an English translation')
    ..writeln('  ${flagged.length} tagged as not to be shown')
    ..writeln('  $usable usable: simplified, fully readable, unflagged')
    ..writeln(
      'Wrote examples for ${best.length} words over ${shards.length} shards '
      '(${(bytes / 1024).round()} KB)',
    );
}

/// One sentence chosen for a word.
class _Pick {
  _Pick({
    required this.text,
    required this.offset,
    required this.english,
    required this.score,
  });

  final String text;

  /// Where the word starts in [text], so the screen can show it in the
  /// reading it was offered with rather than whatever the sentence reads it as.
  final int offset;
  final String english;
  final (int, int, int) score;
}

/// Lower is a better example: as few words outside the syllabus as possible,
/// no names in Latin letters, then the shortest.
///
/// Easy vocabulary first, because the sentence is there to show one word and
/// every other unfamiliar word in it is noise. It also turns out to be what
/// keeps the plain sentences: the opinionated ones a corpus like this
/// collects tend to need harder words.
(int, int, int) _score(
  String text,
  List<_Segment> words,
  Map<String, ({String key, bool ranked})> readings,
) {
  final hard = words.where((word) => !readings[word.text]!.ranked).length;
  final latin = RegExp('[A-Za-z]').hasMatch(text) ? 1 : 0;
  final han = words.fold<int>(0, (sum, word) => sum + word.text.length);
  return (hard, latin, han);
}

/// Whether [a] scores lower than [b], comparing in order.
bool _better((int, int, int) a, (int, int, int) b) {
  if (a.$1 != b.$1) return a.$1 < b.$1;
  if (a.$2 != b.$2) return a.$2 < b.$2;
  return a.$3 < b.$3;
}

/// A word found in a sentence, and where.
class _Segment {
  _Segment(this.text, this.offset);
  final String text;
  final int offset;
}

/// The sentence as dictionary words by longest match, the way
/// `CharacterIndex` reads it at run time, or null if any character is not one
/// it can read.
///
/// Null is what drops the traditional-character half of Tatoeba's Mandarin:
/// the index holds simplified forms only, so a sentence with 們 in it cannot be
/// read, and could not be shown as pinyin either.
List<_Segment>? _segment(
  String text,
  Map<String, ({String key, bool ranked})> readings,
) {
  final words = <_Segment>[];
  var at = 0;
  while (at < text.length) {
    if (!_isHan(text.codeUnitAt(at))) {
      at++;
      continue;
    }
    var length = text.length - at < _longestWord
        ? text.length - at
        : _longestWord;
    for (; length > 0; length--) {
      if (readings.containsKey(text.substring(at, at + length))) break;
    }
    if (length == 0) return null;
    words.add(_Segment(text.substring(at, at + length), at));
    at += length;
  }
  return words.isEmpty ? null : words;
}

var _longestWord = 1;

/// The character index, as `tool/build_dictionary.dart` wrote it.
Map<String, ({String key, bool ranked})> _readings() {
  final readings = <String, ({String key, bool ranked})>{};
  for (final file in Directory('assets/dictionary/characters').listSync()) {
    if (file is! File || !file.path.endsWith('.tsv')) continue;
    for (final line in const LineSplitter().convert(file.readAsStringSync())) {
      final fields = line.split('\t');
      if (fields.length < 3) continue;
      readings[fields[0]] = (key: fields[1], ranked: fields[2] != '-');
      if (fields[0].length > _longestWord) _longestWord = fields[0].length;
    }
  }
  if (readings.isEmpty) {
    throw StateError(
      'No character index. Run tool/build_dictionary.dart first.',
    );
  }
  return readings;
}

/// Every word the English index can offer, which is every word an example
/// could be shown beside.
Set<String> _offered() {
  final offered = <String>{};
  for (final file in Directory('assets/dictionary/english').listSync()) {
    if (file is! File || !file.path.endsWith('.tsv')) continue;
    for (final line in const LineSplitter().convert(file.readAsStringSync())) {
      for (final candidate in line.split('\t').skip(1)) {
        final parts = candidate.split('|');
        if (parts.length == 2) offered.add(parts[1]);
      }
    }
  }
  return offered;
}

/// Same rule as `CharacterIndex.shardFor` and the character index's shards.
String _shardFor(String word) =>
    (word.codeUnitAt(0) >> 8).toRadixString(16).padLeft(2, '0');

bool _isHan(int unit) =>
    (unit >= 0x4e00 && unit <= 0x9fff) ||
    (unit >= 0x3400 && unit <= 0x4dbf) ||
    (unit >= 0xd800 && unit <= 0xdfff);

Map<String, String> _table(String tsv) => {
  for (final row in _rows(tsv))
    if (row.length >= 3) row[0]: row[2],
};

Iterable<List<String>> _rows(String tsv) =>
    const LineSplitter().convert(tsv).map((line) => line.split('\t'));

/// A Tatoeba export, decompressed, downloading it once and keeping it.
///
/// [archive] names the tarball a file comes in, for the exports Tatoeba only
/// publishes that way.
Future<String> _fetch(String path, {String? archive}) async {
  final name = path.split('/').last;
  final kept = File('$cache/$name');
  if (kept.existsSync()) return kept.readAsString();

  final remote = archive == null ? '$path.bz2' : '$archive.bz2';
  stdout.writeln('Downloading $exports/$remote');
  final client = HttpClient();
  try {
    final response = await (await client.getUrl(Uri.parse('$exports/$remote')))
        .close();
    if (response.statusCode != 200) {
      throw HttpException('${response.statusCode} from $remote');
    }
    final compressed = await response.fold<List<int>>(
      <int>[],
      (all, chunk) => all..addAll(chunk),
    );
    var bytes = BZip2Decoder().decodeBytes(compressed);
    if (archive != null) {
      final inside = TarDecoder().decodeBytes(bytes);
      bytes = inside.findFile(name)!.readBytes()!;
    }
    final text = utf8.decode(bytes);
    kept
      ..createSync(recursive: true)
      ..writeAsStringSync(text);
    return text;
  } finally {
    client.close();
  }
}
