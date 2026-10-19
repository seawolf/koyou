import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kouyu/translation/dictionary.dart';

/// The file as written, line by line, without its comments.
List<List<String>> _lines() => [
  for (final line in File('assets/notes/word_notes.tsv').readAsLinesSync())
    if (line.trim().isNotEmpty && !line.startsWith('#')) line.split('\t'),
];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('the notes file', () {
    // Written by hand, so this is what stands between a typo and a note that
    // silently never shows.

    test('has four fields on every line', () {
      for (final fields in _lines()) {
        expect(fields, hasLength(4), reason: fields.join(' | '));
      }
    });

    test('points every line at a real dictionary entry', () async {
      final dictionary = Dictionary.bundled();
      for (final [simplified, key, _, _] in _lines()) {
        final entries = await dictionary.lookUp(key);
        expect(
          entries.map((entry) => entry.simplified),
          contains(simplified),
          reason: '$simplified is not keyed $key in CC-CEDICT',
        );
      }
    });

    test('uses only the registers the app knows', () {
      for (final [simplified, _, register, _] in _lines()) {
        expect(
          const ['everyday', 'formal', '-'],
          contains(register),
          reason: simplified,
        );
      }
    });

    test('writes its notes in pinyin, never in characters', () {
      // Notes are on the learning surface, and characters are not.
      final han = RegExp(r'[㐀-鿿]');
      for (final [simplified, _, _, note] in _lines()) {
        expect(note.trim(), isNotEmpty, reason: simplified);
        expect(han.hasMatch(note), isFalse, reason: '$simplified: $note');
      }
    });

    test('notes each word once', () {
      final seen = <String>{};
      for (final [simplified, key, _, _] in _lines()) {
        expect(seen.add('$simplified|$key'), isTrue, reason: simplified);
      }
    });

    test('never gives two candidates for one English word the same note', () {
      // The point of a note is to tell candidates apart, so two identical
      // ones under one headword tell nobody anything. Checked against every
      // headword the English index has, not a sample of them.
      final notes = {
        for (final [simplified, key, _, note] in _lines())
          '$key|$simplified': note,
      };
      for (final file in Directory('assets/dictionary/english').listSync()) {
        if (file is! File || !file.path.endsWith('.tsv')) continue;
        for (final line in file.readAsLinesSync()) {
          final [headword, ...candidates] = line.split('\t');
          final shown = [for (final candidate in candidates) ?notes[candidate]];
          expect(shown.toSet(), hasLength(shown.length), reason: headword);
        }
      }
    });
  });
}
