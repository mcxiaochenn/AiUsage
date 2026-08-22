import 'dart:async';

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import 'app_controller.dart';
import 'rust/models.dart';
import 'services/secure_account_vault.dart';

final appControllerProvider = ChangeNotifierProvider<AppController>(
  (ref) => throw UnimplementedError('The app controller must be overridden.'),
);

class CodexUsageMonitorApp extends StatelessWidget {
  const CodexUsageMonitorApp({super.key, required this.controller});

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
      title: 'Codex Usage Monitor',
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
  static const _labels = ['Dashboard', 'Accounts', 'History', 'Settings'];
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
    final content = Scaffold(
      appBar: AppBar(
        title: const Text('Codex Usage Monitor'),
        actions: [
          if (controller.accounts.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(right: 4),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: controller.selectedAccount?.identityHash,
                  hint: const Text('Account'),
                  items: controller.accounts
                      .map(
                        (account) => DropdownMenuItem(
                          value: account.identityHash,
                          child: Text(account.email ?? 'Unknown account'),
                        ),
                      )
                      .toList(),
                  onChanged: (value) {
                    if (value != null) {
                      unawaited(controller.selectAccount(value));
                    }
                  },
                ),
              ),
            ),
          IconButton(
            tooltip: 'Refresh',
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
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: FilledButton.icon(
              onPressed: () => _showDeviceLogin(context),
              icon: const Icon(Icons.person_add_alt_1),
              label: const Text('Add account'),
            ),
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
                _labels.length,
                (index) => NavigationDestination(
                  icon: Icon(_icons[index]),
                  label: _labels[index],
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
              _labels.length,
              (index) => NavigationRailDestination(
                icon: Icon(_icons[index]),
                label: Text(_labels[index]),
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

class DashboardPage extends ConsumerWidget {
  const DashboardPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.watch(appControllerProvider);
    if (controller.loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (controller.accounts.isEmpty) {
      return _EmptyState(
        icon: Icons.monitor_heart_outlined,
        title: 'Add a Codex account',
        message:
            'Use the official OpenAI device sign-in flow. Tokens stay in your system keychain.',
        action: FilledButton.icon(
          onPressed: () => _showDeviceLogin(context),
          icon: const Icon(Icons.person_add_alt_1),
          label: const Text('Add account'),
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
              message: controller.bootError!,
              state: UsageState.serverError,
            ),
          if (result != null && result.state != UsageState.fresh)
            _StateBanner(
              message: result.message ?? _stateMessage(result.state),
              state: result.state,
              cached: result.showingCachedData,
            ),
          if (snapshot == null)
            const _EmptyState(
              icon: Icons.cloud_off_outlined,
              title: 'No usage snapshot yet',
              message: 'Pull down or use Refresh to request the latest quota.',
            )
          else ...[
            _AccountHeader(snapshot: snapshot),
            const SizedBox(height: 12),
            if (snapshot.windows.isEmpty)
              const Card(
                child: Padding(
                  padding: EdgeInsets.all(20),
                  child: Text(
                    'OpenAI did not return any quota windows for this account.',
                  ),
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
                  title: const Text('Reset Credits'),
                  subtitle: const Text(
                    'Read-only. This app never consumes credits.',
                  ),
                  trailing: Text(
                    '${snapshot.resetCreditsAvailable} available',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
              ),
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                'Updated ${_relativeTime(snapshot.fetchedAt)} · ${_absoluteTime(snapshot.fetchedAt)}',
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
  Widget build(BuildContext context) => Card(
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
                  snapshot.account.email ?? 'Unknown account',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                Text(snapshot.account.plan ?? 'Unknown plan'),
              ],
            ),
          ),
          const Icon(Icons.verified_user_outlined),
        ],
      ),
    ),
  );
}

class _QuotaWindowCard extends StatelessWidget {
  const _QuotaWindowCard({required this.window});

  final QuotaWindow window;

  @override
  Widget build(BuildContext context) => StreamBuilder<int>(
    stream: Stream<int>.periodic(const Duration(minutes: 1), (value) => value),
    builder: (context, _) {
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
                      window.title,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                  Text('${used.round()}% used'),
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
              Text('${remaining.round()}% remaining'),
              const SizedBox(height: 4),
              Text('Reset in ${_remainingTime(window.resetAt)}'),
              Text(
                'Resets ${_absoluteTime(window.resetAt)}',
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
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text('Accounts', style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 8),
        if (controller.accounts.isEmpty)
          const _EmptyState(
            icon: Icons.person_off_outlined,
            title: 'No accounts',
            message: 'Add an account to start monitoring usage.',
          ),
        ...controller.accounts.map(
          (account) => Card(
            child: ListTile(
              leading: CircleAvatar(
                child: Text(
                  (account.email ?? '?').characters.first.toUpperCase(),
                ),
              ),
              title: Text(account.email ?? 'Unknown account'),
              subtitle: Text(
                '${account.plan ?? 'Unknown plan'} · ${_loginStateLabel(account.loginState)}\n'
                'Last successful refresh: ${account.lastSuccessfulRefresh == null ? 'Never' : _absoluteTime(account.lastSuccessfulRefresh!)}\n'
                'Credential: ${account.credential == null ? 'Cleared' : 'Available in system secure storage'}',
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
                  const PopupMenuItem(value: 'refresh', child: Text('Refresh')),
                  const PopupMenuItem(value: 'logout', child: Text('Logout')),
                  const PopupMenuItem(
                    value: 'remove',
                    child: Text('Remove account'),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: () => _showDeviceLogin(context),
          icon: const Icon(Icons.person_add_alt_1),
          label: const Text('Add account'),
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
        final confirmed = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Remove account?'),
            content: const Text(
              'This clears its locally stored credential and all local usage history. OpenAI data is not changed.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Remove'),
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
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text('History', style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 8),
        SegmentedButton<Duration>(
          segments: const [
            ButtonSegment(value: Duration(hours: 24), label: Text('24 hours')),
            ButtonSegment(value: Duration(days: 7), label: Text('7 days')),
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
              return const _EmptyState(
                icon: Icons.query_stats_outlined,
                title: 'No history in this period',
                message:
                    'History is recorded after successful usage refreshes and is retained for 7 days.',
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
    final titles = {
      for (final window in snapshot?.windows ?? const <QuotaWindow>[])
        window.id: window.title,
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
                    Text(titles[entry.value] ?? 'Custom limit'),
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
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text('Settings', style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 8),
        Card(
          child: Column(
            children: [
              const ListTile(title: Text('Theme')),
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
                        title: Text(_themeLabel(value)),
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
              const ListTile(
                title: Text('Refresh'),
                subtitle: Text(
                  'Foreground refresh follows this interval. Mobile background refresh is best effort.',
                ),
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
                        title: Text(minutes == 0 ? 'Manual' : '$minutes min'),
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
                title: const Text('Show reset credits'),
                subtitle: const Text(
                  'Read-only availability, never consume or redeem.',
                ),
                value: settings.showResetCredits,
                onChanged: (value) => unawaited(
                  controller.updateSettings(
                    settings.copyWith(showResetCredits: value),
                  ),
                ),
              ),
              SwitchListTile(
                title: const Text('Notifications'),
                subtitle: const Text(
                  '80%, 95%, and reset alerts. Background delivery is best effort.',
                ),
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
        const Text(
          'Privacy: no analytics, telemetry, cloud sync, or backend. Credentials and history remain on this device.',
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
  });

  final String message;
  final UsageState state;
  final bool cached;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
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
              child: Text(cached ? '$message Showing cached data.' : message),
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

class _DeviceLoginDialogState extends ConsumerState<_DeviceLoginDialog> {
  DeviceCodeLoginStart? _start;
  Timer? _pollTimer;
  String? _error;
  bool _finished = false;

  @override
  void initState() {
    super.initState();
    unawaited(_begin());
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    final loginId = _start?.loginId;
    if (!_finished && loginId != null) {
      unawaited(ref.read(appControllerProvider).cancelDeviceLogin(loginId));
    }
    super.dispose();
  }

  Future<void> _begin() async {
    try {
      final start = await ref.read(appControllerProvider).beginAddAccount();
      if (!mounted) return;
      setState(() => _start = start);
      await launchUrl(
        Uri.parse(start.verificationUrl),
        mode: LaunchMode.externalApplication,
      );
      _pollTimer = Timer.periodic(
        Duration(seconds: start.pollIntervalSeconds),
        (_) => unawaited(_poll()),
      );
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
    }
  }

  Future<void> _poll() async {
    final start = _start;
    if (start == null || _finished) return;
    try {
      final result = await ref
          .read(appControllerProvider)
          .pollDeviceLogin(start.loginId);
      final complete = result.completed;
      if (complete == null) return;
      _finished = true;
      _pollTimer?.cancel();
      await ref.read(appControllerProvider).acceptLogin(complete);
      if (mounted) Navigator.pop(context);
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Sign in to Codex'),
    content: SizedBox(
      width: 420,
      child: _error != null
          ? Text('Sign-in failed: $_error')
          : _start == null
          ? const SizedBox(
              height: 96,
              child: Center(child: CircularProgressIndicator()),
            )
          : Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Complete sign-in in your browser, then enter this code if requested:',
                ),
                const SizedBox(height: 16),
                SelectableText(
                  _start!.userCode,
                  style: Theme.of(context).textTheme.headlineMedium,
                ),
                const SizedBox(height: 12),
                Text('Waiting for authorization at ${_start!.verificationUrl}'),
                const SizedBox(height: 12),
                const LinearProgressIndicator(),
              ],
            ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      if (_start != null)
        TextButton.icon(
          onPressed: () => launchUrl(
            Uri.parse(_start!.verificationUrl),
            mode: LaunchMode.externalApplication,
          ),
          icon: const Icon(Icons.open_in_new),
          label: const Text('Open browser'),
        ),
    ],
  );
}

Future<void> _showDeviceLogin(BuildContext context) => showDialog<void>(
  context: context,
  barrierDismissible: false,
  builder: (context) => const _DeviceLoginDialog(),
);

String _remainingTime(int resetAt) {
  final seconds = resetAt - DateTime.now().millisecondsSinceEpoch ~/ 1000;
  if (seconds <= 0) {
    return 'now';
  }
  final duration = Duration(seconds: seconds);
  if (duration.inDays > 0) {
    return '${duration.inDays}d ${duration.inHours.remainder(24)}h';
  }
  if (duration.inHours > 0) {
    return '${duration.inHours}h ${duration.inMinutes.remainder(60)}m';
  }
  return '${duration.inMinutes}m';
}

String _relativeTime(int timestamp) {
  final seconds = DateTime.now().millisecondsSinceEpoch ~/ 1000 - timestamp;
  if (seconds < 60) return 'just now';
  if (seconds < 3600) return '${seconds ~/ 60}m ago';
  if (seconds < 86400) return '${seconds ~/ 3600}h ago';
  return '${seconds ~/ 86400}d ago';
}

String _absoluteTime(int timestamp) {
  if (timestamp <= 0) return 'Unavailable';
  final date = DateTime.fromMillisecondsSinceEpoch(timestamp * 1000).toLocal();
  final minute = date.minute.toString().padLeft(2, '0');
  return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')} ${date.hour.toString().padLeft(2, '0')}:$minute';
}

String _stateMessage(UsageState state) => switch (state) {
  UsageState.stale => 'Unable to refresh.',
  UsageState.authExpired => 'Sign-in expired. Add the account again.',
  UsageState.offline => 'You appear to be offline.',
  UsageState.rateLimited => 'OpenAI asked the app to wait before retrying.',
  UsageState.serverError => 'OpenAI returned a server error.',
  UsageState.parseError => 'OpenAI returned an unsupported usage response.',
  UsageState.fresh => '',
};

String _loginStateLabel(LoginState state) => switch (state) {
  LoginState.signedIn => 'Signed in',
  LoginState.signedOut => 'Signed out',
  LoginState.expired => 'Expired',
};

String _themeLabel(ThemePreference value) => switch (value) {
  ThemePreference.system => 'System',
  ThemePreference.light => 'Light',
  ThemePreference.dark => 'Dark',
};
