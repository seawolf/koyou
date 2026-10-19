import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kouyu/translation/character_index.dart';

/// Every row of the generated examples, as `tool/build_examples.dart` wrote
/// them: the word, where it starts in the sentence, the sentence, its English.
List<(String, List<String>)> _rows() => [
  for (final file in Directory('assets/examples').listSync())
    if (file is File && file.path.endsWith('.tsv'))
      for (final line in file.readAsLinesSync())
        if (line.isNotEmpty)
          (file.uri.pathSegments.last.replaceAll('.tsv', ''), line.split('\t')),
];

/// Checks the generated example sentences themselves, before anything reads
/// them. A row that points at the wrong place in its sentence would show the
/// wrong word in bold, and nothing else would notice.
void main() {
  final rows = _rows();

  test('there are examples to check', () {
    expect(rows.length, greaterThan(10000));
  });

  test('every row has its four fields', () {
    for (final (_, fields) in rows) {
      expect(fields, hasLength(4), reason: fields.join(' | '));
    }
  });

  test('every row points at its word in its sentence', () {
    for (final (_, [word, offset, chinese, _]) in rows) {
      final at = int.parse(offset);
      expect(
        chinese.substring(at, at + word.length),
        word,
        reason: '$word in $chinese',
      );
    }
  });

  test('every row is in the shard the app will look in', () {
    for (final (shard, [word, _, _, _]) in rows) {
      expect(CharacterIndex.shardFor(word), shard, reason: word);
    }
  });

  test('has an English translation for every sentence', () {
    for (final (_, [word, _, _, english]) in rows) {
      expect(english.trim(), isNotEmpty, reason: word);
    }
  });

  test('holds no sentences about Tatoeba itself', () {
    // Untagged, and once chosen as the example of 例如.
    for (final (_, [word, _, chinese, english]) in rows) {
      expect(
        '$chinese $english'.toLowerCase(),
        isNot(contains('tatoeba')),
        reason: word,
      );
    }
  });

  test('carries its licence', () {
    final licence = File('assets/examples/LICENCE').readAsStringSync();
    expect(licence, contains('Tatoeba'));
    expect(licence, contains('creativecommons.org/licenses/by/2.0/fr'));
  });
}
