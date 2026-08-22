import 'package:ai_usage/src/app.dart';
import 'package:ai_usage/src/app_controller.dart';
import 'package:ai_usage/src/rust/models.dart';
import 'package:ai_usage/src/services/secure_account_vault.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('credential source persists and old metadata remains unknown', () {
    const imported = StoredAccount(
      identityHash: 'imported-account',
      loginState: LoginState.signedIn,
      credentialSource: CredentialSource.authJson,
    );

    expect(
      StoredAccount.fromMetadata(imported.toMetadata()).credentialSource,
      CredentialSource.authJson,
    );
    expect(
      StoredAccount.fromMetadata(const {
        'identity_hash': 'old-account',
        'login_state': 'signedIn',
      }).credentialSource,
      CredentialSource.unknown,
    );
  });

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

  testWidgets('account list shows the persisted credential source', (
    tester,
  ) async {
    const account = StoredAccount(
      identityHash: 'device-account',
      email: 'device@example.com',
      loginState: LoginState.signedIn,
      credentialSource: CredentialSource.deviceCode,
    );
    await tester.pumpWidget(
      AiUsageApp(controller: AppController.testing(accounts: const [account])),
    );

    await tester.tap(find.text('Accounts'));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('Browser authorization (Device Code)'),
      findsOneWidget,
    );
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

  testWidgets('heatmap ends yesterday and normalizes daily buckets', (
    tester,
  ) async {
    final today = DateTime.now();
    final yesterday = today.subtract(const Duration(days: 1));
    final twoDaysAgo = today.subtract(const Duration(days: 2));
    final threeDaysAgo = today.subtract(const Duration(days: 3));
    final olderDate = today.subtract(const Duration(days: 250));
    final profile = ProfileUsage(
      summary: const TokenUsageSummary(),
      dailyUsageBuckets: [
        DailyTokenBucket(startDate: _dateKey(yesterday), tokens: 5),
        DailyTokenBucket(startDate: _dateKey(yesterday), tokens: 7),
        DailyTokenBucket(startDate: _dateKey(twoDaysAgo), tokens: -4),
        DailyTokenBucket(startDate: _dateKey(today), tokens: 999),
        DailyTokenBucket(startDate: _dateKey(olderDate), tokens: 3),
      ],
      fetchedAt: 1,
    );
    const account = StoredAccount(
      identityHash: 'profile-account',
      email: 'profile@example.com',
      loginState: LoginState.signedOut,
    );
    await tester.pumpWidget(
      AiUsageApp(
        controller: AppController.testing(
          accounts: const [account],
          profileUsage: profile,
        ),
      ),
    );

    await tester.tap(find.text('History'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('${_dateKey(yesterday)} · 12'), findsOneWidget);
    expect(find.byTooltip('${_dateKey(twoDaysAgo)} · 0'), findsOneWidget);
    expect(find.byTooltip('${_dateKey(threeDaysAgo)} · 0'), findsOneWidget);
    expect(find.byTooltip('${_dateKey(olderDate)} · 3'), findsOneWidget);
    expect(find.byTooltip('${_dateKey(today)} · 999'), findsNothing);
    expect(find.textContaining('ends yesterday'), findsOneWidget);
  });

  testWidgets('extra credits hide zero balance and show positive balance', (
    tester,
  ) async {
    await tester.pumpWidget(
      AiUsageApp(controller: _controllerWithCredits(balance: '0.00')),
    );
    expect(find.text('Extra credits'), findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpWidget(
      AiUsageApp(controller: _controllerWithCredits(balance: '1.25')),
    );
    await tester.pump();
    expect(find.text('Extra credits'), findsOneWidget);
  });

  testWidgets(
    'extra credits show unlimited and fall back for invalid balance',
    (tester) async {
      await tester.pumpWidget(
        AiUsageApp(controller: _controllerWithCredits(unlimited: true)),
      );
      expect(find.text('Extra credits'), findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpWidget(
        AiUsageApp(
          controller: _controllerWithCredits(
            balance: 'not-a-number',
            hasCredits: true,
          ),
        ),
      );
      await tester.pump();
      expect(find.text('Extra credits'), findsOneWidget);
    },
  );

  testWidgets('account details use a secondary scaffold and source label', (
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

    await tester.tap(find.text('Accounts'));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.info_outline));
    await tester.pumpAndSettle();

    expect(find.byType(AppBar), findsOneWidget);
    expect(find.byType(NavigationBar), findsNothing);
    expect(find.text('Credential source'), findsOneWidget);
    expect(find.text('Demo data'), findsWidgets);

    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(find.text('Accounts'), findsWidgets);
  });

  testWidgets(
    'Android back returns primary pages to dashboard then requires two exits',
    (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      try {
        var exitCalls = 0;
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(SystemChannels.platform, (call) async {
              if (call.method == 'SystemNavigator.pop') exitCalls += 1;
              return null;
            });
        addTearDown(
          () => TestDefaultBinaryMessengerBinding
              .instance
              .defaultBinaryMessenger
              .setMockMethodCallHandler(SystemChannels.platform, null),
        );
        await tester.pumpWidget(
          AiUsageApp(controller: AppController.testing()),
        );

        await tester.tap(find.text('History'));
        await tester.pumpAndSettle();
        await tester.binding.handlePopRoute();
        await tester.pumpAndSettle();
        expect(find.text('Dashboard'), findsWidgets);

        await tester.binding.handlePopRoute();
        await tester.pump();
        expect(find.text('Press back again to exit AiUsage'), findsOneWidget);
        expect(exitCalls, 0);
        await tester.binding.handlePopRoute();
        await tester.pump();
        expect(exitCalls, 1);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    },
  );

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

AppController _controllerWithCredits({
  String? balance,
  bool unlimited = false,
  bool hasCredits = false,
}) {
  const accountInfo = AccountInfo(
    identityHash: 'credits-account',
    email: 'credits@example.com',
    plan: 'plus',
    isFedramp: false,
    loginState: LoginState.signedIn,
    credentialStatus: CredentialStatus.available,
  );
  const account = StoredAccount(
    identityHash: 'credits-account',
    email: 'credits@example.com',
    plan: 'plus',
    loginState: LoginState.signedIn,
  );
  return AppController.testing(
    accounts: const [account],
    usage: UsageResult(
      snapshot: UsageSnapshot(
        account: accountInfo,
        windows: const [],
        credits: CreditsSnapshot(
          hasCredits: hasCredits,
          unlimited: unlimited,
          balance: balance,
        ),
        fetchedAt: 1,
      ),
      state: UsageState.fresh,
      showingCachedData: false,
    ),
  );
}

String _dateKey(DateTime date) =>
    '${date.year.toString().padLeft(4, '0')}-'
    '${date.month.toString().padLeft(2, '0')}-'
    '${date.day.toString().padLeft(2, '0')}';
