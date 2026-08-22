import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import 'rust/api/application.dart' as core;
import 'rust/models.dart';
import 'services/background_refresh.dart';
import 'services/notification_service.dart';
import 'services/secure_account_vault.dart';

class AppController extends ChangeNotifier {
  AppController({
    SecureAccountVault? vault,
    NotificationService? notifications,
    BackgroundRefreshScheduler? backgroundScheduler,
  }) : _vault = vault ?? SecureAccountVault(),
       _notifications = notifications ?? NotificationService(),
       _backgroundScheduler =
           backgroundScheduler ?? const BackgroundRefreshScheduler();

  /// Useful for widget tests: no platform channels are contacted until
  /// [bootstrap] is called.
  factory AppController.testing({
    List<StoredAccount> accounts = const [],
    MonitorSettings settings = const MonitorSettings(),
  }) {
    final controller = AppController();
    controller._loading = false;
    controller._accounts = accounts;
    controller._selectedAccountId = accounts.firstOrNull?.identityHash;
    controller._settings = settings;
    return controller;
  }

  final SecureAccountVault _vault;
  final NotificationService _notifications;
  final BackgroundRefreshScheduler _backgroundScheduler;
  Timer? _foregroundTimer;

  List<StoredAccount> _accounts = const [];
  String? _selectedAccountId;
  UsageResult? _usage;
  MonitorSettings _settings = const MonitorSettings();
  bool _loading = true;
  bool _refreshing = false;
  String? _bootError;

  List<StoredAccount> get accounts => List.unmodifiable(_accounts);
  StoredAccount? get selectedAccount =>
      _accounts.cast<StoredAccount?>().firstWhere(
        (item) => item?.identityHash == _selectedAccountId,
        orElse: () => null,
      );
  UsageResult? get usage => _usage;
  MonitorSettings get settings => _settings;
  bool get loading => _loading;
  bool get refreshing => _refreshing;
  String? get bootError => _bootError;

  Future<void> bootstrap() async {
    try {
      final supportDirectory = await getApplicationSupportDirectory();
      final databasePath =
          '${supportDirectory.path}${Platform.pathSeparator}aiusage.sqlite3';
      await core.initializeCore(databasePath: databasePath);
      _settings = await _vault.loadSettings();
      _accounts = await _vault.loadAccounts();
      _selectedAccountId = _accounts.firstOrNull?.identityHash;
      _scheduleForegroundRefresh();
      await _backgroundScheduler.configure(_settings.refreshMinutes);
      if (selectedAccount != null) {
        await loadCached();
        unawaited(refresh());
      }
    } catch (error) {
      _bootError = 'Unable to initialize local storage: $error';
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  Future<void> selectAccount(String identityHash) async {
    _selectedAccountId = identityHash;
    _usage = null;
    notifyListeners();
    await loadCached();
    await refresh();
  }

  Future<void> loadCached() async {
    final account = selectedAccount;
    if (account == null) return;
    try {
      final result = await core.cachedUsage(account: account.account);
      if (result.snapshot != null) {
        _usage = result;
        notifyListeners();
      }
    } catch (_) {
      // An empty first-run cache is normal.
    }
  }

  Future<void> refresh() async {
    final account = selectedAccount;
    final credential = account?.credential;
    if (account == null || credential == null || _refreshing) return;
    _refreshing = true;
    notifyListeners();
    try {
      final result = await core.refreshUsage(credential: credential);
      _usage = result;
      if (result.updatedCredential != null) {
        await _vault.updateCredential(
          account.identityHash,
          result.updatedCredential!,
        );
      }
      if (result.snapshot != null) {
        await _vault.updateAccount(result.snapshot!.account);
        _replaceAccount(
          result.snapshot!.account,
          result.updatedCredential ?? credential,
        );
        if (_settings.notificationsEnabled) {
          await _notifications.inspectSnapshot(
            result.snapshot!,
            locale: _settings.locale,
          );
        }
      }
    } catch (error) {
      _usage = UsageResult(
        state: UsageState.offline,
        showingCachedData: _usage?.snapshot != null,
        snapshot: _usage?.snapshot,
        message: 'Unable to refresh: $error',
      );
    } finally {
      _refreshing = false;
      notifyListeners();
    }
  }

  Future<DeviceCodeLoginStart> beginAddAccount() => core.beginDeviceLogin();

  Future<DeviceCodeLoginPoll> pollDeviceLogin(String loginId) =>
      core.pollDeviceLogin(loginId: loginId);

  Future<void> cancelDeviceLogin(String loginId) =>
      core.cancelDeviceLogin(loginId: loginId);

  Future<void> importAccount(Uint8List content) async {
    final completed = await core.importCodexAuthJson(content: content);
    await acceptLogin(completed);
  }

  Future<void> acceptLogin(DeviceCodeLoginComplete completed) async {
    await _vault.saveSignedIn(completed.account, completed.credential);
    _accounts = await _vault.loadAccounts();
    _selectedAccountId = completed.account.identityHash;
    _usage = null;
    notifyListeners();
    await refresh();
  }

  Future<void> logoutSelected() async {
    final account = selectedAccount;
    if (account == null) return;
    await _vault.signOut(account.identityHash);
    _accounts = await _vault.loadAccounts();
    _usage = null;
    notifyListeners();
  }

  Future<void> removeAccount(String identityHash) async {
    await _vault.removeAccount(identityHash);
    await core.removeAccountData(accountIdentityHash: identityHash);
    _accounts = await _vault.loadAccounts();
    if (_selectedAccountId == identityHash) {
      _selectedAccountId = _accounts.firstOrNull?.identityHash;
      _usage = null;
    }
    notifyListeners();
    await loadCached();
  }

  Future<List<HistoryPoint>> history(Duration period) async {
    final account = selectedAccount;
    if (account == null) return const [];
    final since =
        DateTime.now().subtract(period).millisecondsSinceEpoch ~/ 1000;
    return core.usageHistory(
      accountIdentityHash: account.identityHash,
      since: since,
    );
  }

  Future<void> updateSettings(MonitorSettings value) async {
    final enablingNotifications =
        value.notificationsEnabled && !_settings.notificationsEnabled;
    _settings = value;
    await _vault.saveSettings(value);
    _scheduleForegroundRefresh();
    await _backgroundScheduler.configure(value.refreshMinutes);
    if (enablingNotifications) {
      await _notifications.requestPermission(locale: value.locale);
    }
    notifyListeners();
  }

  void _replaceAccount(AccountInfo account, SecureCredential credential) {
    _accounts = _accounts
        .map(
          (item) => item.identityHash == account.identityHash
              ? StoredAccount.fromAccount(account).withCredential(credential)
              : item,
        )
        .toList(growable: false);
  }

  void _scheduleForegroundRefresh() {
    _foregroundTimer?.cancel();
    if (_settings.refreshMinutes == 0) return;
    _foregroundTimer = Timer.periodic(
      Duration(minutes: _settings.refreshMinutes),
      (_) => unawaited(refresh()),
    );
  }

  @override
  void dispose() {
    _foregroundTimer?.cancel();
    super.dispose();
  }
}

extension _ListFirstOrNull<T> on List<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
