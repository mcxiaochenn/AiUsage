import 'dart:async';

import 'package:dynamic_color/dynamic_color.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import 'app_controller.dart';
import '../l10n/app_localizations.dart';
import 'rust/models.dart';
import 'services/secure_account_vault.dart';
import 'services/self_destruct_service.dart';
import 'services/system_settings.dart';
import 'widgets/token_usage_chart.dart';

final appControllerProvider = ChangeNotifierProvider<AppController>(
  (ref) => throw UnimplementedError('The app controller must be overridden.'),
);

class AiUsageApp extends StatelessWidget {
  const AiUsageApp({super.key, required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) => ProviderScope(
    overrides: [appControllerProvider.overrideWith((ref) => controller)],
    child: const _MonitorRouter(),
  );
}

class _MonitorRouter extends ConsumerStatefulWidget {
  const _MonitorRouter();

  @override
  ConsumerState<_MonitorRouter> createState() => _MonitorRouterState();
}

class _MonitorRouterState extends ConsumerState<_MonitorRouter>
    with WidgetsBindingObserver {
  late final GoRouter _router = GoRouter(
    routes: [
      GoRoute(
        path: '/',
        builder: (context, state) =>
            const _AppShell(selectedIndex: 0, child: DashboardPage()),
      ),
      GoRoute(
        path: '/accounts',
        builder: (context, state) =>
            const _AppShell(selectedIndex: 1, child: AccountsPage()),
      ),
      GoRoute(
        path: '/history',
        builder: (context, state) =>
            const _AppShell(selectedIndex: 2, child: HistoryPage()),
      ),
      GoRoute(
        path: '/settings',
        builder: (context, state) =>
            const _AppShell(selectedIndex: 3, child: SettingsPage()),
      ),
      GoRoute(
        path: '/settings/appearance',
        builder: (context, state) => const _SettingsAppearanceRoute(),
      ),
      GoRoute(
        path: '/settings/monitoring',
        builder: (context, state) => const _SettingsMonitoringRoute(),
      ),
      GoRoute(
        path: '/settings/data',
        builder: (context, state) => const _SettingsDataRoute(),
      ),
      GoRoute(
        path: '/settings/about',
        builder: (context, state) => const _AboutRoute(),
      ),
      GoRoute(
        path: '/account-details',
        builder: (context, state) => const _AccountDetailsRoute(),
      ),
      GoRoute(
        path: '/diagnostics',
        builder: (context, state) => const _DiagnosticsRoute(),
      ),
      GoRoute(
        path: '/mimo-login',
        builder: (context, state) =>
            _MimoChallengePage(args: state.extra! as _MimoChallengeArgs),
      ),
    ],
  );

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _router.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(
        ref.read(appControllerProvider).refresh(trigger: SyncTrigger.resume),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(appControllerProvider).settings;
    return DynamicColorBuilder(
      builder: (lightDynamic, darkDynamic) {
        final useDynamic = settings.dynamicColorEnabled && lightDynamic != null;
        return MaterialApp.router(
          onGenerateTitle: (context) => AppLocalizations.of(context).appTitle,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: switch (settings.locale) {
            LocalePreference.system => null,
            LocalePreference.english => const Locale('en'),
            LocalePreference.simplifiedChinese => const Locale('zh'),
          },
          debugShowCheckedModeBanner: false,
          themeMode: switch (settings.theme) {
            ThemePreference.system => ThemeMode.system,
            ThemePreference.light => ThemeMode.light,
            ThemePreference.dark => ThemeMode.dark,
          },
          theme: ThemeData(
            colorScheme: useDynamic
                ? lightDynamic
                : ColorScheme.fromSeed(seedColor: Colors.indigo),
            useMaterial3: true,
          ),
          darkTheme: ThemeData(
            colorScheme: settings.dynamicColorEnabled && darkDynamic != null
                ? darkDynamic
                : ColorScheme.fromSeed(
                    seedColor: Colors.indigo,
                    brightness: Brightness.dark,
                  ),
            useMaterial3: true,
          ),
          routerConfig: _router,
        );
      },
    );
  }
}

class _AppShell extends ConsumerStatefulWidget {
  const _AppShell({required this.selectedIndex, required this.child});

  final int selectedIndex;
  final Widget child;

  @override
  ConsumerState<_AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<_AppShell> {
  static const _routes = ['/', '/accounts', '/history', '/settings'];
  static const _icons = [
    Icons.space_dashboard_outlined,
    Icons.manage_accounts_outlined,
    Icons.show_chart_outlined,
    Icons.settings_outlined,
  ];

  Timer? _exitTimer;
  bool _exitArmed = false;

  @override
  void dispose() {
    _exitTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = ref.watch(appControllerProvider);
    final desktop = MediaQuery.sizeOf(context).width >= 820;
    final l10n = AppLocalizations.of(context);
    final labels = [l10n.dashboard, l10n.accounts, l10n.history, l10n.settings];
    final content = Scaffold(
      appBar: AppBar(
        titleSpacing: desktop ? NavigationToolbar.kMiddleSpacing : 8,
        title: desktop
            ? Text(l10n.appTitle)
            : controller.accounts.isEmpty
            ? Text(l10n.appTitle)
            : _ProviderDropdown(controller: controller, expanded: true),
        actions: [
          if (desktop && controller.accounts.isNotEmpty)
            SizedBox(
              width: 260,
              child: _ProviderDropdown(controller: controller),
            ),
          IconButton(
            tooltip: l10n.refresh,
            onPressed: controller.refreshing
                ? null
                : () => unawaited(controller.refresh()),
            icon: controller.refreshing
                ? const SizedBox(
                    height: 18,
                    width: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.refresh),
          ),
          if (desktop)
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: FilledButton.icon(
                onPressed: () => _showAddAccount(context),
                icon: const Icon(Icons.person_add_alt_1),
                label: Text(l10n.addAccount),
              ),
            )
          else
            IconButton(
              tooltip: l10n.addAccount,
              onPressed: () => _showAddAccount(context),
              icon: const Icon(Icons.person_add_alt_1),
            ),
        ],
      ),
      body: widget.child,
      bottomNavigationBar: desktop
          ? null
          : NavigationBar(
              selectedIndex: widget.selectedIndex,
              onDestinationSelected: (index) => context.go(_routes[index]),
              destinations: List.generate(
                labels.length,
                (index) => NavigationDestination(
                  icon: Icon(_icons[index]),
                  label: labels[index],
                ),
              ),
            ),
    );
    final shell = !desktop
        ? content
        : Scaffold(
            body: Row(
              children: [
                NavigationRail(
                  selectedIndex: widget.selectedIndex,
                  labelType: NavigationRailLabelType.all,
                  onDestinationSelected: (index) => context.go(_routes[index]),
                  destinations: List.generate(
                    labels.length,
                    (index) => NavigationRailDestination(
                      icon: Icon(_icons[index]),
                      label: Text(labels[index]),
                    ),
                  ),
                ),
                const VerticalDivider(width: 1),
                Expanded(child: content),
              ],
            ),
          );
    final android = defaultTargetPlatform == TargetPlatform.android;
    if (!android) return shell;
    return PopScope<Object?>(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        if (widget.selectedIndex != 0) {
          _disarmExit();
          context.go('/');
          return;
        }
        if (_exitArmed) {
          SystemNavigator.pop();
          return;
        }
        _armExit(context);
      },
      child: shell,
    );
  }

  void _armExit(BuildContext context) {
    _exitTimer?.cancel();
    setState(() => _exitArmed = true);
    _exitTimer = Timer(const Duration(seconds: 2), _disarmExit);
    final messenger = ScaffoldMessenger.of(context);
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(AppLocalizations.of(context).pressBackAgainToExit),
          duration: const Duration(seconds: 2),
        ),
      );
  }

  void _disarmExit() {
    _exitTimer?.cancel();
    if (!mounted || !_exitArmed) return;
    setState(() => _exitArmed = false);
  }
}

class _SecondaryPageScaffold extends StatelessWidget {
  const _SecondaryPageScaffold({
    required this.parentPath,
    required this.title,
    required this.child,
    this.actions = const [],
  });

  final String parentPath;
  final String title;
  final Widget child;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final canPop = context.canPop();
    return PopScope<Object?>(
      canPop: canPop,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) context.go(parentPath);
      },
      child: Scaffold(
        appBar: AppBar(
          automaticallyImplyLeading: false,
          leading: BackButton(onPressed: () => _popOrGo(context, parentPath)),
          title: Text(title),
          actions: actions,
        ),
        body: child,
      ),
    );
  }
}

class _AccountDetailsRoute extends ConsumerWidget {
  const _AccountDetailsRoute();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.watch(appControllerProvider);
    final account = controller.selectedAccount;
    final l10n = AppLocalizations.of(context);
    return _SecondaryPageScaffold(
      parentPath: '/accounts',
      title: l10n.accountDetails,
      actions: [
        if (controller.accountDetailsLoading)
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 12),
            child: Center(
              child: SizedBox.square(
                dimension: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          )
        else
          IconButton(
            tooltip: l10n.refresh,
            onPressed: account == null
                ? null
                : () => unawaited(
                    controller.loadAccountDetails(account, force: true),
                  ),
            icon: const Icon(Icons.refresh),
          ),
      ],
      child: const AccountDetailsPage(),
    );
  }
}

class _DiagnosticsRoute extends ConsumerWidget {
  const _DiagnosticsRoute();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.watch(appControllerProvider);
    final l10n = AppLocalizations.of(context);
    return _SecondaryPageScaffold(
      parentPath: '/settings',
      title: l10n.diagnostics,
      actions: [
        IconButton(
          tooltip: l10n.clearDiagnostics,
          onPressed: controller.syncLogs.isEmpty
              ? null
              : () => _clearDiagnostics(context, controller),
          icon: const Icon(Icons.delete_sweep_outlined),
        ),
        IconButton(
          tooltip: l10n.refresh,
          onPressed: () => unawaited(controller.loadSyncLogs()),
          icon: const Icon(Icons.refresh),
        ),
      ],
      child: const DiagnosticsPage(),
    );
  }
}

class _MimoChallengeArgs {
  const _MimoChallengeArgs({
    required this.challengeUrl,
    this.displayName,
    this.accountHint,
  });

  final String challengeUrl;
  final String? displayName;
  final String? accountHint;
}

class _MimoChallengePage extends ConsumerStatefulWidget {
  const _MimoChallengePage({required this.args});

  final _MimoChallengeArgs args;

  @override
  ConsumerState<_MimoChallengePage> createState() => _MimoChallengePageState();
}

class _MimoChallengePageState extends ConsumerState<_MimoChallengePage> {
  bool _capturing = false;
  String? _error;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return _SecondaryPageScaffold(
      parentPath: '/accounts',
      title: l10n.mimoChallengeTitle,
      child: Column(
        children: [
          MaterialBanner(
            content: Text(l10n.mimoChallengeMessage),
            actions: const [SizedBox.shrink()],
          ),
          if (_capturing) const LinearProgressIndicator(),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.all(8),
              child: Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          Expanded(
            child: InAppWebView(
              initialUrlRequest: URLRequest(
                url: WebUri(widget.args.challengeUrl),
              ),
              initialSettings: InAppWebViewSettings(
                javaScriptEnabled: true,
                thirdPartyCookiesEnabled: true,
                useShouldOverrideUrlLoading: true,
              ),
              shouldOverrideUrlLoading: (controller, action) async {
                final uri = action.request.url;
                if (uri == null) return NavigationActionPolicy.CANCEL;
                if (uri.scheme == 'https' && _isAllowedMimoHost(uri.host)) {
                  return NavigationActionPolicy.ALLOW;
                }
                await launchUrl(
                  Uri.parse(uri.toString()),
                  mode: LaunchMode.externalApplication,
                );
                return NavigationActionPolicy.CANCEL;
              },
              onLoadStop: (controller, url) async {
                if (url?.host == 'platform.xiaomimimo.com') {
                  await _captureSession();
                }
              },
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _captureSession() async {
    if (_capturing) return;
    setState(() {
      _capturing = true;
      _error = null;
    });
    try {
      final manager = CookieManager.instance();
      final accountCookies = await manager.getCookies(
        url: WebUri('https://account.xiaomi.com/'),
      );
      final platformCookies = await manager.getCookies(
        url: WebUri('https://platform.xiaomimimo.com/'),
      );
      String header(List<Cookie> cookies) =>
          cookies.map((cookie) => '${cookie.name}=${cookie.value}').join('; ');
      await ref
          .read(appControllerProvider)
          .completeMimoWebAccount(
            accountCookie: header(accountCookies),
            platformCookie: header(platformCookies),
            displayName: widget.args.displayName,
            accountHint: widget.args.accountHint,
          );
      if (mounted) _popOrGo(context, '/accounts');
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _capturing = false);
    }
  }
}

bool _isAllowedMimoHost(String host) =>
    host == 'account.xiaomi.com' ||
    host.endsWith('.account.xiaomi.com') ||
    host == 'platform.xiaomimimo.com' ||
    host.endsWith('.xiaomimimo.com') ||
    host == 'sts.api.io.mi.com';

void _popOrGo(BuildContext context, String fallbackPath) {
  if (context.canPop()) {
    context.pop();
  } else {
    context.go(fallbackPath);
  }
}

class _ProviderDropdown extends StatelessWidget {
  const _ProviderDropdown({required this.controller, this.expanded = false});

  final AppController controller;
  final bool expanded;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return DropdownButtonHideUnderline(
      child: DropdownButton<ProviderKind>(
        isExpanded: expanded,
        value: controller.selectedProvider,
        hint: Text(l10n.provider),
        items: controller.availableProviders
            .map(
              (provider) => DropdownMenuItem(
                value: provider,
                child: Row(
                  children: [
                    _ProviderAvatar(provider: provider, radius: 12),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _providerLabel(context, provider),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
            )
            .toList(),
        onChanged: (value) {
          if (value != null) unawaited(controller.selectProvider(value));
        },
      ),
    );
  }
}

class DashboardPage extends ConsumerWidget {
  const DashboardPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.watch(appControllerProvider);
    final l10n = AppLocalizations.of(context);
    if (controller.loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (controller.accounts.isEmpty) {
      return _EmptyState(
        icon: Icons.monitor_heart_outlined,
        title: l10n.addAccount,
        message: l10n.providerAccountsMessage,
        action: FilledButton.icon(
          onPressed: () => _showAddAccount(context),
          icon: const Icon(Icons.person_add_alt_1),
          label: Text(l10n.addAccount),
        ),
      );
    }
    final result = controller.usage;
    final snapshot = result?.snapshot;
    return RefreshIndicator(
      onRefresh: controller.refresh,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (controller.bootError != null)
            _StateBanner(
              message: l10n.storageInitFailed,
              details: controller.bootError,
              state: UsageState.serverError,
            ),
          if (result != null && result.state != UsageState.fresh)
            _StateBanner(
              message: _stateMessage(context, result.state),
              details: result.message,
              state: result.state,
              cached: result.showingCachedData,
            ),
          if (snapshot == null)
            _EmptyState(
              icon: Icons.cloud_off_outlined,
              title: l10n.noUsageSnapshot,
              message: l10n.noUsageSnapshotMessage,
            )
          else ...[
            _AccountHeader(
              snapshot: snapshot,
              account: controller.selectedAccount,
            ),
            const SizedBox(height: 12),
            if (controller.demoMode)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Chip(
                  avatar: const Icon(Icons.science_outlined, size: 18),
                  label: Text(l10n.demoData),
                ),
              ),
            _OverviewGrid(
              snapshot: snapshot,
              showResetCredits: controller.settings.showResetCredits,
            ),
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                l10n.updatedAt(
                  _relativeTime(context, snapshot.fetchedAt),
                  _absoluteTime(context, snapshot.fetchedAt),
                ),
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _AccountHeader extends StatelessWidget {
  const _AccountHeader({required this.snapshot, required this.account});

  final UsageSnapshot snapshot;
  final StoredAccount? account;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = Theme.of(context).colorScheme;
    return Card(
      color: colors.primaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            _ProviderAvatar(
              provider: snapshot.account.provider,
              account: account,
              radius: 24,
              backgroundColor: colors.primary,
              foregroundColor: colors.onPrimary,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    account != null &&
                            account!.identityHash ==
                                snapshot.account.identityHash
                        ? _accountDisplayName(context, account!)
                        : _providerAccountLabel(context, snapshot.account),
                    style: Theme.of(context).textTheme.titleMedium,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    '${_providerLabel(context, snapshot.account.provider)} · '
                    '${snapshot.account.plan ?? l10n.unknownPlan}',
                  ),
                ],
              ),
            ),
            Icon(
              Icons.verified_user_outlined,
              color: colors.onPrimaryContainer,
            ),
          ],
        ),
      ),
    );
  }
}

class _OverviewGrid extends StatelessWidget {
  const _OverviewGrid({required this.snapshot, required this.showResetCredits});

  final UsageSnapshot snapshot;
  final bool showResetCredits;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final cards = <Widget>[
      if (snapshot.windows.isEmpty &&
          snapshot.balances.isEmpty &&
          snapshot.providerQuotas.isEmpty)
        Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Text(l10n.noQuotaWindows),
          ),
        )
      else
        ...snapshot.windows.map((window) => _QuotaWindowCard(window: window)),
      ..._balanceCards(
        snapshot.balances,
      ).map((metrics) => _ProviderBalanceCard(metrics: metrics)),
      ...snapshot.providerQuotas.map(
        (quota) => _ProviderQuotaCard(quota: quota),
      ),
      if (snapshot.credits case final credits? when _shouldShowCredits(credits))
        _CreditsCard(credits: credits),
      if (showResetCredits && snapshot.resetCreditsAvailable != null)
        _ResetCreditsCard(snapshot: snapshot),
    ];
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 920
            ? 3
            : constraints.maxWidth >= 600
            ? 2
            : 1;
        final width = (constraints.maxWidth - (columns - 1) * 12) / columns;
        return Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            for (final card in cards)
              SizedBox(
                width: width,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: 230),
                  child: card,
                ),
              ),
          ],
        );
      },
    );
  }
}

class _QuotaWindowCard extends StatelessWidget {
  const _QuotaWindowCard({required this.window});

  final QuotaWindow window;

  @override
  Widget build(BuildContext context) => StreamBuilder<int>(
    stream: Stream<int>.periodic(const Duration(minutes: 1), (value) => value),
    builder: (context, _) {
      final l10n = AppLocalizations.of(context);
      final used = window.usedPercent.clamp(0, 100).toDouble();
      final remaining = (100 - used).clamp(0, 100).toDouble();
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _windowTitle(context, window),
                style: Theme.of(context).textTheme.titleMedium,
              ),
              Text(l10n.usedPercent(used.round())),
              const SizedBox(height: 12),
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: LinearProgressIndicator(
                  value: used / 100,
                  minHeight: 10,
                  color: used >= 95
                      ? Theme.of(context).colorScheme.error
                      : used >= 80
                      ? Colors.orange
                      : Theme.of(context).colorScheme.primary,
                  backgroundColor: Theme.of(
                    context,
                  ).colorScheme.surfaceContainerHighest,
                ),
              ),
              const SizedBox(height: 10),
              Text(l10n.remainingPercent(remaining.round())),
              const SizedBox(height: 4),
              Text(l10n.resetIn(_remainingTime(context, window.resetAt))),
              Text(
                l10n.resetsAt(_absoluteTime(context, window.resetAt)),
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
      );
    },
  );
}

List<List<BalanceMetric>> _balanceCards(List<BalanceMetric> metrics) {
  final grouped = <String, List<BalanceMetric>>{};
  for (final metric in metrics) {
    (grouped[metric.currency ?? ''] ??= []).add(metric);
  }
  return grouped.values.toList(growable: false);
}

class _ProviderBalanceCard extends StatelessWidget {
  const _ProviderBalanceCard({required this.metrics});

  final List<BalanceMetric> metrics;

  @override
  Widget build(BuildContext context) {
    BalanceMetric? primary;
    for (final metric in metrics) {
      if (metric.primary) {
        primary = metric;
        break;
      }
    }
    primary ??= metrics.isEmpty ? null : metrics.first;
    final currency = primary?.currency ?? '';
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.account_balance_wallet_outlined),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _balanceLabel(context, primary?.id ?? 'total'),
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Text(
              '${primary?.amount ?? '—'}${currency.isEmpty ? '' : ' $currency'}',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 8),
            for (final metric in metrics.where((item) => !item.primary))
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Row(
                  children: [
                    Expanded(child: Text(_balanceLabel(context, metric.id))),
                    Text(
                      '${metric.amount}${currency.isEmpty ? '' : ' $currency'}',
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _ProviderQuotaCard extends StatelessWidget {
  const _ProviderQuotaCard({required this.quota});

  final ProviderQuotaMetric quota;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final used = quota.usedPercent.clamp(0, 100).toDouble();
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              quota.id.startsWith('mimo:') ? l10n.tokenPlan : quota.title,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(l10n.usedOfTotal(quota.used, quota.limit, quota.unit)),
            const SizedBox(height: 12),
            LinearProgressIndicator(value: used / 100, minHeight: 10),
            const SizedBox(height: 8),
            Text('${quota.remaining} ${quota.unit}'),
            if (quota.expiresAt != null)
              Text(l10n.expiresAt(_absoluteTime(context, quota.expiresAt!))),
          ],
        ),
      ),
    );
  }
}

class _CreditsCard extends StatelessWidget {
  const _CreditsCard({required this.credits});

  final CreditsSnapshot credits;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.account_balance_wallet_outlined),
            const SizedBox(height: 12),
            Text(
              l10n.extraCredits,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 20),
            Text(
              credits.unlimited
                  ? l10n.unlimited
                  : credits.balance ?? l10n.balanceUnavailable,
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            Text(credits.hasCredits ? l10n.creditsAvailable : l10n.noCredits),
          ],
        ),
      ),
    );
  }
}

class _ResetCreditsCard extends StatelessWidget {
  const _ResetCreditsCard({required this.snapshot});

  final UsageSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final available = snapshot.resetCreditsAvailable ?? 0;
    final credits = snapshot.resetCredits ?? const <ResetCredit>[];
    final expiries =
        credits
            .where((credit) => credit.expiresAt != null)
            .map((credit) => credit.expiresAt!)
            .toList()
          ..sort();
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.restart_alt),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    l10n.resetCredits,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(l10n.resetCreditsReadOnly),
            const SizedBox(height: 16),
            Text(
              l10n.availableCount(available),
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            if (expiries.isNotEmpty)
              Text(l10n.earliestExpiry(_absoluteTime(context, expiries.first)))
            else
              Text(l10n.expiryUnavailable),
            if (credits.isNotEmpty)
              Text(
                credits
                    .map((credit) => credit.title ?? credit.status)
                    .join(' · '),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall,
              ),
          ],
        ),
      ),
    );
  }
}

class AccountsPage extends ConsumerWidget {
  const AccountsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.watch(appControllerProvider);
    final l10n = AppLocalizations.of(context);
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          controller.selectedProvider == null
              ? l10n.accounts
              : '${_providerLabel(context, controller.selectedProvider!)} · ${l10n.accounts}',
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        const SizedBox(height: 8),
        if (controller.currentProviderAccounts.isEmpty)
          _EmptyState(
            icon: Icons.person_off_outlined,
            title: l10n.noAccounts,
            message: l10n.noAccountsMessage,
          ),
        ...controller.currentProviderAccounts.map(
          (account) => _AccountManagementCard(
            account: account,
            selected:
                controller.selectedAccount?.identityHash ==
                account.identityHash,
            demo: controller.demoMode,
            onSelect: () =>
                unawaited(controller.selectAccount(account.identityHash)),
            onDetails: () async {
              await controller.selectAccount(account.identityHash);
              if (context.mounted) context.push('/account-details');
            },
            onRename: () => _renameAccount(context, controller, account),
            onRemove: () =>
                _accountAction(context, controller, account, 'remove'),
          ),
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: () => _showAddAccount(context),
          icon: const Icon(Icons.person_add_alt_1),
          label: Text(l10n.addAccount),
        ),
      ],
    );
  }

  Future<void> _accountAction(
    BuildContext context,
    AppController controller,
    StoredAccount account,
    String action,
  ) async {
    switch (action) {
      case 'remove':
        final l10n = AppLocalizations.of(context);
        final confirmed = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: Text(l10n.removeAccountQuestion),
            content: Text(l10n.removeAccountExplanation),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: Text(l10n.cancel),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: Text(l10n.remove),
              ),
            ],
          ),
        );
        if (confirmed ?? false) {
          await controller.removeAccount(account.identityHash);
        }
    }
  }

  Future<void> _renameAccount(
    BuildContext context,
    AppController controller,
    StoredAccount account,
  ) async {
    final value = await _showAccountNameDialog(
      context,
      initialValue: account.displayName,
    );
    if (value == null) return;
    await controller.renameAccount(account.identityHash, value);
  }
}

class _AccountManagementCard extends StatelessWidget {
  const _AccountManagementCard({
    required this.account,
    required this.selected,
    required this.demo,
    required this.onSelect,
    required this.onDetails,
    required this.onRename,
    required this.onRemove,
  });

  final StoredAccount account;
  final bool selected;
  final bool demo;
  final VoidCallback onSelect;
  final VoidCallback onDetails;
  final VoidCallback onRename;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = Theme.of(context).colorScheme;
    final title = _accountDisplayName(context, account);
    final identifier = _accountIdentifierValue(context, account);
    final showIdentifier =
        identifier != title && identifier != l10n.unavailable;
    return Card(
      color: selected ? colors.secondaryContainer : null,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onSelect,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _ProviderAvatar(
                    provider: account.provider,
                    account: account,
                    radius: 22,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        if (showIdentifier) ...[
                          const SizedBox(height: 3),
                          Text(
                            identifier,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ],
                    ),
                  ),
                  if (selected)
                    Padding(
                      padding: const EdgeInsets.only(left: 8),
                      child: Icon(Icons.check_circle, color: colors.primary),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: [
                  Chip(label: Text(account.plan ?? l10n.unknownPlan)),
                  Chip(
                    label: Text(_loginStateLabel(context, account.loginState)),
                  ),
                  Chip(
                    label: Text(
                      _credentialSourceLabel(context, account, demo: demo),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.schedule_outlined, size: 18),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      l10n.lastSuccessfulRefresh(
                        account.lastSuccessfulRefresh == null
                            ? l10n.never
                            : _absoluteTime(
                                context,
                                account.lastSuccessfulRefresh!,
                              ),
                      ),
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                ],
              ),
              const Divider(height: 22),
              Align(
                alignment: AlignmentDirectional.centerEnd,
                child: Wrap(
                  alignment: WrapAlignment.end,
                  spacing: 4,
                  runSpacing: 4,
                  children: [
                    TextButton.icon(
                      onPressed: onDetails,
                      icon: const Icon(Icons.info_outline),
                      label: Text(l10n.accountDetails),
                    ),
                    if (!demo)
                      TextButton.icon(
                        onPressed: onRename,
                        icon: const Icon(Icons.edit_outlined),
                        label: Text(l10n.renameAccount),
                      ),
                    if (!demo)
                      TextButton.icon(
                        onPressed: onRemove,
                        icon: const Icon(Icons.delete_outline),
                        label: Text(l10n.removeAccount),
                        style: TextButton.styleFrom(
                          foregroundColor: colors.error,
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

bool _shouldShowCredits(CreditsSnapshot credits) {
  if (credits.unlimited) return true;
  final balance = credits.balance;
  if (balance == null) return credits.hasCredits;
  final parsed = double.tryParse(balance.trim());
  if (parsed == null || !parsed.isFinite) return credits.hasCredits;
  return parsed > 0;
}

class AccountDetailsPage extends ConsumerStatefulWidget {
  const AccountDetailsPage({super.key});

  @override
  ConsumerState<AccountDetailsPage> createState() => _AccountDetailsPageState();
}

class _AccountDetailsPageState extends ConsumerState<AccountDetailsPage> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final controller = ref.read(appControllerProvider);
      final account = controller.selectedAccount;
      if (account != null) unawaited(controller.loadAccountDetails(account));
    });
  }

  @override
  Widget build(BuildContext context) {
    final controller = ref.watch(appControllerProvider);
    final account = controller.selectedAccount;
    final details = controller.accountDetails;
    final l10n = AppLocalizations.of(context);
    if (account == null) {
      return _EmptyState(
        icon: Icons.person_off_outlined,
        title: l10n.noAccounts,
        message: l10n.noAccountsMessage,
      );
    }
    final registeredDays = details == null
        ? null
        : (DateTime.now().millisecondsSinceEpoch ~/ 1000 - details.createdAt) ~/
              86400;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (controller.demoMode)
          Align(
            alignment: Alignment.centerLeft,
            child: Chip(label: Text(l10n.demoData)),
          ),
        Card(
          child: Column(
            children: [
              ListTile(
                leading: _ProviderAvatar(
                  provider: account.provider,
                  account: account,
                  radius: 24,
                ),
                title: Text(_accountDisplayName(context, account)),
                subtitle: Text(_providerLabel(context, account.provider)),
              ),
              const Divider(height: 1),
              _DetailTile(
                label: l10n.provider,
                value: _providerLabel(context, account.provider),
              ),
              _DetailTile(
                label: _accountIdentifierLabel(context, account),
                value: _accountIdentifierValue(context, account),
              ),
              _DetailTile(
                label: l10n.plan,
                value: account.plan ?? l10n.unknownPlan,
              ),
              _DetailTile(
                label: l10n.loginStatus,
                value: _loginStateLabel(context, account.loginState),
              ),
              _DetailTile(
                label: l10n.credentialSource,
                value: _credentialSourceLabel(
                  context,
                  account,
                  demo: controller.demoMode,
                ),
              ),
              _DetailTile(
                label: l10n.lastRefresh,
                value: account.lastSuccessfulRefresh == null
                    ? l10n.never
                    : _absoluteTime(context, account.lastSuccessfulRefresh!),
              ),
              if (account.provider == ProviderKind.codex) ...[
                _DetailTile(
                  label: l10n.fedramp,
                  value: account.isFedramp ? l10n.yes : l10n.no,
                ),
                _DetailTile(
                  label: l10n.registrationTime,
                  value: details == null
                      ? l10n.unavailable
                      : _absoluteTime(context, details.createdAt),
                ),
                _DetailTile(
                  label: l10n.registeredDays,
                  value: registeredDays == null
                      ? l10n.unavailable
                      : l10n.daysCount(registeredDays.clamp(0, 1 << 30)),
                ),
                _DetailTile(
                  label: l10n.accountDetailsFetchedAt,
                  value: details == null
                      ? l10n.unavailable
                      : _absoluteTime(context, details.fetchedAt),
                ),
              ],
            ],
          ),
        ),
        if (account.provider == ProviderKind.mimo)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              l10n.mimoInternalApiWarning,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        if (account.provider == ProviderKind.codex &&
            controller.accountDetailsLoading &&
            details == null)
          const LinearProgressIndicator(),
        if (controller.accountDetailsError != null)
          Card(
            child: ListTile(
              leading: const Icon(Icons.warning_amber_outlined),
              title: Text(
                details == null
                    ? l10n.accountDetailsUnavailable
                    : l10n.showingCachedAccountDetails,
              ),
              subtitle: Text(controller.accountDetailsError!),
              trailing: IconButton(
                tooltip: l10n.retry,
                onPressed: () => unawaited(
                  controller.loadAccountDetails(account, force: true),
                ),
                icon: const Icon(Icons.refresh),
              ),
            ),
          ),
      ],
    );
  }
}

class _DetailTile extends StatelessWidget {
  const _DetailTile({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => ListTile(
    title: Text(label),
    trailing: SizedBox(
      width: 180,
      child: Text(
        value,
        textAlign: TextAlign.end,
        overflow: TextOverflow.ellipsis,
      ),
    ),
  );
}

class HistoryPage extends ConsumerStatefulWidget {
  const HistoryPage({super.key});

  @override
  ConsumerState<HistoryPage> createState() => _HistoryPageState();
}

class _HistoryPageState extends ConsumerState<HistoryPage> {
  String? _requestedAccount;
  TokenUsageView _tokenUsageView = TokenUsageView.daily;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(ref.read(appControllerProvider).loadProfile());
    });
  }

  @override
  Widget build(BuildContext context) {
    final controller = ref.watch(appControllerProvider);
    final selected = controller.selectedAccount;
    final selectedId = selected?.identityHash;
    if (!controller.demoMode &&
        selectedId != null &&
        selectedId != _requestedAccount) {
      _requestedAccount = selectedId;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) unawaited(ref.read(appControllerProvider).loadProfile());
      });
    }
    final profile = controller.profileUsage;
    final l10n = AppLocalizations.of(context);
    if (selected != null && selected.provider != ProviderKind.codex) {
      return _EmptyState(
        icon: Icons.query_stats_outlined,
        title: _providerLabel(context, selected.provider),
        message: l10n.providerNoHistory,
      );
    }
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                l10n.tokenActivity,
                style: Theme.of(context).textTheme.headlineSmall,
              ),
            ),
            if (controller.demoMode) Chip(label: Text(l10n.demoData)),
            IconButton(
              tooltip: l10n.refresh,
              onPressed: controller.profileLoading || controller.demoMode
                  ? null
                  : () => unawaited(controller.loadProfile(force: true)),
              icon: const Icon(Icons.refresh),
            ),
          ],
        ),
        Text(l10n.profileMayLag, style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: 12),
        if (controller.profileLoading && profile == null)
          const SizedBox(
            height: 240,
            child: Center(child: CircularProgressIndicator()),
          )
        else if (profile == null)
          _EmptyState(
            icon: Icons.query_stats_outlined,
            title: l10n.profileUnavailable,
            message: controller.profileError ?? l10n.noHistoryMessage,
          )
        else ...[
          _TokenSummaryGrid(summary: profile.summary),
          const SizedBox(height: 12),
          TokenUsageChart(
            buckets: profile.dailyUsageBuckets,
            view: _tokenUsageView,
            onViewChanged: (view) => setState(() => _tokenUsageView = view),
          ),
          const SizedBox(height: 8),
          Text(
            l10n.profileUpdatedAt(_absoluteTime(context, profile.fetchedAt)),
            style: Theme.of(context).textTheme.bodySmall,
          ),
          if (controller.profileError != null)
            Text(
              l10n.showingCachedProfile,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
        ],
      ],
    );
  }
}

class _TokenSummaryGrid extends StatelessWidget {
  const _TokenSummaryGrid({required this.summary});

  final TokenUsageSummary summary;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final items = [
      (l10n.lifetimeTokens, _compactNumber(summary.lifetimeTokens)),
      (l10n.peakDailyTokens, _compactNumber(summary.peakDailyTokens)),
      (
        l10n.longestTask,
        summary.longestRunningTurnSec == null
            ? l10n.unavailable
            : _durationLabel(summary.longestRunningTurnSec!),
      ),
      (l10n.currentStreak, l10n.daysCount(summary.currentStreakDays ?? 0)),
      (l10n.longestStreak, l10n.daysCount(summary.longestStreakDays ?? 0)),
    ];
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth >= 700
            ? (constraints.maxWidth - 24) / 3
            : (constraints.maxWidth - 12) / 2;
        return Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            for (final item in items)
              SizedBox(
                width: width,
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(item.$1),
                        const SizedBox(height: 8),
                        Text(
                          item.$2,
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

String _compactNumber(int? value) {
  if (value == null) return '—';
  if (value >= 1000000000) return '${(value / 1000000000).toStringAsFixed(1)}B';
  if (value >= 1000000) return '${(value / 1000000).toStringAsFixed(1)}M';
  if (value >= 1000) return '${(value / 1000).toStringAsFixed(1)}K';
  return value.toString();
}

String _durationLabel(int seconds) {
  final duration = Duration(seconds: seconds);
  final hours = duration.inHours;
  final minutes = duration.inMinutes.remainder(60);
  return hours > 0 ? '${hours}h ${minutes}m' : '${minutes}m';
}

String _syncTriggerLabel(BuildContext context, SyncTrigger trigger) {
  final l10n = AppLocalizations.of(context);
  return switch (trigger) {
    SyncTrigger.manual => l10n.syncManual,
    SyncTrigger.resume => l10n.syncResume,
    SyncTrigger.foregroundTimer => l10n.syncForeground,
    SyncTrigger.background => l10n.syncBackground,
    SyncTrigger.pageLoad => l10n.syncPageLoad,
  };
}

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(l10n.settings, style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 8),
        _SettingsEntry(
          icon: Icons.palette_outlined,
          title: l10n.appearanceAndLanguage,
          subtitle: l10n.appearanceAndLanguageDescription,
          onTap: () => context.push('/settings/appearance'),
        ),
        _SettingsEntry(
          icon: Icons.notifications_active_outlined,
          title: l10n.monitoringAndNotifications,
          subtitle: l10n.monitoringAndNotificationsDescription,
          onTap: () => context.push('/settings/monitoring'),
        ),
        _SettingsEntry(
          icon: Icons.storage_outlined,
          title: l10n.dataAndDiagnostics,
          subtitle: l10n.dataAndDiagnosticsDescription,
          onTap: () => context.push('/settings/data'),
        ),
        _SettingsEntry(
          icon: Icons.info_outline,
          title: l10n.about,
          subtitle: l10n.aboutDescription,
          onTap: () => context.push('/settings/about'),
        ),
      ],
    );
  }
}

class _SettingsEntry extends StatelessWidget {
  const _SettingsEntry({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Card(
    child: ListTile(
      leading: Icon(icon),
      title: Text(title),
      subtitle: Text(subtitle),
      trailing: const Icon(Icons.chevron_right),
      onTap: onTap,
    ),
  );
}

class _SettingsAppearanceRoute extends StatelessWidget {
  const _SettingsAppearanceRoute();

  @override
  Widget build(BuildContext context) => _SecondaryPageScaffold(
    parentPath: '/settings',
    title: AppLocalizations.of(context).appearanceAndLanguage,
    child: const _AppearanceSettingsPage(),
  );
}

class _AppearanceSettingsPage extends ConsumerWidget {
  const _AppearanceSettingsPage();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.watch(appControllerProvider);
    final settings = controller.settings;
    final l10n = AppLocalizations.of(context);
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          child: Column(
            children: [
              ListTile(title: Text(l10n.theme)),
              RadioGroup<ThemePreference>(
                groupValue: settings.theme,
                onChanged: (value) {
                  if (value != null) {
                    unawaited(
                      controller.updateSettings(
                        settings.copyWith(theme: value),
                      ),
                    );
                  }
                },
                child: Column(
                  children: [
                    for (final value in ThemePreference.values)
                      RadioListTile<ThemePreference>(
                        value: value,
                        title: Text(_themeLabel(context, value)),
                      ),
                  ],
                ),
              ),
              const Divider(height: 1),
              SwitchListTile(
                title: Text(l10n.dynamicColor),
                subtitle: Text(l10n.dynamicColorDescription),
                value: settings.dynamicColorEnabled,
                onChanged: (value) => unawaited(
                  controller.updateSettings(
                    settings.copyWith(dynamicColorEnabled: value),
                  ),
                ),
              ),
            ],
          ),
        ),
        Card(
          child: Column(
            children: [
              ListTile(title: Text(l10n.language)),
              RadioGroup<LocalePreference>(
                groupValue: settings.locale,
                onChanged: (value) {
                  if (value != null) {
                    unawaited(
                      controller.updateSettings(
                        settings.copyWith(locale: value),
                      ),
                    );
                  }
                },
                child: Column(
                  children: [
                    for (final value in LocalePreference.values)
                      RadioListTile<LocalePreference>(
                        value: value,
                        title: Text(_localeLabel(context, value)),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _SettingsMonitoringRoute extends StatelessWidget {
  const _SettingsMonitoringRoute();

  @override
  Widget build(BuildContext context) => _SecondaryPageScaffold(
    parentPath: '/settings',
    title: AppLocalizations.of(context).monitoringAndNotifications,
    child: const _MonitoringSettingsPage(),
  );
}

class _MonitoringSettingsPage extends ConsumerWidget {
  const _MonitoringSettingsPage();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.watch(appControllerProvider);
    final settings = controller.settings;
    final l10n = AppLocalizations.of(context);
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          child: Column(
            children: [
              ListTile(
                title: Text(l10n.refresh),
                subtitle: Text(l10n.refreshDescription),
              ),
              RadioGroup<int>(
                groupValue: settings.refreshMinutes,
                onChanged: (value) {
                  if (value != null) {
                    unawaited(
                      controller.updateSettings(
                        settings.copyWith(refreshMinutes: value),
                      ),
                    );
                  }
                },
                child: Column(
                  children: [
                    for (final minutes in [0, 5, 15, 30])
                      RadioListTile<int>(
                        value: minutes,
                        title: Text(
                          minutes == 0
                              ? l10n.manual
                              : l10n.minutesShort(minutes),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
        Card(
          child: Column(
            children: [
              SwitchListTile(
                title: Text(l10n.showResetCredits),
                subtitle: Text(l10n.showResetCreditsDescription),
                value: settings.showResetCredits,
                onChanged: (value) => unawaited(
                  controller.updateSettings(
                    settings.copyWith(showResetCredits: value),
                  ),
                ),
              ),
              SwitchListTile(
                title: Text(l10n.notifications),
                subtitle: Text(l10n.notificationsDescription),
                value: settings.notificationsEnabled,
                onChanged: (value) => unawaited(
                  controller.updateSettings(
                    settings.copyWith(notificationsEnabled: value),
                  ),
                ),
              ),
              SwitchListTile(
                title: Text(l10n.backgroundRefresh),
                subtitle: Text(l10n.backgroundRefreshDescription),
                value: settings.backgroundRefreshEnabled,
                onChanged: (value) async {
                  if (value && !await _confirmBackgroundRefresh(context)) {
                    return;
                  }
                  await controller.updateSettings(
                    settings.copyWith(backgroundRefreshEnabled: value),
                  );
                },
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _SettingsDataRoute extends StatelessWidget {
  const _SettingsDataRoute();

  @override
  Widget build(BuildContext context) => _SecondaryPageScaffold(
    parentPath: '/settings',
    title: AppLocalizations.of(context).dataAndDiagnostics,
    child: const _DataSettingsPage(),
  );
}

class _DataSettingsPage extends ConsumerWidget {
  const _DataSettingsPage();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.watch(appControllerProvider);
    final settings = controller.settings;
    final l10n = AppLocalizations.of(context);
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          child: SwitchListTile(
            title: Text(l10n.demoMode),
            subtitle: Text(l10n.demoModeDescription),
            value: settings.demoModeEnabled,
            onChanged: (value) => unawaited(
              controller.updateSettings(
                settings.copyWith(demoModeEnabled: value),
              ),
            ),
          ),
        ),
        Card(
          child: ListTile(
            leading: const Icon(Icons.monitor_heart_outlined),
            title: Text(l10n.diagnostics),
            subtitle: Text(l10n.diagnosticsDescription),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push('/diagnostics'),
          ),
        ),
        const SizedBox(height: 8),
        Text(l10n.privacy),
      ],
    );
  }
}

class _AboutRoute extends StatelessWidget {
  const _AboutRoute();

  @override
  Widget build(BuildContext context) => _SecondaryPageScaffold(
    parentPath: '/settings',
    title: AppLocalizations.of(context).about,
    child: const _AboutPage(),
  );
}

class _AboutPage extends ConsumerStatefulWidget {
  const _AboutPage();

  @override
  ConsumerState<_AboutPage> createState() => _AboutPageState();
}

class _AboutPageState extends ConsumerState<_AboutPage> {
  int _selfDestructTaps = 0;
  bool _destroying = false;
  String? _selfDestructError;

  static final _repository = Uri.parse(
    'https://github.com/mcxiaochenn/AiUsage',
  );
  static final _issues = Uri.parse(
    'https://github.com/mcxiaochenn/AiUsage/issues',
  );
  static final _developer = Uri.parse('https://github.com/mcxiaochenn');

  @override
  void deactivate() {
    // 离开页面后，未完成解锁的危险操作不能保留。
    _resetSelfDestruct();
    super.deactivate();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return FutureBuilder<PackageInfo>(
      future: PackageInfo.fromPlatform(),
      builder: (context, snapshot) {
        final version = snapshot.data == null
            ? l10n.versionUnavailable
            : '${snapshot.data!.version} (${snapshot.data!.buildNumber})';
        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          children: [
            Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 720),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            ClipRRect(
                              borderRadius: BorderRadius.circular(18),
                              child: Image.asset(
                                'assets/branding/aiusage_icon_dark.png',
                                width: 72,
                                height: 72,
                              ),
                            ),
                            const SizedBox(height: 16),
                            Text(
                              'AiUsage',
                              style: Theme.of(context).textTheme.headlineMedium,
                            ),
                            const SizedBox(height: 6),
                            Text(l10n.aboutTagline),
                            const SizedBox(height: 20),
                            const Divider(),
                            const SizedBox(height: 12),
                            Text(l10n.appVersion(version)),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    Padding(
                      padding: const EdgeInsetsDirectional.only(start: 8),
                      child: Text(
                        l10n.developer,
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(
                              color: Theme.of(context).colorScheme.primary,
                              fontWeight: FontWeight.w700,
                            ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Card(
                      clipBehavior: Clip.antiAlias,
                      child: InkWell(
                        onTap: () => unawaited(_openExternal(_developer)),
                        child: Padding(
                          padding: const EdgeInsets.all(18),
                          child: Row(
                            children: [
                              const CircleAvatar(
                                radius: 32,
                                backgroundImage: AssetImage(
                                  'assets/branding/developer_avatar.jpg',
                                ),
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      l10n.developerName,
                                      style: Theme.of(
                                        context,
                                      ).textTheme.titleLarge,
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      l10n.developerGithub,
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodyLarge
                                          ?.copyWith(
                                            color: Theme.of(
                                              context,
                                            ).colorScheme.onSurfaceVariant,
                                          ),
                                    ),
                                  ],
                                ),
                              ),
                              const Icon(Icons.chevron_right),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Card(
                      clipBehavior: Clip.antiAlias,
                      child: Padding(
                        padding: const EdgeInsets.only(top: 18, bottom: 8),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 20,
                              ),
                              child: Text(
                                l10n.openSourceNotice,
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                            ),
                            const Divider(height: 28),
                            ListTile(
                              leading: const Icon(Icons.code_outlined),
                              title: Text(l10n.sourceCode),
                              subtitle: const Text(
                                'github.com/mcxiaochenn/AiUsage',
                              ),
                              trailing: const Icon(Icons.open_in_new),
                              onTap: () =>
                                  unawaited(_openExternal(_repository)),
                            ),
                            ListTile(
                              leading: const Icon(Icons.bug_report_outlined),
                              title: Text(l10n.feedback),
                              subtitle: const Text(
                                'github.com/mcxiaochenn/AiUsage/issues',
                              ),
                              trailing: const Icon(Icons.open_in_new),
                              onTap: () => unawaited(_openExternal(_issues)),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Padding(
                      padding: const EdgeInsetsDirectional.only(start: 8),
                      child: Text(
                        l10n.copyrightNotice,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],
                ),
              ),
            ),
            if (_selfDestructUiSupported)
              Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 720),
                  child: Card(
                    color: Theme.of(context).colorScheme.errorContainer,
                    clipBehavior: Clip.antiAlias,
                    child: ExpansionTile(
                      leading: Icon(
                        Icons.warning_amber_rounded,
                        color: Theme.of(context).colorScheme.onErrorContainer,
                      ),
                      iconColor: Theme.of(context).colorScheme.onErrorContainer,
                      collapsedIconColor: Theme.of(
                        context,
                      ).colorScheme.onErrorContainer,
                      textColor: Theme.of(context).colorScheme.onErrorContainer,
                      collapsedTextColor: Theme.of(
                        context,
                      ).colorScheme.onErrorContainer,
                      title: Text(l10n.dangerZone),
                      onExpansionChanged: (expanded) {
                        if (!expanded && mounted) {
                          setState(_resetSelfDestruct);
                        }
                      },
                      childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                      children: [
                        LayoutBuilder(
                          builder: (context, constraints) {
                            final description = Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(l10n.selfDestructDescription),
                                if (_selfDestructTaps > 0) ...[
                                  const SizedBox(height: 6),
                                  Text(
                                    l10n.selfDestructTapRemaining(
                                      10 - _selfDestructTaps,
                                    ),
                                    style: Theme.of(
                                      context,
                                    ).textTheme.bodySmall,
                                  ),
                                ],
                              ],
                            );
                            final action = FilledButton.tonalIcon(
                              onPressed: _destroying ? null : _tapSelfDestruct,
                              icon: _destroying
                                  ? const SizedBox.square(
                                      dimension: 16,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : const Icon(Icons.delete_forever),
                              label: Text(l10n.selfDestruct),
                            );
                            if (constraints.maxWidth < 440) {
                              return Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  description,
                                  const SizedBox(height: 12),
                                  Align(
                                    alignment: AlignmentDirectional.centerEnd,
                                    child: action,
                                  ),
                                ],
                              );
                            }
                            return Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(child: description),
                                const SizedBox(width: 12),
                                action,
                              ],
                            );
                          },
                        ),
                        if (_selfDestructError != null) ...[
                          const SizedBox(height: 12),
                          Align(
                            alignment: AlignmentDirectional.centerStart,
                            child: Text(
                              _selfDestructError!,
                              style: TextStyle(
                                color: Theme.of(context).colorScheme.error,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  Future<void> _openExternal(Uri uri) async {
    final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!opened && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppLocalizations.of(context).externalLinkFailed),
        ),
      );
    }
  }

  Future<void> _tapSelfDestruct() async {
    final next = _selfDestructTaps + 1;
    if (next < 10) {
      setState(() {
        _selfDestructTaps = next;
        _selfDestructError = null;
      });
      return;
    }
    setState(() => _selfDestructTaps = 0);
    final first = await _showSelfDestructWarning(context, finalStage: false);
    if (!first || !mounted) {
      if (mounted) setState(_resetSelfDestruct);
      return;
    }
    final second = await _showSelfDestructWarning(context, finalStage: true);
    if (!second || !mounted) {
      if (mounted) setState(_resetSelfDestruct);
      return;
    }
    setState(() {
      _destroying = true;
      _selfDestructError = null;
    });
    try {
      final controller = ref.read(appControllerProvider);
      await const SelfDestructService().execute(
        purgeData: controller.purgeAllUserData,
      );
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _destroying = false;
        _selfDestructError = AppLocalizations.of(context).selfDestructFailed;
      });
    }
  }

  void _resetSelfDestruct() {
    _selfDestructTaps = 0;
    _selfDestructError = null;
  }
}

Future<bool> _showSelfDestructWarning(
  BuildContext context, {
  required bool finalStage,
}) async =>
    await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => _SelfDestructWarningDialog(finalStage: finalStage),
    ) ??
    false;

class _SelfDestructWarningDialog extends StatefulWidget {
  const _SelfDestructWarningDialog({required this.finalStage});

  final bool finalStage;

  @override
  State<_SelfDestructWarningDialog> createState() =>
      _SelfDestructWarningDialogState();
}

class _SelfDestructWarningDialogState
    extends State<_SelfDestructWarningDialog> {
  int _seconds = 10;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) return;
      if (_seconds <= 1) {
        timer.cancel();
        setState(() => _seconds = 0);
      } else {
        setState(() => _seconds--);
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = Theme.of(context).colorScheme;
    return AlertDialog(
      icon: Icon(Icons.warning_amber_rounded, color: colors.error, size: 36),
      title: Text(l10n.selfDestructWarningTitle),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            widget.finalStage
                ? l10n.selfDestructFinalWarning
                : l10n.selfDestructFirstWarning,
          ),
          const SizedBox(height: 16),
          Text(
            _seconds == 0 ? l10n.selfDestruct : l10n.selfDestructWait(_seconds),
            style: TextStyle(
              color: _seconds == 0 ? colors.error : colors.onSurfaceVariant,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: Text(l10n.cancel),
        ),
        IconButton.filled(
          tooltip: l10n.selfDestruct,
          onPressed: _seconds == 0 ? () => Navigator.pop(context, true) : null,
          color: colors.onError,
          style: IconButton.styleFrom(backgroundColor: colors.error),
          icon: const Icon(Icons.delete_forever),
        ),
      ],
    );
  }
}

Future<void> _clearDiagnostics(
  BuildContext context,
  AppController controller,
) async {
  final l10n = AppLocalizations.of(context);
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(l10n.clearDiagnosticsQuestion),
      content: Text(l10n.clearDiagnosticsMessage),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: Text(l10n.cancel),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, true),
          child: Text(l10n.clearDiagnostics),
        ),
      ],
    ),
  );
  if (confirmed != true || !context.mounted) return;
  await controller.clearSyncLogs();
  if (!context.mounted) return;
  ScaffoldMessenger.of(
    context,
  ).showSnackBar(SnackBar(content: Text(l10n.diagnosticsCleared)));
}

bool get _selfDestructUiSupported =>
    defaultTargetPlatform == TargetPlatform.android ||
    defaultTargetPlatform == TargetPlatform.iOS;

Future<bool> _confirmBackgroundRefresh(BuildContext context) async {
  final l10n = AppLocalizations.of(context);
  var confirmed = false;
  return await showDialog<bool>(
        context: context,
        builder: (context) => StatefulBuilder(
          builder: (context, setState) => AlertDialog(
            title: Text(l10n.backgroundWarningTitle),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(l10n.backgroundWarningMessage),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    children: [
                      OutlinedButton(
                        onPressed: () => unawaited(
                          const SystemSettingsService()
                              .openApplicationDetails(),
                        ),
                        child: Text(l10n.appSettings),
                      ),
                      OutlinedButton(
                        onPressed: () => unawaited(
                          const SystemSettingsService().openBatterySettings(),
                        ),
                        child: Text(l10n.batterySettings),
                      ),
                    ],
                  ),
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    value: confirmed,
                    onChanged: (value) =>
                        setState(() => confirmed = value ?? false),
                    title: Text(l10n.backgroundConfirmed),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: Text(l10n.cancel),
              ),
              FilledButton(
                onPressed: confirmed
                    ? () => Navigator.pop(context, true)
                    : null,
                child: Text(l10n.enable),
              ),
            ],
          ),
        ),
      ) ??
      false;
}

class DiagnosticsPage extends ConsumerStatefulWidget {
  const DiagnosticsPage({super.key});

  @override
  ConsumerState<DiagnosticsPage> createState() => _DiagnosticsPageState();
}

class _DiagnosticsPageState extends ConsumerState<DiagnosticsPage> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(ref.read(appControllerProvider).loadSyncLogs());
    });
  }

  @override
  Widget build(BuildContext context) {
    final controller = ref.watch(appControllerProvider);
    final l10n = AppLocalizations.of(context);
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          l10n.diagnosticsPrivacy,
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 8),
        if (controller.syncLogs.isEmpty)
          _EmptyState(
            icon: Icons.receipt_long_outlined,
            title: l10n.noDiagnostics,
            message: l10n.noDiagnosticsDescription,
          )
        else
          ...controller.syncLogs.map(
            (entry) => Card(
              child: ExpansionTile(
                leading: Icon(
                  entry.errorKind == null
                      ? Icons.check_circle_outline
                      : Icons.error_outline,
                ),
                title: Text('${entry.endpoint} · ${entry.statusCode ?? '—'}'),
                subtitle: Text(
                  '${_absoluteTime(context, entry.startedAt)} · ${entry.durationMs} ms · ${_syncTriggerLabel(context, entry.trigger)}',
                ),
                childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                children: [
                  Align(
                    alignment: Alignment.centerLeft,
                    child: SelectableText(
                      entry.responseBody.isEmpty
                          ? l10n.emptyResponse
                          : entry.responseBody,
                      style: Theme.of(
                        context,
                      ).textTheme.bodySmall?.copyWith(fontFamily: 'monospace'),
                    ),
                  ),
                  if (entry.truncated)
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(l10n.responseTruncated),
                    ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

class _StateBanner extends StatelessWidget {
  const _StateBanner({
    required this.message,
    required this.state,
    this.cached = false,
    this.details,
  });

  final String message;
  final UsageState state;
  final bool cached;
  final String? details;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context);
    return Card(
      color: state == UsageState.authExpired
          ? colors.errorContainer
          : colors.surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Icon(
              state == UsageState.authExpired
                  ? Icons.lock_outline
                  : Icons.warning_amber_outlined,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(cached ? l10n.showingCachedData(message) : message),
                  if (details != null && details!.isNotEmpty)
                    ExpansionTile(
                      tilePadding: EdgeInsets.zero,
                      childrenPadding: EdgeInsets.zero,
                      title: Text(l10n.details),
                      children: [SelectableText(details!)],
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({
    required this.icon,
    required this.title,
    required this.message,
    this.action,
  });

  final IconData icon;
  final String title;
  final String message;
  final Widget? action;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(32),
    child: Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 48),
          const SizedBox(height: 12),
          Text(title, style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 6),
          Text(message, textAlign: TextAlign.center),
          if (action != null) ...[const SizedBox(height: 16), action!],
        ],
      ),
    ),
  );
}

class _DeviceLoginDialog extends ConsumerStatefulWidget {
  const _DeviceLoginDialog();

  @override
  ConsumerState<_DeviceLoginDialog> createState() => _DeviceLoginDialogState();
}

class _DeviceLoginDialogState extends ConsumerState<_DeviceLoginDialog>
    with WidgetsBindingObserver {
  final _alias = TextEditingController();
  DeviceCodeLoginStart? _start;
  Timer? _pollTimer;
  Timer? _countdownTimer;
  DateTime? _expiresAt;
  String? _error;
  bool _finished = false;
  bool _polling = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_begin());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(_poll());
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _countdownTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    final loginId = _start?.loginId;
    if (!_finished && loginId != null) {
      unawaited(ref.read(appControllerProvider).cancelDeviceLogin(loginId));
    }
    _alias.dispose();
    super.dispose();
  }

  Future<void> _begin() async {
    final previousLoginId = _start?.loginId;
    if (previousLoginId != null && !_finished) {
      await ref.read(appControllerProvider).cancelDeviceLogin(previousLoginId);
      if (!mounted) return;
    }
    _pollTimer?.cancel();
    _countdownTimer?.cancel();
    setState(() {
      _start = null;
      _error = null;
      _finished = false;
    });
    try {
      final start = await ref.read(appControllerProvider).beginAddAccount();
      if (!mounted) return;
      setState(() {
        _start = start;
        _expiresAt = DateTime.now().add(const Duration(minutes: 15));
      });
      _pollTimer = Timer.periodic(
        Duration(seconds: start.pollIntervalSeconds),
        (_) => unawaited(_poll()),
      );
      _countdownTimer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (!mounted) return;
        final expiresAt = _expiresAt;
        if (expiresAt != null && DateTime.now().isAfter(expiresAt)) {
          _pollTimer?.cancel();
          _countdownTimer?.cancel();
          setState(() => _error = 'device_login.expired');
          unawaited(
            ref.read(appControllerProvider).cancelDeviceLogin(start.loginId),
          );
        } else {
          setState(() {});
        }
      });
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
    }
  }

  Future<void> _poll() async {
    final start = _start;
    if (start == null || _finished || _polling) return;
    _polling = true;
    try {
      final result = await ref
          .read(appControllerProvider)
          .pollDeviceLogin(start.loginId);
      final complete = result.completed;
      if (complete == null) return;
      _finished = true;
      _pollTimer?.cancel();
      _countdownTimer?.cancel();
      await ref
          .read(appControllerProvider)
          .acceptLogin(
            complete,
            credentialSource: CredentialSource.deviceCode,
            displayName: _alias.text,
          );
      if (mounted) Navigator.pop(context);
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
    } finally {
      _polling = false;
    }
  }

  Future<void> _copyCode() async {
    final code = _start?.userCode;
    if (code == null) return;
    await Clipboard.setData(ClipboardData(text: code));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(AppLocalizations.of(context).codeCopied)),
    );
  }

  Future<void> _openBrowser() async {
    final url = _start?.verificationUrl;
    if (url == null) return;
    final opened = await launchUrl(
      Uri.parse(url),
      mode: LaunchMode.externalApplication,
    );
    if (!opened && mounted) {
      setState(() => _error = 'device_login.browser_open_failed');
    }
  }

  String get _remainingLoginTime {
    final seconds = _expiresAt?.difference(DateTime.now()).inSeconds ?? 0;
    if (seconds <= 0) return '0:00';
    final minutes = seconds ~/ 60;
    return '$minutes:${(seconds % 60).toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return AlertDialog(
      title: Text(l10n.signInToCodex),
      content: SizedBox(
        width: 420,
        child: _error != null && _start == null
            ? Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(l10n.signInFailed),
                  const SizedBox(height: 8),
                  SelectableText(_loginErrorMessage(context, _error!)),
                ],
              )
            : _start == null
            ? const SizedBox(
                height: 96,
                child: Center(child: CircularProgressIndicator()),
              )
            : Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    controller: _alias,
                    decoration: InputDecoration(
                      labelText: l10n.accountAliasOptional,
                    ),
                    textInputAction: TextInputAction.done,
                  ),
                  const SizedBox(height: 12),
                  Text(l10n.completeBrowserSignIn),
                  const SizedBox(height: 16),
                  SelectableText(
                    _start!.userCode,
                    style: Theme.of(context).textTheme.headlineMedium,
                  ),
                  const SizedBox(height: 8),
                  Text(l10n.codeExpiresIn(_remainingLoginTime)),
                  const SizedBox(height: 8),
                  Text(l10n.browserPasteHint),
                  if (_error != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      '${l10n.lastCheckFailed} ${_loginErrorMessage(context, _error!)}',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ],
                  const SizedBox(height: 12),
                  const LinearProgressIndicator(),
                ],
              ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l10n.cancel),
        ),
        if (_start != null)
          TextButton.icon(
            onPressed: _copyCode,
            icon: const Icon(Icons.copy),
            label: Text(l10n.copyCode),
          ),
        if (_start != null)
          TextButton.icon(
            onPressed: _openBrowser,
            icon: const Icon(Icons.open_in_new),
            label: Text(l10n.openBrowser),
          ),
        if (_error != null)
          TextButton(onPressed: _begin, child: Text(l10n.newCode)),
      ],
    );
  }
}

Future<void> _showDeviceLogin(BuildContext context) => showDialog<void>(
  context: context,
  barrierDismissible: false,
  builder: (context) => const _DeviceLoginDialog(),
);

Future<void> _showAddAccount(BuildContext context) async {
  final mobile = MediaQuery.sizeOf(context).width < 600;
  final provider = mobile
      ? await showModalBottomSheet<String>(
          context: context,
          showDragHandle: true,
          builder: (context) => const _ProviderChoices(),
        )
      : await showDialog<String>(
          context: context,
          builder: (context) => SimpleDialog(
            title: Text(AppLocalizations.of(context).chooseProvider),
            children: const [_ProviderChoices()],
          ),
        );
  if (!context.mounted || provider == null) return;
  if (provider == 'deepseek') {
    await showDialog<void>(
      context: context,
      builder: (context) => const _DeepSeekLoginDialog(),
    );
    return;
  }
  if (provider == 'mimo') {
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) => const _MimoLoginDialog(),
    );
    return;
  }
  final method = mobile
      ? await showModalBottomSheet<String>(
          context: context,
          showDragHandle: true,
          builder: (context) => const _LoginMethodChoices(),
        )
      : await showDialog<String>(
          context: context,
          builder: (context) => SimpleDialog(
            title: Text(AppLocalizations.of(context).providerCodex),
            children: const [_LoginMethodChoices()],
          ),
        );
  if (!context.mounted || method == null) return;
  if (method == 'device') {
    await _showDeviceLogin(context);
  } else {
    await _importAuthJson(context);
  }
}

class _ProviderChoices extends StatelessWidget {
  const _ProviderChoices();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final provider in ProviderKind.values)
          ListTile(
            leading: _ProviderAvatar(provider: provider, radius: 18),
            title: Text(_providerLabel(context, provider)),
            subtitle: provider == ProviderKind.mimo
                ? Text(l10n.mimoInternalApiWarning)
                : null,
            onTap: () => Navigator.pop(context, provider.name.toLowerCase()),
          ),
        const SizedBox(height: 8),
      ],
    );
  }
}

class _DeepSeekLoginDialog extends StatefulWidget {
  const _DeepSeekLoginDialog();

  @override
  State<_DeepSeekLoginDialog> createState() => _DeepSeekLoginDialogState();
}

class _DeepSeekLoginDialogState extends State<_DeepSeekLoginDialog> {
  final _key = TextEditingController();
  final _alias = TextEditingController();
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _key.dispose();
    _alias.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return AlertDialog(
      title: Text(l10n.addDeepSeek),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _key,
              obscureText: true,
              enableSuggestions: false,
              autocorrect: false,
              decoration: InputDecoration(labelText: l10n.deepSeekApiKey),
            ),
            TextField(
              controller: _alias,
              decoration: InputDecoration(labelText: l10n.accountAliasOptional),
            ),
            const SizedBox(height: 12),
            Text(l10n.deepSeekKeyHint),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context),
          child: Text(l10n.cancel),
        ),
        FilledButton(
          onPressed: _saving ? null : _submit,
          child: _saving
              ? const SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text(l10n.saveAndVerify),
        ),
      ],
    );
  }

  Future<void> _submit() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await ProviderScope.containerOf(context)
          .read(appControllerProvider)
          .addDeepSeekAccount(apiKey: _key.text, alias: _alias.text);
      if (mounted) Navigator.pop(context);
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}

class _MimoLoginDialog extends StatefulWidget {
  const _MimoLoginDialog();

  @override
  State<_MimoLoginDialog> createState() => _MimoLoginDialogState();
}

class _MimoLoginDialogState extends State<_MimoLoginDialog> {
  final _username = TextEditingController();
  final _password = TextEditingController();
  final _alias = TextEditingController();
  bool _obscure = true;
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _username.dispose();
    _password.dispose();
    _alias.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return AlertDialog(
      title: Text(l10n.addMimo),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: _alias,
                maxLength: 48,
                decoration: InputDecoration(
                  labelText: l10n.accountAliasOptional,
                ),
              ),
              TextField(
                controller: _username,
                keyboardType: TextInputType.emailAddress,
                decoration: InputDecoration(labelText: l10n.mimoUsername),
              ),
              TextField(
                controller: _password,
                obscureText: _obscure,
                enableSuggestions: false,
                autocorrect: false,
                decoration: InputDecoration(
                  labelText: l10n.mimoPassword,
                  suffixIcon: IconButton(
                    onPressed: () => setState(() => _obscure = !_obscure),
                    icon: Icon(
                      _obscure ? Icons.visibility : Icons.visibility_off,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Text(l10n.mimoSecurityHint),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    _error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context),
          child: Text(l10n.cancel),
        ),
        FilledButton(
          onPressed: _saving ? null : _submit,
          child: _saving
              ? const SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text(l10n.saveAndVerify),
        ),
      ],
    );
  }

  Future<void> _submit() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final username = _username.text;
      final alias = _alias.text;
      final result = await ProviderScope.containerOf(context)
          .read(appControllerProvider)
          .beginMimoAccount(
            username: username,
            password: _password.text,
            displayName: alias,
          );
      _password.clear();
      if (!mounted) return;
      Navigator.pop(context);
      if (result.challengeUrl != null) {
        await context.push(
          '/mimo-login',
          extra: _MimoChallengeArgs(
            challengeUrl: result.challengeUrl!,
            displayName: alias,
            accountHint: username,
          ),
        );
      }
    } catch (error) {
      _password.clear();
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}

class _LoginMethodChoices extends StatelessWidget {
  const _LoginMethodChoices();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        ListTile(
          leading: const Icon(Icons.open_in_browser),
          title: Text(l10n.signInWithBrowser),
          subtitle: Text(l10n.deviceCodeRecommended),
          onTap: () => Navigator.pop(context, 'device'),
        ),
        ListTile(
          leading: const Icon(Icons.file_open_outlined),
          title: Text(l10n.importAuthJson),
          subtitle: Text(l10n.authJsonAdvanced),
          onTap: () => Navigator.pop(context, 'file'),
        ),
        const SizedBox(height: 8),
      ],
    );
  }
}

Future<void> _importAuthJson(BuildContext context) => showDialog<void>(
  context: context,
  barrierDismissible: false,
  builder: (context) => const _AuthJsonImportDialog(),
);

class _AuthJsonImportDialog extends ConsumerStatefulWidget {
  const _AuthJsonImportDialog();

  @override
  ConsumerState<_AuthJsonImportDialog> createState() =>
      _AuthJsonImportDialogState();
}

class _AuthJsonImportDialogState extends ConsumerState<_AuthJsonImportDialog> {
  final _alias = TextEditingController();
  Uint8List? _bytes;
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _wipeBytes();
    _alias.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return AlertDialog(
      title: Text(l10n.importAuthJson),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _alias,
              maxLength: 48,
              decoration: InputDecoration(labelText: l10n.accountAliasOptional),
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                Expanded(
                  child: Text(
                    '${l10n.credentialImport}: ${_bytes == null ? l10n.credentialNotImported : l10n.credentialImported}',
                  ),
                ),
                const SizedBox(width: 12),
                OutlinedButton.icon(
                  onPressed: _saving ? null : _chooseFile,
                  icon: const Icon(Icons.file_open_outlined),
                  label: Text(l10n.importCredential),
                ),
              ],
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context),
          child: Text(l10n.cancel),
        ),
        FilledButton(
          onPressed: _saving || _bytes == null ? null : _save,
          child: _saving
              ? const SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text(l10n.save),
        ),
      ],
    );
  }

  Future<void> _chooseFile() async {
    final l10n = AppLocalizations.of(context);
    final typeGroup = XTypeGroup(
      label: l10n.authFileLabel,
      extensions: const ['json'],
      mimeTypes: const ['application/json'],
      uniformTypeIdentifiers: const ['public.json'],
    );
    try {
      final file = await openFile(acceptedTypeGroups: [typeGroup]);
      if (file == null || !mounted) return;
      if (await file.length() > 1024 * 1024) {
        throw const FormatException('auth_import.file_too_large');
      }
      final bytes = await file.readAsBytes();
      if (!mounted) {
        bytes.fillRange(0, bytes.length, 0);
        return;
      }
      _wipeBytes();
      setState(() {
        _bytes = bytes;
        _error = null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = _authImportErrorMessage(context, error));
    }
  }

  Future<void> _save() async {
    final bytes = _bytes;
    if (bytes == null) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await ref
          .read(appControllerProvider)
          .importAccount(bytes, displayName: _alias.text);
      if (!mounted) return;
      final message = AppLocalizations.of(context).accountImported;
      final messenger = ScaffoldMessenger.of(context);
      _wipeBytes();
      Navigator.pop(context);
      messenger.showSnackBar(SnackBar(content: Text(message)));
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = _authImportErrorMessage(context, error));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _wipeBytes() {
    final bytes = _bytes;
    if (bytes != null) bytes.fillRange(0, bytes.length, 0);
    _bytes = null;
  }
}

Future<String?> _showAccountNameDialog(
  BuildContext context, {
  String? initialValue,
}) async {
  final controller = TextEditingController(text: initialValue ?? '');
  try {
    return await showDialog<String>(
      context: context,
      builder: (context) {
        final l10n = AppLocalizations.of(context);
        return AlertDialog(
          title: Text(l10n.customAccountName),
          content: TextField(
            controller: controller,
            autofocus: true,
            maxLength: 48,
            decoration: InputDecoration(labelText: l10n.accountAliasOptional),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(l10n.cancel),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, controller.text),
              child: Text(l10n.save),
            ),
          ],
        );
      },
    );
  } finally {
    controller.dispose();
  }
}

String _remainingTime(BuildContext context, int resetAt) {
  final l10n = AppLocalizations.of(context);
  final seconds = resetAt - DateTime.now().millisecondsSinceEpoch ~/ 1000;
  if (seconds <= 0) {
    return l10n.now;
  }
  final duration = Duration(seconds: seconds);
  if (duration.inDays > 0) {
    return l10n.daysHours(duration.inDays, duration.inHours.remainder(24));
  }
  if (duration.inHours > 0) {
    return l10n.hoursMinutes(
      duration.inHours,
      duration.inMinutes.remainder(60),
    );
  }
  return l10n.minutesOnly(duration.inMinutes);
}

String _relativeTime(BuildContext context, int timestamp) {
  final l10n = AppLocalizations.of(context);
  final seconds = DateTime.now().millisecondsSinceEpoch ~/ 1000 - timestamp;
  if (seconds < 60) return l10n.justNow;
  if (seconds < 3600) return l10n.minutesAgo(seconds ~/ 60);
  if (seconds < 86400) return l10n.hoursAgo(seconds ~/ 3600);
  return l10n.daysAgo(seconds ~/ 86400);
}

String _absoluteTime(BuildContext context, int timestamp) {
  final l10n = AppLocalizations.of(context);
  if (timestamp <= 0) return l10n.unavailable;
  final date = DateTime.fromMillisecondsSinceEpoch(timestamp * 1000).toLocal();
  return DateFormat.yMd(
    Localizations.localeOf(context).toLanguageTag(),
  ).add_Hm().format(date);
}

String _stateMessage(BuildContext context, UsageState state) => switch (state) {
  UsageState.stale => AppLocalizations.of(context).stateStale,
  UsageState.authExpired => AppLocalizations.of(context).stateAuthExpired,
  UsageState.offline => AppLocalizations.of(context).stateOffline,
  UsageState.rateLimited => AppLocalizations.of(context).stateRateLimited,
  UsageState.serverError => AppLocalizations.of(context).stateServerError,
  UsageState.parseError => AppLocalizations.of(context).stateParseError,
  UsageState.fresh => '',
};

String _loginStateLabel(BuildContext context, LoginState state) =>
    switch (state) {
      LoginState.signedIn => AppLocalizations.of(context).signedIn,
      LoginState.signedOut => AppLocalizations.of(context).signedOut,
      LoginState.expired => AppLocalizations.of(context).expired,
    };

String _credentialSourceLabel(
  BuildContext context,
  StoredAccount account, {
  required bool demo,
}) {
  final l10n = AppLocalizations.of(context);
  if (demo) return l10n.demoData;
  return switch (account.credentialSource) {
    CredentialSource.deviceCode => l10n.credentialSourceDeviceCode,
    CredentialSource.authJson => l10n.credentialSourceAuthJson,
    CredentialSource.apiKey => l10n.credentialSourceApiKey,
    CredentialSource.xiaomiPassword => l10n.credentialSourceXiaomiPassword,
    CredentialSource.xiaomiWeb => l10n.credentialSourceXiaomiWeb,
    CredentialSource.unknown => l10n.credentialSourceUnknown,
  };
}

String _providerLabel(BuildContext context, ProviderKind provider) =>
    switch (provider) {
      ProviderKind.codex => AppLocalizations.of(context).providerCodex,
      ProviderKind.deepSeek => AppLocalizations.of(context).providerDeepSeek,
      ProviderKind.mimo => AppLocalizations.of(context).providerMimo,
    };

class _ProviderAvatar extends StatelessWidget {
  const _ProviderAvatar({
    required this.provider,
    this.account,
    this.radius = 20,
    this.backgroundColor,
    this.foregroundColor,
  });

  final ProviderKind provider;
  final StoredAccount? account;
  final double radius;
  final Color? backgroundColor;
  final Color? foregroundColor;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final background =
        backgroundColor ??
        switch (provider) {
          ProviderKind.codex || ProviderKind.deepSeek => Colors.white,
          ProviderKind.mimo => const Color(0xFFFF6900),
        };
    final foreground =
        foregroundColor ??
        switch (provider) {
          ProviderKind.codex => colors.onPrimaryContainer,
          ProviderKind.deepSeek || ProviderKind.mimo => Colors.white,
        };
    final avatarUrl = provider == ProviderKind.codex
        ? account?.avatarUrl
        : null;
    final fallback = Padding(
      padding: EdgeInsets.all(radius * 0.32),
      child: Image.asset(_providerAsset(provider), fit: BoxFit.contain),
    );
    return CircleAvatar(
      radius: radius,
      backgroundColor: background,
      foregroundColor: foreground,
      foregroundImage: avatarUrl == null ? null : NetworkImage(avatarUrl),
      onForegroundImageError: avatarUrl == null ? null : (_, _) {},
      child: fallback,
    );
  }
}

String _providerAsset(ProviderKind provider) => switch (provider) {
  ProviderKind.codex => 'assets/providers/openai.png',
  ProviderKind.deepSeek => 'assets/providers/deepseek.png',
  ProviderKind.mimo => 'assets/providers/mimo.png',
};

String _accountDisplayName(BuildContext context, StoredAccount account) =>
    account.displayName ??
    account.email ??
    account.mimoAccountHint ??
    _providerLabel(context, account.provider);

String _accountIdentifierLabel(BuildContext context, StoredAccount account) {
  final l10n = AppLocalizations.of(context);
  return switch (account.provider) {
    ProviderKind.codex => l10n.email,
    ProviderKind.deepSeek => l10n.apiKeyFingerprint,
    ProviderKind.mimo => l10n.mimoAccount,
  };
}

String _accountIdentifierValue(BuildContext context, StoredAccount account) {
  final l10n = AppLocalizations.of(context);
  return switch (account.provider) {
    ProviderKind.codex => account.email ?? l10n.unavailable,
    ProviderKind.deepSeek => _maskedApiKey(account.apiKey) ?? l10n.unavailable,
    ProviderKind.mimo =>
      account.mimoAccountHint ??
          account.mimoCredential?.userId ??
          l10n.unavailable,
  };
}

String? _maskedApiKey(String? value) {
  final key = value?.trim();
  if (key == null || key.isEmpty) return null;
  if (key.length <= 10) return '${key.substring(0, 2)}…';
  return '${key.substring(0, 6)}…${key.substring(key.length - 4)}';
}

String _providerAccountLabel(BuildContext context, AccountInfo account) =>
    account.email ?? _providerLabel(context, account.provider);

String _balanceLabel(BuildContext context, String id) {
  final l10n = AppLocalizations.of(context);
  if (id.endsWith(':total')) return l10n.totalBalance;
  if (id.endsWith(':cash')) return l10n.cashBalance;
  if (id.endsWith(':granted')) return l10n.grantedBalance;
  if (id.endsWith(':topped-up')) return l10n.toppedUpBalance;
  if (id.endsWith(':gift')) return l10n.giftBalance;
  if (id.endsWith(':frozen')) return l10n.frozenBalance;
  if (id.endsWith(':remaining-overdraft')) return l10n.remainingOverdraftLimit;
  if (id.endsWith(':overdraft')) return l10n.overdraftLimit;
  return l10n.totalBalance;
}

String _themeLabel(BuildContext context, ThemePreference value) =>
    switch (value) {
      ThemePreference.system => AppLocalizations.of(context).system,
      ThemePreference.light => AppLocalizations.of(context).light,
      ThemePreference.dark => AppLocalizations.of(context).dark,
    };

String _localeLabel(BuildContext context, LocalePreference value) =>
    switch (value) {
      LocalePreference.system => AppLocalizations.of(context).followSystem,
      LocalePreference.english => AppLocalizations.of(context).english,
      LocalePreference.simplifiedChinese => AppLocalizations.of(
        context,
      ).simplifiedChinese,
    };

String _windowTitle(BuildContext context, QuotaWindow window) {
  if (!window.id.startsWith('codex:')) return window.title;
  final l10n = AppLocalizations.of(context);
  final seconds = window.windowSeconds;
  if (seconds > 0 && seconds % 604800 == 0) {
    return l10n.weekLimit(seconds ~/ 604800);
  }
  if (seconds > 0 && seconds % 86400 == 0) {
    return l10n.dayLimit(seconds ~/ 86400);
  }
  if (seconds > 0 && seconds % 3600 == 0) {
    return l10n.hourLimit(seconds ~/ 3600);
  }
  if (seconds > 0 && seconds % 60 == 0) {
    return l10n.minuteLimit(seconds ~/ 60);
  }
  return l10n.customLimit;
}

String _loginErrorMessage(BuildContext context, String error) {
  final l10n = AppLocalizations.of(context);
  return switch (error) {
    'device_login.expired' => l10n.codeExpired,
    'device_login.browser_open_failed' => l10n.browserOpenFailed,
    _ => error,
  };
}

String _authImportErrorMessage(BuildContext context, Object error) {
  final l10n = AppLocalizations.of(context);
  final value = error.toString();
  if (value.contains('auth_import.file_too_large')) {
    return l10n.authImportTooLarge;
  }
  if (value.contains('auth_import.api_key_only')) {
    return l10n.authImportApiKeyOnly;
  }
  if (value.contains('auth_import.invalid_json') ||
      value.contains('omitted required credentials') ||
      value.contains('OAuth response could not be decoded')) {
    return l10n.authImportInvalid;
  }
  return l10n.authImportFailed;
}
