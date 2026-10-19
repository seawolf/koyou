import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kouyu/translation/dictionary.dart';
import 'package:kouyu/translation/english_dictionary_translator.dart';
import 'package:kouyu/translation/english_index.dart';
import 'package:kouyu/translation/english_translator.dart';
import 'package:kouyu/translation/word_notes.dart';

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

  test('reads a line, and reads "-" as no register', () {
    final notes = WordNotes.parse(
      '# a comment\n'
      '夏季\txia4 ji4\tformal\tthe season, in writing\n'
      '月球\tyue4 qiu2\t-\tthe moon in space\n'
      '\n',
    );
    expect(notes['夏季|xia4 ji4'], (
      register: Register.formal,
      note: 'the season, in writing',
    ));
    expect(notes['月球|yue4 qiu2']?.register, isNull);
    expect(notes, hasLength(2));
  });

  group('over the dictionary', () {
    final real = EnglishDictionaryTranslator(
      index: EnglishIndex.bundled(),
      dictionary: Dictionary.bundled(),
      notes: WordNotes.bundled(),
    );

    test('says what the dictionary could not', () async {
      final options = (await real.say('member'))!.options;
      String? noteOf(String pinyin) =>
          options.firstWhere((o) => o.written == pinyin).distinction;
      expect(noteOf('chéngyuán'), 'of a group, team or family');
      expect(noteOf('huìyuán'), 'of a club or service you join');
    });

    test('labels the everyday and the formal word', () async {
      final options = (await real.say('summer'))!.options;
      Register? registerOf(String pinyin) =>
          options.firstWhere((o) => o.written == pinyin).register;
      expect(registerOf('xiàtiān'), Register.everyday);
      expect(registerOf('xiàjì'), Register.formal);
    });

    test('a preference puts that register first', () async {
      Future<String> first(Register? register) async =>
          (await real.say('summer', register: register))!.best.written;
      expect(await first(Register.formal), 'xiàjì');
      expect(await first(Register.everyday), 'xiàtiān');
    });

    test('a preference hides nothing', () async {
      final either = (await real.say('summer'))!.options;
      final formal = (await real.say(
        'summer',
        register: Register.formal,
      ))!.options;
      expect(
        formal.map((o) => o.written).toSet(),
        either.map((o) => o.written).toSet(),
      );
    });

    test('words without a label keep their place among themselves', () async {
      // "hot" has no notes at all, so a preference changes nothing.
      final either = await real.say('hot');
      final formal = await real.say('hot', register: Register.formal);
      expect(
        formal!.options.map((o) => o.written),
        either!.options.map((o) => o.written),
      );
    });
  });
}
