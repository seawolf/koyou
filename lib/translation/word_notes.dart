import 'package:flutter/services.dart';

import 'english_translator.dart';

/// What this project knows about a word that CC-CEDICT does not say.
typedef WordNote = ({Register? register, String? note});

/// The hand-written notes in `assets/notes/word_notes.tsv`.
///
/// A layer over the dictionary rather than a change to it. CC-CEDICT is
/// generated and stays as it is; this is small, written by hand, and says
/// what CC-CEDICT gives no way to say — that 夏季 is the formal word for
/// summer, or that 会员 is a member of a club and 成员 of a group. Read once,
/// whole: a couple of hundred lines.
class WordNotes {
  WordNotes({required this.load});

  final Future<String> Function() load;

  factory WordNotes.bundled([AssetBundle? bundle]) {
    final assets = bundle ?? rootBundle;
    return WordNotes(
      load: () => assets.loadString('assets/notes/word_notes.tsv'),
    );
  }

  Future<Map<String, WordNote>>? _loaded;

  /// The note for the word written [simplified] and keyed [key], or null.
  Future<WordNote?> find(String simplified, String key) async {
    final notes = await (_loaded ??= _parse());
    return notes['$simplified|$key'];
  }

  Future<Map<String, WordNote>> _parse() async {
    String contents;
    try {
      contents = await load();
    } on Object {
      // No notes is a dictionary without them, not a broken lookup.
      return const {};
    }
    return parse(contents);
  }

  /// The notes [contents] holds, keyed by word and reading.
  ///
  /// Public so the test that checks every line against the dictionary reads
  /// the file exactly as the app does.
  static Map<String, WordNote> parse(String contents) {
    final notes = <String, WordNote>{};
    for (final line in contents.split('\n')) {
      if (line.trim().isEmpty || line.startsWith('#')) continue;
      final fields = line.split('\t');
      if (fields.length < 4) continue;
      final note = fields[3].trim();
      notes['${fields[0]}|${fields[1]}'] = (
        register: switch (fields[2].trim()) {
          'everyday' => Register.everyday,
          'formal' => Register.formal,
          _ => null,
        },
        note: note.isEmpty ? null : note,
      );
    }
    return notes;
  }
}
