import 'package:flutter_test/flutter_test.dart';
import 'package:recoverysense_phone/main.dart';

void main() {
  testWidgets('RecoverySense app starts at login screen', (tester) async {
    await tester.pumpWidget(const RecoverySenseApp());
    expect(find.text('RecoverySense'), findsOneWidget);
    expect(find.text('Login / Continue'), findsOneWidget);
  });
}
