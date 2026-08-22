import 'package:codex_usage_monitor/src/app.dart';
import 'package:codex_usage_monitor/src/app_controller.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('empty dashboard offers account login', (tester) async {
    await tester.pumpWidget(
      CodexUsageMonitorApp(controller: AppController.testing()),
    );

    expect(find.text('Add a Codex account'), findsOneWidget);
  });
}
