import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kouyu/favourites/favourites.dart';
import 'package:kouyu/favourites/stored_favourites.dart';
import 'package:kouyu/pinyin/syllable.dart';
import 'package:kouyu/pinyin/tone.dart';
import 'package:kouyu/pinyin/word.dart';
import 'package:kouyu/screens/favourites_screen.dart';
import 'package:kouyu/theme.dart';

final _nihao = [
  Spoken([const Syllable(initial: 'n', rime: 'i', tone: Tone.third)]),
  Spoken([const Syllable(initial: 'h', rime: 'ao', tone: Tone.third)]),
];
final _cha = [
  Spoken([const Syllable(initial: 'ch', rime: 'a', tone: Tone.second)]),
];

/// A store over a string in memory, with a clock that moves a minute a save.
StoredFavourites _store() {
  String? stored;
  var minute = 0;
  return StoredFavourites(
    read: () async => stored,
    write: (json) async => stored = json,
    clock: () => DateTime.utc(2026, 9, 27, 10, minute++),
  );
}

/// Pushes the list from a host route and reports what it popped with.
Future<List<Favourite?>> _show(
  WidgetTester tester,
  Favourites favourites, {
  ThemeData? theme,
}) async {
  final popped = <Favourite?>[];
  await tester.pumpWidget(
    MaterialApp(
      theme: theme ?? kLightTheme,
      home: Builder(
        builder: (context) => Scaffold(
          body: ElevatedButton(
            onPressed: () async => popped.add(
              await Navigator.of(context).push<Favourite>(
                MaterialPageRoute<Favourite>(
                  builder: (context) =>
                      FavouritesScreen(favourites: favourites),
                ),
              ),
            ),
            child: const Text('open'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  return popped;
}

void main() {
  testWidgets('says how to fill it when it is empty', (tester) async {
    await _show(tester, _store());
    expect(find.byKey(const Key('no-favourites')), findsOne);
    // The star is drawn with the icon font, which always ships. Typed as ☆ it
    // rendered as an empty box, because no bundled font carries it.
    expect(find.textContaining('☆'), findsNothing);
    expect(
      find.descendant(
        of: find.byKey(const Key('no-favourites')),
        matching: find.byIcon(Icons.star_border),
      ),
      findsOne,
    );
  });

  testWidgets('lists each line with its meaning, newest first', (tester) async {
    final favourites = _store();
    await favourites.save(_nihao, meaning: 'hello');
    await favourites.save(_cha, meaning: 'tea');
    await _show(tester, favourites);

    final titles = tester
        .widgetList<ListTile>(find.byType(ListTile))
        .map((tile) => (tile.title! as Text).data)
        .toList();
    expect(titles, ['chá', 'nǐ hǎo']);
    expect(find.text('hello'), findsOne);
    expect(find.text('tea'), findsOne);
  });

  testWidgets('tapping a line hands it back to be opened', (tester) async {
    final favourites = _store();
    await favourites.save(_nihao, meaning: 'hello');
    final popped = await _show(tester, favourites);

    await tester.tap(find.text('nǐ hǎo'));
    await tester.pumpAndSettle();

    expect(popped.single!.words, _nihao);
  });

  testWidgets('a swipe asks first, and Keep keeps it', (tester) async {
    final favourites = _store();
    await favourites.save(_nihao, meaning: 'hello');
    await _show(tester, favourites);

    await tester.drag(find.text('nǐ hǎo'), const Offset(-500, 0));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('confirm-removal')), findsOne);
    // The dialog names the line, so it can be answered without remembering
    // which row was swiped.
    expect(
      find.descendant(
        of: find.byKey(const Key('confirm-removal')),
        matching: find.text('nǐ hǎo'),
      ),
      findsOne,
    );

    await tester.tap(find.byKey(const Key('keep')));
    await tester.pumpAndSettle();
    expect(find.text('nǐ hǎo'), findsOne);
    expect(favourites.items.value, hasLength(1));
  });

  testWidgets('a swipe asks first, and Remove removes it', (tester) async {
    final favourites = _store();
    await favourites.save(_nihao, meaning: 'hello');
    await favourites.save(_cha, meaning: 'tea');
    await _show(tester, favourites);

    await tester.drag(find.text('nǐ hǎo'), const Offset(500, 0));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('remove')));
    await tester.pumpAndSettle();

    expect(find.text('nǐ hǎo'), findsNothing);
    expect(favourites.items.value.single.pinyin, 'chá');
    expect(tester.takeException(), isNull);
  });

  testWidgets('removing the last one leaves the empty message', (tester) async {
    final favourites = _store();
    await favourites.save(_cha, meaning: 'tea');
    await _show(tester, favourites);

    await tester.drag(find.text('chá'), const Offset(-500, 0));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('remove')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('no-favourites')), findsOne);
  });

  testWidgets('renders in both light and dark themes', (tester) async {
    for (final theme in [kLightTheme, kDarkTheme]) {
      final favourites = _store();
      await favourites.save(_nihao, meaning: 'hello');
      await tester.pumpWidget(
        MaterialApp(
          key: ValueKey(theme.brightness),
          theme: theme,
          home: FavouritesScreen(favourites: favourites),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('nǐ hǎo'), findsOne);
    }
  });
}
