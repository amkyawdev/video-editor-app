import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  testWidgets('smoke widget test renders material UI', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: Text('Amkyaw Studio'))),
    );
    expect(find.text('Amkyaw Studio'), findsOneWidget);
  });
}
