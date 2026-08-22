import 'package:ai_usage/src/app.dart';
import 'package:ai_usage/src/app_controller.dart';
import 'package:ai_usage/src/rust/models.dart';
import 'package:ai_usage/src/services/secure_account_vault.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('new privacy and battery-sensitive settings default off', () {
    const settings = MonitorSettings();
    expect(settings.dynamicColorEnabled, isFalse);
    expect(settings.demoModeEnabled, isFalse);
    expect(settings.backgroundRefreshEnabled, isFalse);

    final migrated = MonitorSettings.fromJson(const {'refresh_minutes': 15});
    expect(migrated.backgroundRefreshEnabled, isFalse);
  });

  testWidgets('empty dashboard offers account login', (tester) async {
    await tester.pumpWidget(AiUsageApp(controller: AppController.testing()));

    expect(find.text('Add a Codex account'), findsOneWidget);
  });

  testWidgets('Simplified Chinese can be selected explicitly', (tester) async {
    await tester.pumpWidget(
      AiUsageApp(
        controller: AppController.testing(
          settings: const MonitorSettings(
            locale: LocalePreference.simplifiedChinese,
          ),
        ),
      ),
    );

    expect(find.text('添加 Codex 账户'), findsOneWidget);
  });

  testWidgets('mobile app bar handles a long account without overflow', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    const account = StoredAccount(
      identityHash: 'test-account',
      email: 'a-very-long-account-name-that-must-truncate@example.com',
      plan: 'plus',
      loginState: LoginState.signedOut,
    );
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(textScaler: TextScaler.linear(1.5)),
        child: AiUsageApp(
          controller: AppController.testing(accounts: const [account]),
        ),
      ),
    );

    expect(tester.takeException(), isNull);
    expect(find.byIcon(Icons.person_add_alt_1), findsOneWidget);
  });

  testWidgets('complete demo mode renders quota credits and token profile', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final controller = AppController.testing(
      settings: const MonitorSettings(demoModeEnabled: true, demoSeed: 42),
    );
    await tester.pumpWidget(AiUsageApp(controller: controller));

    expect(find.text('Demo data'), findsWidgets);
    expect(find.text('Extra credits'), findsOneWidget);
    expect(find.text('Reset Credits'), findsOneWidget);
    await controller.refresh();
    expect(controller.profileUsage?.dailyUsageBuckets.length, 120);

    await tester.tap(find.text('History'));
    await tester.pumpAndSettle();
    expect(find.text('Token activity'), findsOneWidget);
    expect(find.text('Lifetime tokens'), findsOneWidget);
    expect(find.text('Daily token heatmap'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('overview remains overflow-free at 2x text scale', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(textScaler: TextScaler.linear(2)),
        child: AiUsageApp(
          controller: AppController.testing(
            settings: const MonitorSettings(demoModeEnabled: true, demoSeed: 7),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
