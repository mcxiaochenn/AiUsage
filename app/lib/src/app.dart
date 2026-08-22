import 'dart:async';

import 'package:fl_chart/fl_chart.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
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

class _MonitorRouterState extends ConsumerState<_MonitorRouter> {
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
    ],
  );

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(appControllerProvider).settings;
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
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo),
        useMaterial3: true,
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.indigo,
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      routerConfig: _router,
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

class _AppShellState extends ConsumerState<_AppShell>
    with WidgetsBindingObserver {
  static const _routes = ['/', '/accounts', '/history', '/settings'];
  static const _icons = [
    Icons.space_dashboard_outlined,
    Icons.manage_accounts_outlined,
    Icons.show_chart_outlined,
    Icons.settings_outlined,
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(ref.read(appControllerProvider).refresh());
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = ref.watch(appControllerProvider);
    final desktop = MediaQuery.sizeOf(context).width >= 820;
    final l10n = AppLocalizations.of(context);
    final labels = [l10n.dashboard, l10n.accounts, l10n.history, l10n.settings];
    final content = Scaffold(
      appBar: AppBar(
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
    if (!desktop) return content;
    return Scaffold(
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
                child: Text(
                  account.email ?? l10n.unknownAccount,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
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
        title: l10n.addCodexAccount,
        message: l10n.addCodexAccountMessage,
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
            if (snapshot.windows.isEmpty)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Text(l10n.noQuotaWindows),
                ),
              ),
            ...snapshot.windows.map(
              (window) => _QuotaWindowCard(window: window),
            ),
            if (controller.settings.showResetCredits &&
                snapshot.resetCreditsAvailable != null)
              Card(
                child: ListTile(
                  leading: const Icon(Icons.restart_alt),
                  title: Text(l10n.resetCredits),
                  subtitle: Text(l10n.resetCreditsReadOnly),
                  trailing: Text(
                    l10n.availableCount(snapshot.resetCreditsAvailable!),
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
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
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            CircleAvatar(
              child: Text(
                (snapshot.account.email ?? '?').characters.first.toUpperCase(),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    snapshot.account.email ?? l10n.unknownAccount,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  Text(snapshot.account.plan ?? l10n.unknownPlan),
                ],
              ),
            ),
            const Icon(Icons.verified_user_outlined),
          ],
        ),
      ),
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
        margin: const EdgeInsets.only(bottom: 12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      _windowTitle(context, window),
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                  Text(l10n.usedPercent(used.round())),
                ],
              ),
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
                child: Text(
                  (account.email ?? '?').characters.first.toUpperCase(),
                ),
              ),
              title: Text(account.email ?? l10n.unknownAccount),
              subtitle: Text(
                '${account.plan ?? l10n.unknownPlan} · ${_loginStateLabel(context, account.loginState)}\n'
                '${l10n.lastSuccessfulRefresh(account.lastSuccessfulRefresh == null ? l10n.never : _absoluteTime(context, account.lastSuccessfulRefresh!))}\n'
                '${l10n.credentialStatus(account.credential == null ? l10n.credentialCleared : l10n.credentialAvailable)}',
              ),
              isThreeLine: true,
              selected:
                  controller.selectedAccount?.identityHash ==
                  account.identityHash,
              onTap: () =>
                  unawaited(controller.selectAccount(account.identityHash)),
              trailing: PopupMenuButton<String>(
                onSelected: (value) =>
                    _accountAction(context, controller, account, value),
                itemBuilder: (context) => [
                  PopupMenuItem(value: 'refresh', child: Text(l10n.refresh)),
                  PopupMenuItem(value: 'logout', child: Text(l10n.logout)),
                  PopupMenuItem(
                    value: 'remove',
                    child: Text(l10n.removeAccount),
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

class HistoryPage extends ConsumerStatefulWidget {
  const HistoryPage({super.key});

  @override
  ConsumerState<HistoryPage> createState() => _HistoryPageState();
}

class _HistoryPageState extends ConsumerState<HistoryPage> {
  Duration _period = const Duration(hours: 24);

  @override
  Widget build(BuildContext context) {
    final controller = ref.watch(appControllerProvider);
    final snapshot = controller.usage?.snapshot;
    final l10n = AppLocalizations.of(context);
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(l10n.history, style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 8),
        SegmentedButton<Duration>(
          segments: [
            ButtonSegment(
              value: const Duration(hours: 24),
              label: Text(l10n.hours24),
            ),
            ButtonSegment(
              value: const Duration(days: 7),
              label: Text(l10n.days7),
            ),
          ],
          selected: {_period},
          onSelectionChanged: (selection) =>
              setState(() => _period = selection.first),
        ),
        const SizedBox(height: 20),
        FutureBuilder<List<HistoryPoint>>(
          key: ValueKey(
            '${controller.selectedAccount?.identityHash}:$_period:${snapshot?.fetchedAt}',
          ),
          future: controller.history(_period),
          builder: (context, result) {
            if (result.connectionState != ConnectionState.done) {
              return const SizedBox(
                height: 260,
                child: Center(child: CircularProgressIndicator()),
              );
            }
            final points = result.data ?? const <HistoryPoint>[];
            if (points.isEmpty) {
              return _EmptyState(
                icon: Icons.query_stats_outlined,
                title: l10n.noHistory,
                message: l10n.noHistoryMessage,
              );
            }
            return _HistoryChart(points: points, snapshot: snapshot);
          },
        ),
      ],
    );
  }
}

class _HistoryChart extends StatelessWidget {
  const _HistoryChart({required this.points, required this.snapshot});

  final List<HistoryPoint> points;
  final UsageSnapshot? snapshot;

  @override
  Widget build(BuildContext context) {
    final grouped = <String, List<HistoryPoint>>{};
    for (final point in points) {
      (grouped[point.windowId] ??= []).add(point);
    }
    final earliest = points
        .map((point) => point.timestamp)
        .reduce((a, b) => a < b ? a : b);
    const colors = [
      Colors.indigo,
      Colors.teal,
      Colors.orange,
      Colors.purple,
      Colors.pink,
    ];
    final windows = {
      for (final window in snapshot?.windows ?? const <QuotaWindow>[])
        window.id: window,
    };
    final bars = grouped.entries.toList().asMap().entries.map((entry) {
      final values = entry.value.value
        ..sort((a, b) => a.timestamp.compareTo(b.timestamp));
      return LineChartBarData(
        spots: values
            .map(
              (point) => FlSpot(
                (point.timestamp - earliest).toDouble(),
                point.usedPercent.clamp(0, 100).toDouble(),
              ),
            )
            .toList(),
        isCurved: true,
        color: colors[entry.key % colors.length],
        barWidth: 3,
        dotData: const FlDotData(show: false),
      );
    }).toList();
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              height: 240,
              child: LineChart(
                LineChartData(
                  minY: 0,
                  maxY: 100,
                  lineBarsData: bars,
                  borderData: FlBorderData(show: false),
                  gridData: const FlGridData(drawVerticalLine: false),
                  titlesData: FlTitlesData(
                    topTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                    rightTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                    bottomTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                    leftTitles: const AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 36,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 12,
              runSpacing: 6,
              children: grouped.keys.toList().asMap().entries.map((entry) {
                final color = colors[entry.key % colors.length];
                return Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(width: 10, height: 10, color: color),
                    const SizedBox(width: 4),
                    Text(
                      windows[entry.value] == null
                          ? AppLocalizations.of(context).customLimit
                          : _windowTitle(context, windows[entry.value]!),
                    ),
                  ],
                );
              }).toList(),
            ),
          ],
        ),
      ),
    );
  }
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
            ],
          ),
        ),
        const SizedBox(height: 8),
        Text(l10n.privacy),
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
      await ref.read(appControllerProvider).acceptLogin(complete);
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
  final method = mobile
      ? await showModalBottomSheet<String>(
          context: context,
          showDragHandle: true,
          builder: (context) => const _LoginMethodChoices(),
        )
      : await showDialog<String>(
          context: context,
          builder: (context) => SimpleDialog(
            title: Text(AppLocalizations.of(context).addAccount),
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
