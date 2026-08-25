import 'package:ai_usage/src/app.dart';
import 'package:ai_usage/src/app_controller.dart';
import 'package:ai_usage/src/rust/models.dart';
import 'package:ai_usage/src/services/secure_account_vault.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
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
    expect(
      StoredAccount.fromMetadata(const {
        'identity_hash': 'old-account',
        'login_state': 'signedIn',
      }).provider,
      ProviderKind.codex,
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

  test('provider and per-provider account selections persist in settings', () {
    const settings = MonitorSettings(
      selectedProvider: ProviderKind.deepSeek,
      selectedAccountByProvider: {
        'codex': 'codex-account',
        'deepSeek': 'deepseek-account',
      },
    );

    final restored = MonitorSettings.fromJson(settings.toJson());
    expect(restored.selectedProvider, ProviderKind.deepSeek);
    expect(restored.selectedAccountByProvider['codex'], 'codex-account');
    expect(restored.selectedAccountByProvider['deepSeek'], 'deepseek-account');
  });

  test('demo mode provides synthetic data for every provider', () async {
    final controller = AppController.testing(
      settings: const MonitorSettings(demoModeEnabled: true, demoSeed: 7),
    );
    expect(controller.accounts.map((item) => item.provider).toSet(), {
      ProviderKind.codex,
      ProviderKind.deepSeek,
      ProviderKind.mimo,
    });
    await controller.selectAccount('demo-deepseek');
    expect(controller.usage!.snapshot!.balances, isNotEmpty);
    await controller.selectAccount('demo-mimo');
    expect(controller.usage!.snapshot!.providerQuotas, isNotEmpty);
  });

  testWidgets('empty dashboard offers account login', (tester) async {
    await tester.pumpWidget(AiUsageApp(controller: AppController.testing()));

    expect(
      find.text(
        'Monitor ChatGPT quotas, DeepSeek balances, or Xiaomi MiMo balances and Token Plans.',
      ),
      findsOneWidget,
    );
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

    expect(
      find.text('可监控 ChatGPT 额度、DeepSeek 余额或 Xiaomi MiMo 余额与 Token 套餐。'),
      findsOneWidget,
    );
  });

  test('provider credentials round-trip only through secure storage', () async {
    FlutterSecureStorage.setMockInitialValues({});
    final vault = SecureAccountVault();
    const deepSeek = AccountInfo(
      provider: ProviderKind.deepSeek,
      identityHash: 'deepseek-hash',
      plan: 'API',
      isFedramp: false,
      loginState: LoginState.signedIn,
      credentialStatus: CredentialStatus.available,
    );
    await vault.saveDeepSeek(
      deepSeek,
      'test-key-not-real',
      displayName: 'Main',
    );
    final loaded = (await vault.loadAccounts()).single;
    expect(loaded.provider, ProviderKind.deepSeek);
    expect(loaded.apiKey, 'test-key-not-real');
    expect(
      loaded.toMetadata().toString(),
      isNot(contains('test-key-not-real')),
    );

    const mimo = AccountInfo(
      provider: ProviderKind.mimo,
      identityHash: 'mimo-hash',
      plan: 'MiMo',
      isFedramp: false,
      loginState: LoginState.signedIn,
      credentialStatus: CredentialStatus.available,
    );
    const session = MimoCredential(
      userId: 'user-test',
      passToken: 'pass-test',
      serviceToken: 'service-test',
      serviceSlh: 'slh-test',
      servicePh: 'ph-test',
    );
    await vault.saveMimo(
      mimo,
      session,
      credentialSource: CredentialSource.xiaomiPassword,
    );
    final mimoLoaded = (await vault.loadAccounts()).first;
    expect(mimoLoaded.mimoCredential, session);
    expect(mimoLoaded.toMetadata().toString(), isNot(contains('pass-test')));
  });

  testWidgets('add account offers all three providers', (tester) async {
    await tester.pumpWidget(AiUsageApp(controller: AppController.testing()));
    await tester.tap(find.byType(FilledButton).first);
    await tester.pumpAndSettle();

    expect(find.text('ChatGPT'), findsOneWidget);
    expect(find.text('DeepSeek'), findsOneWidget);
    expect(find.text('Xiaomi MiMo'), findsOneWidget);
  });

  testWidgets('auth.json import waits for a selected credential before save', (
    tester,
  ) async {
    await tester.pumpWidget(AiUsageApp(controller: AppController.testing()));
    await tester.tap(find.byType(FilledButton).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('ChatGPT'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Import auth.json'));
    await tester.pumpAndSettle();

    expect(find.text('Credential import: Not imported'), findsOneWidget);
    final save = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Save'),
    );
    expect(save.onPressed, isNull);
  });

  testWidgets('dashboard account header prefers matching custom name', (
    tester,
  ) async {
    const stored = StoredAccount(
      identityHash: 'named-account',
      email: 'stored@example.com',
      displayName: 'Dashboard alias',
      plan: 'plus',
      loginState: LoginState.signedIn,
    );
    const snapshotAccount = AccountInfo(
      provider: ProviderKind.codex,
      identityHash: 'named-account',
      email: 'snapshot@example.com',
      plan: 'plus',
      isFedramp: false,
      loginState: LoginState.signedIn,
      credentialStatus: CredentialStatus.available,
    );
    await tester.pumpWidget(
      AiUsageApp(
        controller: AppController.testing(
          accounts: const [stored],
          usage: const UsageResult(
            snapshot: UsageSnapshot(
              account: snapshotAccount,
              windows: [],
              balances: [],
              providerQuotas: [],
              fetchedAt: 1,
            ),
            state: UsageState.fresh,
            showingCachedData: false,
          ),
        ),
      ),
    );

    expect(find.text('Dashboard alias'), findsOneWidget);
    expect(find.text('snapshot@example.com'), findsNothing);
  });

  testWidgets('self-destruct requires ten taps before the first warning', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    await tester.pumpWidget(AiUsageApp(controller: AppController.testing()));
    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('About'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Danger zone'));
    await tester.pumpAndSettle();

    for (var index = 0; index < 9; index++) {
      await tester.tap(find.text('Self-destruct'));
      await tester.pump();
    }
    expect(find.text('Irreversible data destruction'), findsNothing);
    await tester.tap(find.text('Self-destruct'));
    await tester.pump();
    expect(find.text('Irreversible data destruction'), findsOneWidget);
    expect(find.byIcon(Icons.delete_forever), findsWidgets);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('DeepSeek renders separate currencies and has no token history', (
    tester,
  ) async {
    const info = AccountInfo(
      provider: ProviderKind.deepSeek,
      identityHash: 'deepseek-account',
      plan: 'API',
      isFedramp: false,
      loginState: LoginState.signedIn,
      credentialStatus: CredentialStatus.available,
    );
    const account = StoredAccount(
      provider: ProviderKind.deepSeek,
      identityHash: 'deepseek-account',
      displayName: 'DeepSeek main',
      plan: 'API',
      loginState: LoginState.signedIn,
      credentialSource: CredentialSource.apiKey,
    );
    final controller = AppController.testing(
      accounts: const [account],
      usage: const UsageResult(
        snapshot: UsageSnapshot(
          account: info,
          windows: [],
          balances: [
            BalanceMetric(
              id: 'deepseek:CNY:total',
              label: 'Total balance',
              amount: '12.50',
              currency: 'CNY',
              primary: true,
            ),
            BalanceMetric(
              id: 'deepseek:USD:total',
              label: 'Total balance',
              amount: '3.25',
              currency: 'USD',
              primary: true,
            ),
          ],
          providerQuotas: [],
          fetchedAt: 1,
        ),
        state: UsageState.fresh,
        showingCachedData: false,
      ),
    );
    await tester.pumpWidget(AiUsageApp(controller: controller));
    await tester.pumpAndSettle();

    expect(find.text('12.50 CNY'), findsOneWidget);
    expect(find.text('3.25 USD'), findsOneWidget);
    await tester.tap(find.byIcon(Icons.show_chart_outlined));
    await tester.pumpAndSettle();
    expect(
      find.text('This provider does not currently expose Token history.'),
      findsOneWidget,
    );
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

  testWidgets('account cards remain readable on narrow large-text layouts', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    const account = StoredAccount(
      identityHash: 'long-account',
      email: 'a-very-long-account-identifier@example.com',
      displayName: 'A very long custom account name for the dashboard',
      plan: 'ChatGPT Plus with a long plan name',
      loginState: LoginState.signedIn,
      credentialSource: CredentialSource.deviceCode,
    );
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(textScaler: TextScaler.linear(2)),
        child: AiUsageApp(
          controller: AppController.testing(accounts: const [account]),
        ),
      ),
    );
    await tester.tap(find.text('Accounts'));
    await tester.pumpAndSettle();

    expect(find.text(account.displayName!), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('account page filters accounts to the selected provider', (
    tester,
  ) async {
    const codex = StoredAccount(
      identityHash: 'codex-account',
      displayName: 'Codex only',
      loginState: LoginState.signedOut,
    );
    const deepSeek = StoredAccount(
      identityHash: 'deepseek-account',
      provider: ProviderKind.deepSeek,
      displayName: 'DeepSeek only',
      loginState: LoginState.signedIn,
      credentialSource: CredentialSource.apiKey,
    );
    await tester.pumpWidget(
      AiUsageApp(
        controller: AppController.testing(
          accounts: const [codex, deepSeek],
          settings: const MonitorSettings(
            selectedProvider: ProviderKind.deepSeek,
            selectedAccountByProvider: {'deepSeek': 'deepseek-account'},
          ),
        ),
      ),
    );

    await tester.tap(find.text('Accounts'));
    await tester.pumpAndSettle();
    expect(find.text('DeepSeek only'), findsOneWidget);
    expect(find.text('Codex only'), findsNothing);
  });

  testWidgets('provider account details show a masked DeepSeek API key', (
    tester,
  ) async {
    const account = StoredAccount(
      identityHash: 'deepseek-account',
      provider: ProviderKind.deepSeek,
      displayName: 'DeepSeek main',
      loginState: LoginState.signedIn,
      apiKey: 'sk-test-secret-9876',
      credentialSource: CredentialSource.apiKey,
    );
    await tester.pumpWidget(
      AiUsageApp(controller: AppController.testing(accounts: const [account])),
    );

    await tester.tap(find.text('Accounts'));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.info_outline));
    await tester.pumpAndSettle();
    expect(find.text('API Key fingerprint'), findsOneWidget);
    expect(find.text('sk-tes…9876'), findsOneWidget);
    expect(find.text('sk-test-secret-9876'), findsNothing);
  });

  testWidgets('settings exposes four categorized secondary entries', (
    tester,
  ) async {
    await tester.pumpWidget(AiUsageApp(controller: AppController.testing()));
    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();

    expect(find.text('Appearance & language'), findsOneWidget);
    expect(find.text('Monitoring & notifications'), findsOneWidget);
    expect(find.text('Data & diagnostics'), findsOneWidget);
    expect(find.text('About'), findsOneWidget);
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
    expect(find.text('Token usage chart'), findsOneWidget);
    expect(find.text('Daily'), findsOneWidget);
    expect(find.text('Weekly'), findsOneWidget);
    expect(find.text('Cumulative'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('token chart switches views and excludes today from daily', (
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
    final controller = AppController.testing(
      accounts: const [account],
      profileUsage: profile,
    );
    await tester.pumpWidget(AiUsageApp(controller: controller));

    await tester.tap(find.text('History'));
    await tester.pumpAndSettle();
    expect(
      find.byTooltip('${_dateKey(yesterday)} · 12 tokens'),
      findsOneWidget,
    );
    expect(
      find.byTooltip('${_dateKey(twoDaysAgo)} · 0 tokens'),
      findsOneWidget,
    );
    expect(
      find.byTooltip('${_dateKey(threeDaysAgo)} · 0 tokens'),
      findsOneWidget,
    );
    expect(find.byTooltip('${_dateKey(olderDate)} · 3 tokens'), findsOneWidget);
    expect(find.byTooltip('${_dateKey(today)} · 999 tokens'), findsNothing);
    expect(find.textContaining('ends yesterday'), findsOneWidget);

    await tester.tap(find.text('Weekly'));
    await tester.pump();
    final weekStart = _dateKey(
      yesterday.subtract(Duration(days: yesterday.weekday % 7)),
    );
    expect(find.byTooltip('Week of $weekStart · 12 tokens'), findsOneWidget);

    await tester.tap(find.text('Cumulative'));
    await tester.pump();
    expect(
      find.byTooltip('Through week of $weekStart · 15 tokens'),
      findsOneWidget,
    );
    expect(identical(controller.profileUsage, profile), isTrue);
  });

  testWidgets('valid empty profile uses a neutral no-data message', (
    tester,
  ) async {
    const account = StoredAccount(
      identityHash: 'empty-profile-account',
      email: 'empty@example.com',
      loginState: LoginState.signedOut,
    );
    await tester.pumpWidget(
      AiUsageApp(
        controller: AppController.testing(
          accounts: const [account],
          profileUsage: const ProfileUsage(
            summary: TokenUsageSummary(),
            dailyUsageBuckets: [],
            fetchedAt: 1,
          ),
        ),
      ),
    );

    await tester.tap(find.text('History'));
    await tester.pumpAndSettle();
    expect(find.text('No daily Token statistics yet.'), findsOneWidget);
    expect(find.textContaining('Profile API returned no'), findsNothing);
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
    await tester.tap(find.byIcon(Icons.info_outline).first);
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
    final controller = AppController.testing(
      settings: const MonitorSettings(
        locale: LocalePreference.simplifiedChinese,
        demoModeEnabled: true,
        demoSeed: 7,
      ),
    );
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(textScaler: TextScaler.linear(2)),
        child: AiUsageApp(controller: controller),
      ),
    );
    await tester.pumpAndSettle();
    await controller.refresh();
    await tester.pump();
    await tester.tap(
      find.descendant(
        of: find.byType(NavigationBar),
        matching: find.byIcon(Icons.show_chart_outlined),
      ),
    );
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('Token 使用量图表'), 400);
    expect(find.text('每日'), findsOneWidget);
    expect(find.text('每周'), findsOneWidget);
    expect(find.text('累计'), findsOneWidget);
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
    provider: ProviderKind.codex,
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
        balances: const [],
        providerQuotas: const [],
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
