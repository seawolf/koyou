import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kouyu/screens/home_screen.dart';
import 'package:kouyu/theme.dart';

void main() {
  Widget wrap({required Brightness brightness}) {
    return MaterialApp(
      theme: brightness == Brightness.light ? kLightTheme : kDarkTheme,
      home: const HomeScreen(),
    );
  }

  testWidgets('shows the greeting in Hanzi, pinyin, and English', (
    tester,
  ) async {
    await tester.pumpWidget(wrap(brightness: Brightness.light));

    expect(find.text('你好，世界'), findsOneWidget);
    expect(find.text('Nǐ hǎo, shìjiè'), findsOneWidget);
    expect(find.text('Hello, world'), findsOneWidget);
    expect(find.text('Kǒuyǔ'), findsOneWidget);
  });

  testWidgets('renders in both light and dark themes', (tester) async {
    for (final brightness in Brightness.values) {
      await tester.pumpWidget(wrap(brightness: brightness));
      expect(find.byType(HomeScreen), findsOneWidget);
      expect(tester.takeException(), isNull);
    }
  });
}
