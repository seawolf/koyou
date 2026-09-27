import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:kouyu/favourites/favourites.dart';
import 'package:kouyu/favourites/stored_favourites.dart';
import 'package:kouyu/pinyin/syllable.dart';
import 'package:kouyu/pinyin/tone.dart';
import 'package:kouyu/pinyin/word.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

final _ni = Spoken([const Syllable(initial: 'n', rime: 'i', tone: Tone.third)]);
final _hao = Spoken([
  const Syllable(initial: 'h', rime: 'ao', tone: Tone.third),
]);
final _cha = Spoken([
  const Syllable(initial: 'ch', rime: 'a', tone: Tone.second),
]);

/// Storage that is a string in a variable.
class _Disk {
  _Disk([this.stored]);

  String? stored;
  int writes = 0;

  StoredFavourites open({DateTime Function()? clock}) => StoredFavourites(
    read: () async => stored,
    write: (json) async {
      writes++;
      stored = json;
    },
    clock: clock,
  );
}

Future<void> _settle() => Future<void>.delayed(Duration.zero);

void main() {
  var minute = 0;
  DateTime clock() => DateTime.utc(2026, 9, 27, 10, minute++);

  setUp(() => minute = 0);

  test('starts empty when nothing has been kept', () async {
    final favourites = _Disk().open();
    await _settle();
    expect(favourites.items.value, isEmpty);
  });

  test('keeps a line, newest first', () async {
    final disk = _Disk();
    final favourites = disk.open(clock: clock);

    await favourites.save([_ni, _hao], meaning: 'hello');
    await favourites.save([_cha], meaning: 'tea');

    expect(favourites.items.value.map((f) => f.pinyin), ['chá', 'nǐ hǎo']);
    expect(favourites.find([_ni, _hao])?.meaning, 'hello');
  });

  test('survives being opened again', () async {
    final disk = _Disk();
    final first = disk.open(clock: clock);
    await first.save([_ni, _hao], meaning: 'hello');

    final again = disk.open();
    await _settle();
    expect(again.items.value.single.pinyin, 'nǐ hǎo');
    expect(again.items.value.single.meaning, 'hello');
  });

  test('saving the same line twice keeps it once', () async {
    final favourites = _Disk().open(clock: clock);
    await favourites.save([_ni, _hao], meaning: 'hello');
    await favourites.save([_ni, _hao, const Spoken()], meaning: 'hi');
    expect(favourites.items.value, hasLength(1));
    // The first meaning stands: it is what was saved.
    expect(favourites.items.value.single.meaning, 'hello');
  });

  test('ignores an empty line', () async {
    final disk = _Disk();
    final favourites = disk.open();
    await favourites.save(const [Spoken()]);
    expect(favourites.items.value, isEmpty);
    expect(disk.writes, 0);
  });

  test('removes one and leaves the rest', () async {
    final disk = _Disk();
    final favourites = disk.open(clock: clock);
    await favourites.save([_ni, _hao]);
    await favourites.save([_cha]);

    await favourites.remove(favourites.find([_ni, _hao])!);

    expect(favourites.items.value.single.pinyin, 'chá');
    final reopened = disk.open();
    await _settle();
    expect(reopened.items.value.single.pinyin, 'chá');
  });

  test('a row it cannot read does not cost the others', () async {
    final good = {
      'words': [
        {
          's': ['cha2'],
        },
      ],
      'meaning': 'tea',
      'saved': DateTime.utc(2026).toIso8601String(),
    };
    final disk = _Disk(
      jsonEncode([
        good,
        {'nonsense': true},
      ]),
    );
    final favourites = disk.open();
    await _settle();
    expect(favourites.items.value.single.meaning, 'tea');
  });

  test('storage that is not a list is an empty list', () async {
    for (final stored in ['not json', '{"a": 1}', '']) {
      final favourites = _Disk(stored).open();
      await _settle();
      expect(favourites.items.value, isEmpty, reason: stored);
    }
  });

  test('storage that cannot be read is an empty list', () async {
    final favourites = StoredFavourites(
      read: () async => throw StateError('no storage'),
      write: (_) async {},
    );
    await _settle();
    expect(favourites.items.value, isEmpty);
  });

  test('a save before loading finishes does not wipe what was kept', () async {
    // The store starts reading as soon as it exists, and a tap can arrive
    // before the read does. Writing the new line alone would replace the
    // whole list with one item.
    final reading = Completer<String?>();
    String? stored;
    final favourites = StoredFavourites(
      read: () => reading.future,
      write: (json) async => stored = json,
      clock: clock,
    );

    final saving = favourites.save([_cha], meaning: 'tea');
    reading.complete(
      jsonEncode([
        {
          'words': [
            {
              's': ['ni3', 'hao3'],
            },
          ],
          'meaning': 'hello',
          'saved': DateTime.utc(2026).toIso8601String(),
        },
      ]),
    );
    await saving;

    expect(favourites.items.value.map((f) => f.pinyin), ['chá', 'nǐhǎo']);
    expect(jsonDecode(stored!), hasLength(2));
  });

  test('writes land in the order they were made', () async {
    // Two saves close together. If the older write finished last, it would
    // put back a list without the newer line.
    final landed = <int>[];
    final gates = [Completer<void>(), Completer<void>()];
    var call = 0;
    final favourites = StoredFavourites(
      read: () async => null,
      write: (json) async {
        final mine = call++;
        await gates[mine].future;
        landed.add((jsonDecode(json) as List).length);
      },
      clock: clock,
    );

    final first = favourites.save([_ni]);
    await _settle();
    final second = favourites.save([_cha]);
    await _settle();
    gates[1].complete();
    gates[0].complete();
    await Future.wait([first, second]);

    expect(landed, [1, 2]);
  });

  test('a failed write keeps the list on screen', () async {
    final favourites = StoredFavourites(
      read: () async => null,
      write: (_) async => throw StateError('disk full'),
      clock: clock,
    );
    await favourites.save([_cha]);
    expect(favourites.items.value.single.pinyin, 'chá');
  });

  test('starts, empty, where there are no preferences at all', () async {
    // Constructing the plugin's store throws where no platform is
    // registered. That must cost the list, never the app starting.
    SharedPreferencesAsyncPlatform.instance = null;

    final favourites = StoredFavourites.preferences();
    await _settle();
    expect(favourites.items.value, isEmpty);
    // Saving still works for the session; it is only not kept.
    await favourites.save([_cha]);
    expect(favourites.items.value.single.pinyin, 'chá');
  });

  test('keeps its list in the platform preferences', () async {
    // The one part that needs a platform, run against the in-memory one the
    // plugin publishes for tests.
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();

    final first = StoredFavourites.preferences();
    await first.save([_ni, _hao], meaning: 'hello');

    final again = StoredFavourites.preferences();
    await _settle();
    expect(again.items.value.single.meaning, 'hello');
  });
}
