import '../pinyin/reading.dart';
import '../pinyin/syllable.dart';
import 'breakdown.dart';
import '../pinyin/word.dart';
import 'character_index.dart';
import 'dictionary.dart';
import 'english_index.dart';
import 'example_index.dart';
import 'word_notes.dart';
import 'english_translator.dart';
import 'translator.dart';

/// Answers a word by inverting CC-CEDICT.
///
/// It is a dictionary read backwards and behaves like one: it answers words
/// and set phrases and it does not compose sentences. "toilet" it can do;
/// "where is the toilet?" it cannot, and declines rather than guess — that is
/// what the model tier behind it is for.
///
/// Where English is vaguer than Chinese it offers the alternatives instead of
/// picking. "hot" is 热 or 辣 and nothing in the English says which; showing
/// both, each with what it actually means, is the only honest answer.
class EnglishDictionaryTranslator implements EnglishTranslator {
  const EnglishDictionaryTranslator({
    required this.index,
    required this.dictionary,
    this.examples,
    this.characters,
    this.notes,
  });

  /// This project's own notes, over the dictionary: a register, and what a
  /// word is used for where CC-CEDICT gives several the same gloss.
  final WordNotes? notes;

  /// Sentences showing each word in use. Both this and [characters] are
  /// needed to show one, and either being null leaves examples out.
  final ExampleIndex? examples;

  /// Reads an example's sentence into pinyin.
  final CharacterIndex? characters;

  final EnglishIndex index;

  /// Read for the glosses and the HSK band, not for the pinyin — the index
  /// already carries the key. Without it a learner choosing between three
  /// candidates would be choosing between three strings of pinyin they cannot
  /// tell apart.
  final Dictionary dictionary;

  @override
  Future<Said?> say(String english, {Register? register}) async {
    final meanings = await index.lookUp(english);
    if (meanings.isEmpty) return null;
    final queries = EnglishIndex.queriesFor(english);

    final found = <_Found>[];
    for (final meaning in meanings) {
      final syllables = syllablesFor(meaning.key);
      // A word the keyboard cannot build — the erhua suffix, an interjection.
      // Skipped rather than declined over: the other candidates are still
      // answers.
      if (syllables == null) continue;
      final entry = await _entryFor(meaning);
      found.add(
        _Found(
          words: [Spoken(syllables)],
          entry: entry,
          sense: entry == null ? null : _senseFor(entry, queries),
          example: await _exampleFor(meaning.simplified, syllables),
          note: await notes?.find(meaning.simplified, meaning.key),
          parts: await Breakdown(dictionary)
              .charactersOf(meaning.simplified, meaning.key),
        ),
      );
    }
    if (found.isEmpty) return null;
    // A register preference first and the part of speech last, so that when
    // both are given the part of speech wins: "to bury" asks for a verb in
    // so many words, and a preference for formal words is only a lean.
    _preferRegister(found, register);
    _putFirst(found, _askedFor(english));

    final distinctions = _distinctions(found);
    return Said(
      options: [
        for (var i = 0; i < found.length; i++)
          Rendering(
            words: found[i].words,
            meaning: found[i].sense,
            distinction: found[i].note?.note ?? distinctions[i],
            example: found[i].example,
            register: found[i].note?.register,
            parts: found[i].parts,
            hskLevel: found[i].entry?.hskLevel,
          ),
      ],
      phrasing: Phrasing.entry,
    );
  }

  /// The example for [word], with the word itself in the reading it is
  /// being offered with.
  ///
  /// Not in whatever reading the sentence would otherwise be read with. A
  /// word with several readings is offered as one of them, and reading the
  /// sentence on its own could pick another: the candidate would say one tone
  /// and its own example a different one. So the sentence is read either side
  /// of the word and the word is put back as the candidate's syllables.
  Future<Example?> _exampleFor(String word, List<Syllable> syllables) async {
    final examples = this.examples;
    final characters = this.characters;
    if (examples == null || characters == null) return null;
    final sentence = await examples.find(word);
    if (sentence == null) return null;

    final end = sentence.offset + word.length;
    if (end > sentence.chinese.length ||
        sentence.chinese.substring(sentence.offset, end) != word) {
      return null;
    }
    final before = await characters.readPart(
      sentence.chinese.substring(0, sentence.offset),
    );
    final after = await characters.readPart(sentence.chinese.substring(end));
    if (before == null || after == null) return null;
    return Example(
      words: [...before, Spoken(syllables), ...after],
      target: before.length,
      english: sentence.english,
    );
  }

  /// Moves the candidates in the [wanted] register to the front, then the
  /// ones nobody has labelled, and the other register last.
  ///
  /// A lean, not a filter. Most words carry no label, and hiding them because
  /// a learner asked for formal words would empty most answers; putting the
  /// formal word first, chosen, where one is known, is what "formal" can
  /// honestly mean with the data there is.
  static void _preferRegister(List<_Found> found, Register? wanted) {
    if (wanted == null) return;
    int place(_Found f) => switch (f.note?.register) {
      null => 1,
      final register when register == wanted => 0,
      _ => 2,
    };
    final indexed = [for (var i = 0; i < found.length; i++) (i, found[i])];
    indexed.sort((a, b) {
      final byPlace = place(a.$2).compareTo(place(b.$2));
      return byPlace != 0 ? byPlace : a.$1.compareTo(b.$1);
    });
    found
      ..clear()
      ..addAll(indexed.map((entry) => entry.$2));
  }

  /// Which part of speech the English itself asked for, where it says.
  ///
  /// English marks it already: "to land" is the verb and "a leak" the noun.
  /// The index ignores both markers, since neither is part of any headword, so
  /// without this "to land" and "land" gave the same list in the same order.
  static _PartOfSpeech? _askedFor(String english) {
    final typed = english.trim().toLowerCase();
    if (typed.startsWith('to ')) return _PartOfSpeech.verb;
    for (final article in const ['a ', 'an ', 'the ']) {
      if (typed.startsWith(article)) return _PartOfSpeech.noun;
    }
    return null;
  }

  /// Moves the candidates that are [wanted] to the front, keeping the order
  /// within each side — so the first, which is the one chosen until somebody
  /// says otherwise, is the best of the kind that was asked for.
  ///
  /// The dictionary's own convention decides what is a verb: CC-CEDICT writes
  /// every verb sense "to …", so this works for all of it, not only for words
  /// in a syllabus.
  static void _putFirst(List<_Found> found, _PartOfSpeech? wanted) {
    if (wanted == null) return;
    bool isWanted(_Found f) =>
        _isVerb(f.sense) == (wanted == _PartOfSpeech.verb);
    final reordered = [...found.where(isWanted), ...found.whereNot(isWanted)];
    found
      ..clear()
      ..addAll(reordered);
  }

  static bool _isVerb(String? sense) {
    if (sense == null) return false;
    // "(bound form) to leak out" is a verb too: the aside comes first.
    final bare = sense.replaceFirst(_leadingAsides, '').trim().toLowerCase();
    return bare.startsWith('to ');
  }

  static final _leadingAsides = RegExp(r'^(\([^)]*\)\s*)+');

  /// A note for each candidate whose shown sense another candidate shares,
  /// saying what tells them apart; null for the rest.
  ///
  /// Measured over every headword with several candidates. Of those sharing a
  /// gloss, 53% have a sense no sibling has — 午餐 is also "luncheon", 中餐
  /// also "Chinese meal; Chinese food" — and another 12% are the one plain
  /// word left once the others are accounted for, like 午饭, which means lunch
  /// and nothing else. The remaining 35% are near-synonyms CC-CEDICT does not
  /// separate (湖 and 湖泊, 成员 and 会员), and for those the honest answer is
  /// which is commoner, never an invented difference.
  static List<String?> _distinctions(List<_Found> found) {
    final notes = List<String?>.filled(found.length, null);
    final groups = <String, List<int>>{};
    for (var i = 0; i < found.length; i++) {
      final sense = found[i].sense;
      if (sense == null) continue;
      groups.putIfAbsent(sense.trim().toLowerCase(), () => []).add(i);
    }

    for (final members in groups.values) {
      if (members.length < 2) continue;
      final others = {for (final i in members) i: _otherSenses(found[i])};
      final plain = <int>[];
      for (final i in members) {
        final theirs = {
          for (final j in members)
            if (j != i) ...others[j]!.map(EnglishIndex.normalise),
        };
        final own = [
          for (final sense in others[i]!)
            if (!theirs.contains(EnglishIndex.normalise(sense))) sense,
        ];
        if (own.isEmpty) {
          plain.add(i);
        } else {
          notes[i] = 'also: ${own.take(2).join('; ')}';
        }
      }

      if (plain.length == 1) {
        // Told apart by elimination: every sibling means something else as
        // well, and this one does not.
        notes[plain.single] = 'only this meaning';
      } else if (plain.length > 1) {
        plain.sort(
          (a, b) => (found[a].entry?.rank ?? unranked).compareTo(
            found[b].entry?.rank ?? unranked,
          ),
        );
        final first = found[plain.first].entry?.rank;
        final second = found[plain[1]].entry?.rank;
        // Frequency is the one thing left to tell them apart by, and only if
        // it does: two unranked words, or two on the same rank, are simply
        // said to be the same.
        if (first == null || first == second) {
          for (final i in plain) {
            notes[i] = 'no difference recorded';
          }
        } else {
          notes[plain.first] = 'the commoner word';
          for (final i in plain.skip(1)) {
            notes[i] = 'rarer — no difference recorded';
          }
        }
      }
    }
    return notes;
  }

  /// The senses of [found] besides the one shown, without the dictionary's
  /// own housekeeping: a bare measure-word note, a cross-reference.
  static List<String> _otherSenses(_Found found) => [
    for (final gloss in found.entry?.glosses ?? const <String>[])
      if (gloss != found.sense && _meaningful(gloss)) gloss,
  ];

  static bool _meaningful(String gloss) {
    final text = gloss.trim().toLowerCase();
    return text.isNotEmpty &&
        !text.startsWith('cl:') &&
        !text.startsWith('see ') &&
        !text.startsWith('variant of') &&
        !text.startsWith('also written');
  }

  /// Ranks run upward from 1; this sorts after all of them.
  static const unranked = 1 << 30;

  /// The sense that was actually asked about.
  ///
  /// Not the entry's first gloss, which is the obvious thing and the wrong
  /// one. 热 is glossed "to warm up / to heat up / hot (of weather) / …", so
  /// somebody typing "hot" and choosing between candidates was being shown
  /// "to warm up" against 辣's "hot (spicy)" — a choice between one answer
  /// and something that does not look like an answer at all.
  ///
  /// The whole sense is returned rather than the matched synonym, because the
  /// bracketed part is the useful bit: "hot (of weather)" is what distinguishes
  /// it, and that is exactly what the index had to strip to find it.
  String _senseFor(DictionaryEntry entry, List<String> queries) {
    for (final gloss in entry.glosses) {
      for (final synonym in gloss.split('; ')) {
        if (queries.contains(EnglishIndex.normalise(synonym))) return gloss;
      }
    }
    return entry.glosses.first;
  }

  /// The entry the index was pointing at.
  ///
  /// Matched on the characters, not just the key: several words share a
  /// reading, and glossing 啤酒 with 皮酒's meaning would be worse than showing
  /// no gloss at all.
  Future<DictionaryEntry?> _entryFor(EnglishMeaning meaning) async {
    for (final entry in await dictionary.lookUp(meaning.key)) {
      if (entry.simplified == meaning.simplified) return entry;
    }
    return null;
  }
}

/// A candidate on its way to being a [Rendering], kept with its entry so the
/// candidates can be compared before they are shown.
class _Found {
  _Found({
    required this.words,
    required this.entry,
    required this.sense,
    this.example,
    this.note,
    this.parts = const [],
  });

  final List<Word> words;
  final DictionaryEntry? entry;
  final String? sense;
  final Example? example;
  final WordNote? note;
  final List<WordGloss> parts;
}

enum _PartOfSpeech { noun, verb }

extension<T> on Iterable<T> {
  Iterable<T> whereNot(bool Function(T) test) => where((item) => !test(item));
}
