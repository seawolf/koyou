import 'package:flutter_test/flutter_test.dart';
import 'package:kouyu/app.dart';
import 'package:kouyu/screens/home_screen.dart';

void main() {
  testWidgets('boots to the home screen', (tester) async {
    await tester.pumpWidget(const KouyuApp());

    expect(find.byType(HomeScreen), findsOneWidget);
  });
}
