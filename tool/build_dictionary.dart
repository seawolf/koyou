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

/// English headword to the Chinese words that mean it.
///
/// The same data read the other way round. CC-CEDICT is a Chinese-to-English
/// dictionary, so this is an inversion of it rather than a translation
/// resource in its own right, and it inherits that: it is good on words and
/// silent on sentences.
const englishDirectory = '$outputDirectory/english';

/// Simplified characters to the pinyin they are read with.
///
/// The bridge back. A model asked for Chinese answers in characters — which
/// is what it is good at — and this is what turns those characters into
/// tone-marked pinyin, deterministically, so the model never has to produce a
/// tone mark. See `docs/local-model.md`.
const charactersDirectory = '$outputDirectory/characters';

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

  // Parsed once, emitted once the readings have been settled: how often a
  // character is used in a reading is itself evidence of which reading it is
  // really used in, and that cannot be counted until every entry is read.
  final usable =
      <
        ({String key, String simplified, String proper, List<String> glosses})
      >[];
  final cedictUses = <String, int>{};

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
    usable.add((
      key: key,
      simplified: simplified,
      proper: proper,
      glosses: glosses,
    ));

    // Only words of two or more syllables count, for the same reason the HSK
    // side excludes them: a single character cannot be evidence of its own
    // reading.
    final syllables = key.split(' ');
    if (syllables.length < 2 || syllables.length != simplified.length) continue;
    for (var index = 0; index < syllables.length; index++) {
      final at = '${simplified[index]}|${syllables[index]}';
      cedictUses[at] = (cedictUses[at] ?? 0) + 1;
    }
  }

  hsk.resolveDominance(cedictUses);

  // The two inversions of the same data, collected as the entries are
  // emitted so nothing is parsed twice.
  final english = <String, List<_Meaning>>{};
  final characters = <String, _Reading>{};

  for (final entry in usable) {
    final rank = hsk.rankOf(entry.simplified, entry.key);
    final level = hsk.levelOf(entry.simplified, entry.key);
    if (rank != null) ranked++;

    // Names are kept out of the English index and kept in the character one.
    // Looking up "hope" should not offer a county in Arkansas; rendering
    // 史蒂夫 back to `shǐdìfū` has to work, because a model writing a foreign
    // name is the commonest reason it emits one.
    if (entry.proper != 'p') {
      final meanings = _meanings(
        glosses: entry.glosses,
        key: entry.key,
        simplified: entry.simplified,
        rank: rank,
        syllabus: level != null,
      );
      for (final meaning in meanings) {
        english.putIfAbsent(meaning.headword, () => <_Meaning>[]).add(meaning);
      }
    }

    final reading = _Reading(key: entry.key, rank: rank);
    final known = characters[entry.simplified];
    if (known == null || reading.beats(known)) {
      characters[entry.simplified] = reading;
    }

    shards
        .putIfAbsent(entry.key[0], () => <String>[])
        .add(
          [
            entry.key,
            entry.simplified,
            entry.proper,
            rank?.toString() ?? '-',
            level?.toString() ?? '-',
            entry.glosses.join('/'),
          ].join('\t'),
        );
  }
  final total = shards.values.fold<int>(0, (sum, rows) => sum + rows.length);

  // Refuse to publish an implausibly small build. Everything below this line
  // deletes the existing shards first, so a source that fetches but does not
  // parse — a changed export format, an error page served with a 200, the CRLF
  // bug above — would otherwise replace a working dictionary with a stub and
  // report success. A real build is around 115,000 entries.
  const leastCredible = 50000;
  if (total < leastCredible) {
    throw StateError(
      'Only $total entries survived the build, which is far below the '
      '$leastCredible expected. Refusing to overwrite $outputDirectory. '
      'Check the source format before rerunning.',
    );
  }

  final directory = Directory(outputDirectory);
  if (directory.existsSync()) directory.deleteSync(recursive: true);
  directory.createSync(recursive: true);

  var bytes = 0;
  final letters = shards.keys.toList()..sort();
  for (final letter in letters) {
    final rows = shards[letter]!..sort();
    final file = File('$outputDirectory/$letter.tsv');
    file.writeAsStringSync('${rows.join('\n')}\n');
    bytes += file.lengthSync();
  }

  final englishBytes = _writeShards(englishDirectory, _englishRows(english));
  final characterBytes = _writeShards(
    charactersDirectory,
    _characterRows(characters),
  );

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
    )
    ..writeln(
      'Wrote ${english.length} English headwords '
      '(${(englishBytes / 1048576).toStringAsFixed(2)} MB)',
    )
    ..writeln(
      'Wrote ${characters.length} character readings '
      '(${(characterBytes / 1048576).toStringAsFixed(2)} MB)',
    );
}

/// Writes one row per key into shards named by [rows]' own grouping.
int _writeShards(String into, Map<String, List<String>> rows) {
  final directory = Directory(into);
  directory.createSync(recursive: true);
  var bytes = 0;
  for (final shard in rows.keys.toList()..sort()) {
    final file = File('$into/$shard.tsv');
    file.writeAsStringSync('${(rows[shard]!..sort()).join('\n')}\n');
    bytes += file.lengthSync();
  }
  return bytes;
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

/// CC-CEDICT ships CRLF line endings, so this splits on line terminators
/// rather than on '\n'. Splitting on '\n' alone leaves a '\r' on the end of
/// every line, which the `/$` anchor in [entryPattern] will not match — the
/// download path then parses nothing while the `--input` path, which uses
/// `readAsLines`, works fine.
Future<List<String>> _download() async =>
    const LineSplitter().convert(await _fetch(source));

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
  _Hsk({
    required this.wordRank,
    required this.compoundRank,
    required this.readings,
    required this.wordLevel,
  });

  /// Rank for an exact word in an exact reading.
  ///
  /// Per *word*, despite the key: the source gives one `frequency` and lists
  /// every reading of the word beneath it, so this map on its own cannot say
  /// which reading earned the number. [rankOf] is what decides that.
  final Map<String, int> wordRank;

  /// Rank for a single character in a reading, from the commonest HSK word of
  /// two or more characters containing it with that reading.
  ///
  /// 谢 is not an HSK word on its own, but 谢谢 is and is common, so the
  /// character earns its rank from the company it keeps. The reading has to
  /// match: 解 is common as `jie3` and rare as `xie4`, and crediting the
  /// second with the first's rank is how "acrobatic display" outranked "to
  /// thank". Single-character words are excluded on purpose — letting 的
  /// credit itself is what spread its rank over every reading it has.
  final Map<String, int> compoundRank;

  /// The readings of a word its frequency may describe, filled in by
  /// [resolveDominance] once the whole of CC-CEDICT has been counted.
  final Map<String, Set<String>> dominantReadings = {};

  /// Every reading the source lists for a word.
  final Map<String, Set<String>> readings;

  final Map<String, int> wordLevel;

  /// How far a reading is pushed down when the word's rank cannot be pinned to
  /// it. Big enough to lose to any real rank, small enough to still beat a
  /// word carrying no rank at all.
  static const _unattributable = 1 << 20;

  /// Whether [key] is the reading a word's frequency actually describes.
  ///
  /// True for a word with only one reading, where there is nothing to confuse.
  bool _earnedIt(String simplified, String key) =>
      (readings[simplified]?.length ?? 0) <= 1 ||
      (dominantReadings[simplified]?.contains(key) ?? false);

  /// Works out which readings a word's frequency may describe, from two
  /// independent signals. A reading counts if *either* supports it: they fail
  /// on different words, and admitting one reading too many costs far less
  /// than stripping the right one.
  ///
  /// - **The commonest HSK compound.** Sound for words that live inside other
  ///   words, and blind to those that do not.
  /// - **How many CC-CEDICT entries use the character in that reading**, in
  ///   [cedictUses]. Breadth rather than frequency, which catches the words
  ///   the first signal misses: 喝 is common as `he1` but almost only appears
  ///   in compounds as `he4`, so on the HSK signal alone "to drink" lost its
  ///   rank to "to shout".
  ///
  /// Neither can see a word that is common standing alone and absent from
  /// compounds, which is every grammatical particle, so a neutral tone on a
  /// single character vouches for itself.
  void resolveDominance(Map<String, int> cedictUses) {
    for (final entry in readings.entries) {
      final word = entry.key;
      final found = <String>{};

      String? best;
      var bestRank = 1 << 30;
      for (final reading in entry.value) {
        var score = compoundRank['$word|$reading'];
        if (word.length == 1 && reading.endsWith('5')) {
          final alone = wordRank['$word|$reading'];
          if (alone != null && (score == null || alone < score)) score = alone;
        }
        if (score != null && score < bestRank) {
          bestRank = score;
          best = reading;
        }
      }
      if (best != null) found.add(best);

      if (word.length == 1) {
        String? widest;
        var mostUses = 0;
        for (final reading in entry.value) {
          final uses = cedictUses['$word|$reading'] ?? 0;
          if (uses > mostUses) {
            mostUses = uses;
            widest = reading;
          }
        }
        if (widest != null) found.add(widest);
      }

      if (found.isNotEmpty) dominantReadings[word] = found;
    }
  }

  int? rankOf(String simplified, String key) {
    final word = wordRank['$simplified|$key'];
    final evidence = simplified.length == 1
        ? compoundRank['$simplified|$key']
        : null;
    if (_earnedIt(simplified, key)) return word ?? evidence;
    // A reading the rank cannot be pinned to: take what its own compounds say
    // if they say anything, and otherwise keep the rank but well demoted.
    return evidence ?? (word == null ? null : word + _unattributable);
  }

  /// The HSK band, but only for the reading that earned it — 的 is HSK 1 as
  /// `de5`, and labelling "bull's-eye" HSK 1 would be the same mistake as
  /// ranking it first.
  int? levelOf(String simplified, String key) =>
      _earnedIt(simplified, key) ? wordLevel['$simplified|$key'] : null;
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
  final compoundRank = <String, int>{};
  final wordLevel = <String, int>{};
  final readings = <String, Set<String>>{};

  void keepLowest(Map<String, int> into, String key, int value) {
    final existing = into[key];
    if (existing == null || value < existing) into[key] = value;
  }

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

      readings.putIfAbsent(word, () => <String>{}).add(reading);
      keepLowest(wordRank, '$word|$reading', rank);
      if (level > 0) keepLowest(wordLevel, '$word|$reading', level);

      final syllables = reading.split(' ');
      if (syllables.length != word.length) continue;
      // Only a word of two or more characters may credit a character with a
      // rank in a reading. Where the word is one character the reading is the
      // very thing in doubt, and letting it vouch for itself is the bug this
      // avoids.
      if (word.length < 2) continue;
      for (var index = 0; index < syllables.length; index++) {
        keepLowest(compoundRank, '${word[index]}|${syllables[index]}', rank);
      }
    }
  }

  return _Hsk(
    wordRank: wordRank,
    compoundRank: compoundRank,
    readings: readings,
    wordLevel: wordLevel,
  );
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

/// Stands in for "no rank at all" when scoring.
///
/// Larger than any rank the build can produce, which is not simply larger
/// than the HSK list: an unattributable reading is stored as its word rank
/// plus `_Hsk._unattributable`, and those run past a million.
const unranked = 1 << 30;

/// One English headword an entry offers, and how good an answer it is.
class _Meaning {
  _Meaning({
    required this.headword,
    required this.key,
    required this.simplified,
    required this.score,
  });

  final String headword;
  final String key;
  final String simplified;

  /// Lower is a better answer to that headword. Measured, not guessed: see
  /// [_meanings].
  final int score;
}

/// The reading a character or compound is pronounced with.
class _Reading {
  _Reading({required this.key, required this.rank});

  final String key;
  final int? rank;

  /// Whether this is the reading to render these characters with.
  ///
  /// Commonest wins, and a ranked reading always beats an unranked one. This
  /// is the 多音字 decision, and it is the same one [_Hsk.rankOf] has already
  /// settled per entry — this only picks between entries that share the
  /// characters.
  ///
  /// On a tie, the neutral tone wins. Ties are common and were being settled
  /// by whichever entry the export happened to list first, which is how 得
  /// came out `dé`: its particle reading `de` and its verb reading `dé` are
  /// both rank 58, so 说得慢 read back as `shuō dé màn`. The rule is not a
  /// patch for that one character. A full-tone reading of a character this
  /// common almost always occurs inside a compound — 得到, 地球 — which
  /// longest-match has already taken as a word, so a character left standing
  /// on its own between other words is far likelier to be the particle. It
  /// settles 地 the same way, and correctly.
  bool beats(_Reading other) {
    final mine = rank ?? unranked;
    final theirs = other.rank ?? unranked;
    if (mine != theirs) return mine < theirs;
    return _neutral && !other._neutral;
  }

  bool get _neutral => key.endsWith('5');
}

/// Every English headword an entry's glosses offer.
///
/// Two separators, not one. CC-CEDICT divides senses with `/` and synonyms
/// within a sense with `; `, so 你好 is glossed `hello; hi` and 我 is
/// `I; me; my` — splitting only on `/` finds neither "hello" nor "I".
///
/// The score is `rank × (1 + sense) + synonym`, which is the product of two
/// signals that are each wrong alone. Rank by itself answers "eat" with 用,
/// a very common word with "to eat" as a minor sense. Sense position by
/// itself answers "thank you" with 三克油, an unranked transliteration that
/// happens to lead with it. Multiplying them puts 吃 and 谢谢 first.
///
/// A word outside the HSK syllabus is then doubled, which only decides near
/// ties — and one kind of tie in particular. A compound's rank leaks onto its
/// first character, so 啤 and 啤酒 are both rank 2622 and 朋 and 朋友 are both
/// 280, leaving "beer" and "friend" answered with a character nobody says on
/// its own. Only the compound is in the syllabus, and that settles it.
Iterable<_Meaning> _meanings({
  required List<String> glosses,
  required String key,
  required String simplified,
  required int? rank,
  required bool syllabus,
}) sync* {
  for (var sense = 0; sense < glosses.length; sense++) {
    final synonyms = glosses[sense].split('; ');
    for (var synonym = 0; synonym < synonyms.length; synonym++) {
      final headword = _headword(synonyms[synonym]);
      if (headword == null) continue;
      yield _Meaning(
        headword: headword,
        key: key,
        simplified: simplified,
        score: (rank ?? unranked) * (1 + sense) * (syllabus ? 1 : 2) + synonym,
      );
    }
  }
}

/// A gloss reduced to something a learner would actually type, or null if
/// what is left is a definition rather than a word.
String? _headword(String gloss) {
  var word = gloss
      .replaceAll(parenthetical, ' ')
      .toLowerCase()
      .replaceAll(classifier, ' ')
      .replaceAll(notAHeadword, ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  // CC-CEDICT writes verbs with their infinitive marker, and nobody looking
  // for 吃 types "to eat". Stripped here so the index is keyed on the bare
  // verb, and stripped again from the query — see `EnglishIndex`.
  if (word.startsWith('to ')) word = word.substring(3);
  if (word.isEmpty) return null;
  // Past this length a gloss is CC-CEDICT explaining something, and indexing
  // the explanation matches nothing anyone types.
  if (word.length > 40 || word.split(' ').length > 5) return null;
  return word;
}

/// A bracketed aside: `(bound form)`, `(of a person)`, `(dialect)`.
final parenthetical = RegExp(r'\([^)]*\)');

/// CC-CEDICT's measure-word note and everything after it.
final classifier = RegExp(r'\bcl:.*');

/// Anything that is not a letter, a digit, an apostrophe or a hyphen.
final notAHeadword = RegExp(r"[^a-z0-9'\- ]");

/// The English index, sharded by the headword's first letter, as the pinyin
/// shards are — so a lookup reads one file of about 160KB.
Map<String, List<String>> _englishRows(Map<String, List<_Meaning>> english) {
  final rows = <String, List<String>>{};
  for (final headword in english.keys) {
    final meanings = english[headword]!
      ..sort((a, b) => a.score.compareTo(b.score));
    final seen = <String>{};
    final best = <_Meaning>[];
    for (final meaning in meanings) {
      // One row per Chinese word. CC-CEDICT splits a word's senses across
      // entries, and offering 你 twice reads as two answers when it is one.
      if (!seen.add(meaning.simplified)) continue;
      // And only alternatives in the same league as the best one. Candidates
      // are for where English is genuinely vaguer than Chinese — "hot" is 热
      // or 辣 — not for everything CC-CEDICT happens to gloss the same way.
      // Unfiltered, "thank you" offered 谢谢 alongside 三克油, a joke
      // transliteration, and 雅教, archaic formal: a beginner has no way to
      // tell and might pick one.
      if (best.isNotEmpty && meaning.score > best.first.score * sameLeague) {
        break;
      }
      best.add(meaning);
      if (best.length == englishCandidates) break;
    }
    final letter = headword[0];
    final shard = RegExp('[a-z]').hasMatch(letter) ? letter : '0';
    rows
        .putIfAbsent(shard, () => <String>[])
        .add(
          [
            headword,
            for (final meaning in best) '${meaning.key}|${meaning.simplified}',
          ].join('\t'),
        );
  }
  return rows;
}

/// How many Chinese words one English headword offers.
///
/// Three, for the same reason the forward direction offers three candidates:
/// "hot" is 热 or 辣 and a learner should be told so, but a list of every
/// word CC-CEDICT glosses "hot" is not an answer.
const englishCandidates = 3;

/// How much worse than the best answer an alternative may score and still be
/// offered.
///
/// The score is rank-led and rank is roughly frequency order, so ten times
/// worse is roughly a tenth as common — which is about where an alternative
/// stops being a choice and starts being a curiosity. It leaves "hot" with
/// all three of 辣, 热 and 热门, whose scores are within a hair of each other,
/// and leaves "thank you", "water", "sorry" and "goodbye" with one answer
/// each. 8,451 of 93,339 headwords lose at least one candidate to it.
const sameLeague = 10;

/// The character index, sharded by where the first character sits in Unicode.
///
/// Sharded on the high byte of its code unit, which splits the CJK block into
/// about eighty files of ~30KB. Sharding by the character itself would mean
/// ten thousand files; not sharding at all would mean parsing 2.5MB and
/// holding 115,000 strings to read one sentence back.
Map<String, List<String>> _characterRows(Map<String, _Reading> characters) {
  final rows = <String, List<String>>{};
  for (final simplified in characters.keys) {
    final reading = characters[simplified]!;
    rows
        .putIfAbsent(charactersShardFor(simplified), () => <String>[])
        .add(
          [simplified, reading.key, reading.rank?.toString() ?? '-'].join('\t'),
        );
  }
  return rows;
}

/// Which character shard [word] would be found in.
///
/// Duplicated in `CharacterIndex`, which has to agree with it exactly. Kept
/// short enough that the two copies can be read side by side, and pinned by a
/// test that builds a shard name from both.
String charactersShardFor(String word) =>
    (word.codeUnitAt(0) >> 8).toRadixString(16).padLeft(2, '0');
