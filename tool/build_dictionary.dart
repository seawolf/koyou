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

/// HSK vocabulary with frequency ranks, MIT licensed.
///
/// CC-CEDICT has no frequency data at all, so on its own it cannot tell 是
/// ("to be", the fourth commonest word in Mandarin) from 世 or 仕. This is what
/// orders the candidates.
const hskSource =
    'https://raw.githubusercontent.com/drkameleon/complete-hsk-vocabulary/main/complete.json';

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

const _hanzi = r'[㐀-鿿豈-﫿]';

/// Any CJK ideograph.
final hasHanzi = RegExp(_hanzi);

/// A bracketed aside referring to another entry, such as the
/// "(informal, as opposed to courteous ...)" in the gloss for 你.
///
/// Removed whole, rather than having the characters picked out of it. Stripping
/// only the characters left "you (informal, as opposed to courteous)" at best
/// and subjectless prose at worst, and the useful half of that gloss is "you".
final bracketedReference = RegExp(r'\s*\([^()]*' + _hanzi + r'[^()]*\)');

/// A bare reference: characters, optionally a `|` variant form, optionally
/// followed by their pinyin in square brackets.
final bareReference = RegExp(
  _hanzi + r'+(?:\|' + _hanzi + r'+)?(?:\[[^\]]*\])?',
);

/// A gloss left hanging by the reference that used to complete it, as in
/// "euphemistic variant of" or "nude picture (from)".
final danglingWord = RegExp(
  r'\b(for|of|to|as|from|with|than|like|and|or|into|see|also'
  r'|in|on|at|by|before|after|used)$',
  caseSensitive: false,
);

Future<void> main(List<String> arguments) async {
  final input = _argument(arguments, '--input');
  final lines = input == null
      ? await _download()
      : await File(input).readAsLines();

  final hsk = await _loadHsk(_argument(arguments, '--hsk'));
  final shards = <String, List<String>>{};
  var parsed = 0;
  var unreachable = 0;
  var glossless = 0;
  var droppedGlosses = 0;
  var recoveredGlosses = 0;
  var ranked = 0;

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
      if (trimmed.isEmpty || crossReference.hasMatch(trimmed)) continue;
      if (!hasHanzi.hasMatch(trimmed)) {
        glosses.add(trimmed);
        continue;
      }
      final cleaned = _withoutReferences(trimmed);
      if (_usable(cleaned)) {
        glosses.add(cleaned);
        recoveredGlosses++;
      } else {
        droppedGlosses++;
      }
    }
    if (glosses.isEmpty) {
      glossless++;
      continue;
    }

    // Capitalised pinyin marks a proper noun, which breaks ties among the
    // unranked: `shi4` should not offer a newspaper before a verb.
    final proper = pinyin != pinyin.toLowerCase() ? 'p' : '-';
    final simplified = match.group(2)!;
    final rank = hsk.rankOf(simplified, key);
    if (rank != null) ranked++;

    shards
        .putIfAbsent(key[0], () => <String>[])
        .add(
          [
            key,
            simplified,
            proper,
            rank?.toString() ?? '-',
            hsk.levelOf(simplified, key)?.toString() ?? '-',
            glosses.join('/'),
          ].join('\t'),
        );
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
    ..writeln('  dropped $droppedGlosses glosses that were only a reference')
    ..writeln('  recovered $recoveredGlosses glosses by removing a reference')
    ..writeln('  ranked $ranked entries from HSK frequency data')
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

Future<List<String>> _download() async => (await _fetch(source)).split('\n');

/// A gloss with its references to other entries taken out.
String _withoutReferences(String gloss) {
  var cleaned = gloss;
  // Nested brackets mean this can need more than one pass.
  for (var pass = 0; pass < 3; pass++) {
    final next = cleaned.replaceAll(bracketedReference, '');
    if (next == cleaned) break;
    cleaned = next;
  }
  cleaned = cleaned
      .replaceAll(bareReference, '')
      .replaceAll(RegExp(r'\s+'), ' ')
      .replaceAll(RegExp(r'\(\s*[,;]?\s*\)'), '')
      .replaceAllMapped(RegExp(r'\s+([,;)])'), (m) => m.group(1)!)
      .replaceAll(RegExp(r'\(\s+'), '(')
      .trim();
  cleaned = cleaned.replaceAll(RegExp(r'^[ ,;|-]+|[ ,;|-]+$'), '');
  // A bracket left open by the removal reads worse than no brackets at all.
  final opens = cleaned.split('(').length;
  final closes = cleaned.split(')').length;
  if (opens != closes) {
    cleaned = cleaned
        .replaceAll('(', '')
        .replaceAll(')', '')
        .replaceAll(RegExp(r'^[ ,;]+|[ ,;]+$'), '');
  }
  return cleaned;
}

bool _usable(String gloss) =>
    gloss.length >= 2 &&
    !crossReference.hasMatch(gloss) &&
    !danglingWord.hasMatch(gloss.replaceAll(RegExp(r'[).,; ]+$'), ''));

/// Frequency ranks and HSK levels, looked up by word and reading.
class _Hsk {
  _Hsk(this.wordRank, this.characterRank, this.wordLevel);

  /// Rank for an exact word in an exact reading.
  final Map<String, int> wordRank;

  /// Rank for a single character in a reading, taken from the commonest HSK
  /// word that contains it with that reading.
  ///
  /// 谢 is not an HSK word on its own, but 谢谢 is and is common, so the
  /// character earns its rank from the company it keeps. The reading has to
  /// match: 解 is common as `jie3` and rare as `xie4`, and crediting the
  /// second with the first's rank is how "acrobatic display" outranked
  /// "to thank".
  final Map<String, int> characterRank;

  final Map<String, int> wordLevel;

  int? rankOf(String simplified, String key) =>
      wordRank['$simplified|$key'] ??
      (simplified.length == 1 ? characterRank['$simplified|$key'] : null);

  int? levelOf(String simplified, String key) => wordLevel['$simplified|$key'];
}

/// CC-CEDICT writes ü as `u:`; the HSK data writes it as ü. Without this the
/// join silently misses every ü word — nǚ, lǜ, and the rest.
String _normaliseReading(String numeric) =>
    numeric.toLowerCase().replaceAll('ü', 'u:');

Future<_Hsk> _loadHsk(String? input) async {
  final text = input == null
      ? await _fetch(hskSource)
      : await File(input).readAsString();
  final entries = jsonDecode(text) as List<dynamic>;

  final wordRank = <String, int>{};
  final characterRank = <String, int>{};
  final wordLevel = <String, int>{};

  for (final entry in entries.cast<Map<String, dynamic>>()) {
    final rank = entry['frequency'];
    if (rank is! int) continue;
    final word = entry['simplified'] as String;

    // Levels come in three schemes (old, new, newest); the lowest band across
    // them is the most useful single answer to "how basic is this word".
    var level = 0;
    for (final label
        in (entry['level'] as List<dynamic>? ?? []).cast<String>()) {
      final digits = RegExp(r'(\d+)').firstMatch(label)?.group(1);
      final parsed = digits == null ? 0 : int.parse(digits);
      if (parsed > 0 && (level == 0 || parsed < level)) level = parsed;
    }

    for (final form
        in (entry['forms'] as List<dynamic>).cast<Map<String, dynamic>>()) {
      final transcriptions = form['transcriptions'] as Map<String, dynamic>?;
      final numeric = transcriptions?['numeric'] as String?;
      if (numeric == null) continue;
      final reading = _normaliseReading(numeric);

      void keepLowest(Map<String, int> into, String key, int value) {
        final existing = into[key];
        if (existing == null || value < existing) into[key] = value;
      }

      keepLowest(wordRank, '$word|$reading', rank);
      if (level > 0) keepLowest(wordLevel, '$word|$reading', level);

      final syllables = reading.split(' ');
      if (syllables.length != word.length) continue;
      for (var index = 0; index < syllables.length; index++) {
        keepLowest(characterRank, '${word[index]}|${syllables[index]}', rank);
      }
    }
  }
  return _Hsk(wordRank, characterRank, wordLevel);
}

Future<String> _fetch(String url) async {
  stdout.writeln('Downloading $url');
  final client = HttpClient();
  try {
    final request = await client.getUrl(Uri.parse(url));
    final response = await request.close();
    if (response.statusCode != 200) {
      throw HttpException('${response.statusCode} from $url');
    }
    final bytes = await response.fold<List<int>>(
      <int>[],
      (all, chunk) => all..addAll(chunk),
    );
    return utf8.decode(url.endsWith('.gz') ? gzip.decode(bytes) : bytes);
  } finally {
    client.close();
  }
}
