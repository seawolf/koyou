import 'package:flutter_test/flutter_test.dart';
import 'package:kouyu/app.dart';
import 'package:kouyu/screens/compose_screen.dart';

void main() {
  testWidgets('boots to the compose screen', (tester) async {
    await tester.pumpWidget(const KouyuApp());

    expect(find.byType(ComposeScreen), findsOneWidget);
  });
}
