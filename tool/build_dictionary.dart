// Turns the CC-CEDICT export into the sharded assets the app looks words up in.
//
// CC-CEDICT is Creative Commons Attribution-ShareAlike 4.0. The generated
// assets carry the same licence, and the app credits it on screen — see
// `DictionaryCredit` and assets/dictionary/LICENCE.
//
// Usage, from the repository root:
//
//   dart run tool/build_dictionary.dart                 # downloads the export
//   dart run tool/build_dictionary.dart --input FILE     # uses a local copy
//
// Plain Dart on purpose: it imports nothing from Flutter, so any Dart SDK on
// the PATH can run it.
import 'dart:convert';
import 'dart:io';

const source =
    'https://www.mdbg.net/chinese/export/cedict/cedict_1_0_ts_utf-8_mdbg.txt.gz';

const outputDirectory = 'assets/dictionary';

/// One CC-CEDICT line: traditional, simplified, [pinyin], then /glosses/.
final entryPattern = RegExp(r'^(\S+) (\S+) \[([^\]]*)\] /(.*)/$');

/// A key the app's keyboard could actually produce: syllables of Latin letters
/// or `u:`, each ending in a tone number, separated by single spaces.
///
/// Everything else is unreachable — CC-CEDICT also carries entries keyed on
/// digits (`110`), on names with a middle dot, and on letters pinyin never
/// starts a syllable with — so dropping them costs nothing and keeps the
/// shards to the letters the keyboard can reach.
final reachableKey = RegExp(r'^[a-z:]+[1-5](?: [a-z:]+[1-5])*$');

/// Glosses that are only a pointer to another entry. Useful in a dictionary
/// you read, useless here: they are meaningless without the characters they
/// point at, and this app deliberately keeps characters off the screen.
final crossReference = RegExp(
  r'^(old |erhua form of |see |see also |variant of |abbr\.|surname )',
  caseSensitive: false,
);

/// Any CJK ideograph. A gloss containing one is a cross-reference in prose
/// form, and would put characters in front of a learner who is here not to
/// read them.
final hasHanzi = RegExp(r'[㐀-鿿豈-﫿]');

Future<void> main(List<String> arguments) async {
  final input = _argument(arguments, '--input');
  final lines = input == null
      ? await _download()
      : await File(input).readAsLines();

  final shards = <String, List<String>>{};
  var parsed = 0;
  var unreachable = 0;
  var glossless = 0;
  var droppedGlosses = 0;

  for (final line in lines) {
    if (line.startsWith('#') || line.trim().isEmpty) continue;
    final match = entryPattern.firstMatch(line);
    if (match == null) continue;
    parsed++;

    final pinyin = match.group(3)!;
    final key = pinyin.toLowerCase().replaceAll(RegExp(r'\s+'), ' ').trim();
    if (!reachableKey.hasMatch(key)) {
      unreachable++;
      continue;
    }

    final glosses = <String>[];
    for (final gloss in match.group(4)!.split('/')) {
      final trimmed = gloss.trim();
      if (trimmed.isEmpty) continue;
      if (hasHanzi.hasMatch(trimmed) || crossReference.hasMatch(trimmed)) {
        droppedGlosses++;
        continue;
      }
      glosses.add(trimmed);
    }
    if (glosses.isEmpty) {
      glossless++;
      continue;
    }

    // Capitalised pinyin marks a proper noun. Recorded because the lookup
    // needs it to rank: `shi4` should offer "to be" before a newspaper.
    final proper = pinyin != pinyin.toLowerCase() ? 'p' : '-';
    final simplified = match.group(2)!;

    shards
        .putIfAbsent(key[0], () => <String>[])
        .add([key, simplified, proper, glosses.join('/')].join('\t'));
  }

  final directory = Directory(outputDirectory);
  if (directory.existsSync()) directory.deleteSync(recursive: true);
  directory.createSync(recursive: true);

  var total = 0;
  var bytes = 0;
  final letters = shards.keys.toList()..sort();
  for (final letter in letters) {
    final rows = shards[letter]!..sort();
    final file = File('$outputDirectory/$letter.tsv');
    file.writeAsStringSync('${rows.join('\n')}\n');
    total += rows.length;
    bytes += file.lengthSync();
  }

  File('$outputDirectory/LICENCE').writeAsStringSync(
    'The files in this directory are generated from CC-CEDICT by\n'
    'tool/build_dictionary.dart, and carry its licence.\n\n'
    'CC-CEDICT, published by MDBG, community maintained.\n'
    'Creative Commons Attribution-ShareAlike 4.0 International\n'
    'https://creativecommons.org/licenses/by-sa/4.0/\n'
    'Source: $source\n',
  );

  stdout
    ..writeln('Parsed $parsed entries from CC-CEDICT')
    ..writeln('  dropped $unreachable the keyboard cannot reach')
    ..writeln('  dropped $glossless left with no usable gloss')
    ..writeln('  dropped $droppedGlosses individual cross-reference glosses')
    ..writeln(
      'Wrote $total entries over ${letters.length} shards '
      '(${letters.join(' ')})',
    )
    ..writeln(
      '  ${(bytes / 1048576).toStringAsFixed(2)} MB total, '
      'largest ${_largest(shards)}',
    );
}

String _largest(Map<String, List<String>> shards) {
  final letter = shards.keys.reduce(
    (a, b) => shards[a]!.length >= shards[b]!.length ? a : b,
  );
  final size = File('$outputDirectory/$letter.tsv').lengthSync();
  return '$letter at ${(size / 1024).toStringAsFixed(0)} KB';
}

String? _argument(List<String> arguments, String name) {
  final index = arguments.indexOf(name);
  return index >= 0 && index + 1 < arguments.length
      ? arguments[index + 1]
      : null;
}

Future<List<String>> _download() async {
  stdout.writeln('Downloading $source');
  final client = HttpClient();
  try {
    final request = await client.getUrl(Uri.parse(source));
    final response = await request.close();
    if (response.statusCode != 200) {
      throw HttpException('${response.statusCode} from $source');
    }
    final compressed = await response.fold<List<int>>(
      <int>[],
      (all, chunk) => all..addAll(chunk),
    );
    return utf8.decode(gzip.decode(compressed)).split('\n');
  } finally {
    client.close();
  }
}
