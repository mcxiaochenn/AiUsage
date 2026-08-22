import 'package:ai_usage/src/app.dart';
import 'package:ai_usage/src/app_controller.dart';
import 'package:ai_usage/src/rust/models.dart';
import 'package:ai_usage/src/services/secure_account_vault.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
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
}
