import 'package:ai_usage/src/app.dart';
import 'package:ai_usage/src/app_controller.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('empty dashboard offers account login', (tester) async {
    await tester.pumpWidget(
      AiUsageApp(controller: AppController.testing()),
    );

    expect(find.text('Add a Codex account'), findsOneWidget);
  });
}
