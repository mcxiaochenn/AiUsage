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
import 'package:url_launcher/url_launcher.dart';

import 'app_controller.dart';
import '../l10n/app_localizations.dart';
import 'rust/models.dart';
import 'services/secure_account_vault.dart';
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
            _MimoChallengePage(challengeUrl: state.extra! as String),
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
            : _AccountDropdown(controller: controller, expanded: true),
        actions: [
          if (desktop && controller.accounts.isNotEmpty)
            SizedBox(
              width: 260,
              child: _AccountDropdown(controller: controller),
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
          tooltip: l10n.refresh,
          onPressed: () => unawaited(controller.loadSyncLogs()),
          icon: const Icon(Icons.refresh),
        ),
      ],
      child: const DiagnosticsPage(),
    );
  }
}

class _MimoChallengePage extends ConsumerStatefulWidget {
  const _MimoChallengePage({required this.challengeUrl});

  final String challengeUrl;

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
              initialUrlRequest: URLRequest(url: WebUri(widget.challengeUrl)),
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

class _AccountDropdown extends StatelessWidget {
  const _AccountDropdown({required this.controller, this.expanded = false});

  final AppController controller;
  final bool expanded;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return DropdownButtonHideUnderline(
      child: DropdownButton<String>(
        isExpanded: expanded,
        value: controller.selectedAccount?.identityHash,
        hint: Text(l10n.account),
        items: controller.accounts
            .map(
              (account) => DropdownMenuItem(
                value: account.identityHash,
                child: Row(
                  children: [
                    Icon(_providerIcon(account.provider), size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _accountDisplayName(context, account),
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
          if (value != null) unawaited(controller.selectAccount(value));
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
            _AccountHeader(snapshot: snapshot),
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
  const _AccountHeader({required this.snapshot});

  final UsageSnapshot snapshot;

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
            CircleAvatar(
              backgroundColor: colors.primary,
              foregroundColor: colors.onPrimary,
              child: Icon(_providerIcon(snapshot.account.provider)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _providerAccountLabel(context, snapshot.account),
                    style: Theme.of(context).textTheme.titleMedium,
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
        Text(l10n.accounts, style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 8),
        if (controller.accounts.isEmpty)
          _EmptyState(
            icon: Icons.person_off_outlined,
            title: l10n.noAccounts,
            message: l10n.noAccountsMessage,
          ),
        ...controller.accounts.map(
          (account) => Card(
            child: ListTile(
              leading: CircleAvatar(
                child: Icon(_providerIcon(account.provider)),
              ),
              title: Text(_accountDisplayName(context, account)),
              subtitle: Text(
                '${_providerLabel(context, account.provider)} · ${account.plan ?? l10n.unknownPlan} · ${_loginStateLabel(context, account.loginState)}\n'
                '${l10n.lastSuccessfulRefresh(account.lastSuccessfulRefresh == null ? l10n.never : _absoluteTime(context, account.lastSuccessfulRefresh!))}\n'
                '${l10n.credentialSource}: ${_credentialSourceLabel(context, account, demo: controller.demoMode)}',
              ),
              isThreeLine: true,
              selected:
                  controller.selectedAccount?.identityHash ==
                  account.identityHash,
              onTap: () =>
                  unawaited(controller.selectAccount(account.identityHash)),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    tooltip: l10n.accountDetails,
                    onPressed: () async {
                      await controller.selectAccount(account.identityHash);
                      if (context.mounted) context.push('/account-details');
                    },
                    icon: const Icon(Icons.info_outline),
                  ),
                  if (!controller.demoMode)
                    PopupMenuButton<String>(
                      onSelected: (value) =>
                          _accountAction(context, controller, account, value),
                      itemBuilder: (context) => [
                        PopupMenuItem(
                          value: 'refresh',
                          child: Text(l10n.refresh),
                        ),
                        PopupMenuItem(
                          value: 'logout',
                          child: Text(l10n.logout),
                        ),
                        PopupMenuItem(
                          value: 'remove',
                          child: Text(l10n.removeAccount),
                        ),
                      ],
                    ),
                ],
              ),
            ),
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
      case 'refresh':
        await controller.selectAccount(account.identityHash);
      case 'logout':
        await controller.selectAccount(account.identityHash);
        await controller.logoutSelected();
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
              _DetailTile(
                label: l10n.provider,
                value: _providerLabel(context, account.provider),
              ),
              _DetailTile(
                label: l10n.email,
                value: account.email ?? account.displayName ?? l10n.unavailable,
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

class SettingsPage extends ConsumerWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.watch(appControllerProvider);
    final settings = controller.settings;
    final l10n = AppLocalizations.of(context);
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(l10n.settings, style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 8),
        Card(
          child: Column(
            children: [
              ListTile(title: Text(l10n.theme)),
              RadioGroup<ThemePreference>(
                groupValue: settings.theme,
                onChanged: (selection) {
                  if (selection != null) {
                    unawaited(
                      controller.updateSettings(
                        settings.copyWith(theme: selection),
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
                onChanged: (selection) {
                  if (selection != null) {
                    unawaited(
                      controller.updateSettings(
                        settings.copyWith(locale: selection),
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
        Card(
          child: Column(
            children: [
              ListTile(
                title: Text(l10n.refresh),
                subtitle: Text(l10n.refreshDescription),
              ),
              RadioGroup<int>(
                groupValue: settings.refreshMinutes,
                onChanged: (selection) {
                  if (selection != null) {
                    unawaited(
                      controller.updateSettings(
                        settings.copyWith(refreshMinutes: selection),
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
                title: Text(l10n.demoMode),
                subtitle: Text(l10n.demoModeDescription),
                value: settings.demoModeEnabled,
                onChanged: (value) => unawaited(
                  controller.updateSettings(
                    settings.copyWith(demoModeEnabled: value),
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
              ListTile(
                leading: const Icon(Icons.monitor_heart_outlined),
                title: Text(l10n.diagnostics),
                subtitle: Text(l10n.diagnosticsDescription),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => context.push('/diagnostics'),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Text(l10n.privacy),
      ],
    );
  }

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
      unawaited(_openBrowser());
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
          .acceptLogin(complete, credentialSource: CredentialSource.deviceCode);
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
            leading: Icon(_providerIcon(provider)),
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
  bool _obscure = true;
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _username.dispose();
    _password.dispose();
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
      final result = await ProviderScope.containerOf(context)
          .read(appControllerProvider)
          .beginMimoAccount(username: _username.text, password: _password.text);
      _password.clear();
      if (!mounted) return;
      Navigator.pop(context);
      if (result.challengeUrl != null) {
        await context.push('/mimo-login', extra: result.challengeUrl!);
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

Future<void> _importAuthJson(BuildContext context) async {
  try {
    final l10n = AppLocalizations.of(context);
    final typeGroup = XTypeGroup(
      label: l10n.authFileLabel,
      extensions: const ['json'],
      mimeTypes: const ['application/json'],
      uniformTypeIdentifiers: const ['public.json'],
    );
    final file = await openFile(acceptedTypeGroups: [typeGroup]);
    if (file == null || !context.mounted) return;
    if (await file.length() > 1024 * 1024) {
      throw const FormatException('auth_import.file_too_large');
    }
    final bytes = await file.readAsBytes();
    if (!context.mounted) return;
    await ProviderScope.containerOf(
      context,
    ).read(appControllerProvider).importAccount(bytes);
    if (!context.mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(l10n.accountImported)));
  } catch (error) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(_authImportErrorMessage(context, error))),
    );
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

IconData _providerIcon(ProviderKind provider) => switch (provider) {
  ProviderKind.codex => Icons.auto_awesome,
  ProviderKind.deepSeek => Icons.water_drop_outlined,
  ProviderKind.mimo => Icons.memory_outlined,
};

String _accountDisplayName(BuildContext context, StoredAccount account) =>
    account.displayName ??
    account.email ??
    _providerLabel(context, account.provider);

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
  if (id.endsWith(':overdraft') || id.endsWith(':remaining-overdraft')) {
    return l10n.overdraftLimit;
  }
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
