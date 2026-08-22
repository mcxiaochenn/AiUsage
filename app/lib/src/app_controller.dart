import 'dart:async';
import 'dart:io';
import 'dart:math';

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
    UsageResult? usage,
    ProfileUsage? profileUsage,
    Map<String, AccountDetails> accountDetails = const {},
  }) {
    final controller = AppController();
    controller._loading = false;
    controller._accounts = accounts;
    controller._selectedAccountId = accounts.firstOrNull?.identityHash;
    controller._settings = settings;
    controller._usage = usage;
    controller._profileUsage = profileUsage;
    controller._accountDetailsByAccount.addAll(accountDetails);
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
  ProfileUsage? _profileUsage;
  final Map<String, AccountDetails> _accountDetailsByAccount = {};
  final Set<String> _accountDetailsLoadingAccounts = {};
  final Map<String, String> _accountDetailsErrors = {};
  List<SyncLogEntry> _syncLogs = const [];
  bool _profileLoading = false;
  String? _profileError;

  List<StoredAccount> get accounts =>
      _settings.demoModeEnabled ? [_demoAccount] : List.unmodifiable(_accounts);
  StoredAccount? get selectedAccount => _settings.demoModeEnabled
      ? _demoAccount
      : _accounts.cast<StoredAccount?>().firstWhere(
          (item) => item?.identityHash == _selectedAccountId,
          orElse: () => null,
        );
  UsageResult? get usage => _settings.demoModeEnabled ? _demoUsage : _usage;
  ProfileUsage? get profileUsage =>
      _settings.demoModeEnabled ? _demoProfile : _profileUsage;
  AccountDetails? get accountDetails {
    if (_settings.demoModeEnabled) return _demoDetails;
    final identityHash = _selectedAccountId;
    return identityHash == null ? null : _accountDetailsByAccount[identityHash];
  }

  List<SyncLogEntry> get syncLogs => List.unmodifiable(_syncLogs);
  bool get profileLoading => _profileLoading;
  bool get accountDetailsLoading {
    final identityHash = _selectedAccountId;
    return identityHash != null &&
        _accountDetailsLoadingAccounts.contains(identityHash);
  }

  String? get profileError => _profileError;
  String? get accountDetailsError {
    final identityHash = _selectedAccountId;
    return identityHash == null ? null : _accountDetailsErrors[identityHash];
  }

  bool get demoMode => _settings.demoModeEnabled;
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
      await _preloadAccountDetailsCaches();
      _scheduleForegroundRefresh();
      await _backgroundScheduler.configure(
        enabled: _settings.backgroundRefreshEnabled,
        refreshMinutes: _settings.refreshMinutes,
      );
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
    if (_settings.demoModeEnabled) return;
    if (_selectedAccountId == identityHash) return;
    _selectedAccountId = identityHash;
    _usage = null;
    _profileUsage = null;
    _profileError = null;
    notifyListeners();
    await loadCached();
    unawaited(refresh());
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

  Future<void> refresh({SyncTrigger trigger = SyncTrigger.manual}) async {
    if (_settings.demoModeEnabled) return;
    final account = selectedAccount;
    final credential = account?.credential;
    if (account == null || credential == null || _refreshing) return;
    _refreshing = true;
    notifyListeners();
    try {
      final result = await core.refreshUsage(
        credential: credential,
        trigger: trigger,
      );
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
    await acceptLogin(completed, credentialSource: CredentialSource.authJson);
  }

  Future<void> acceptLogin(
    DeviceCodeLoginComplete completed, {
    required CredentialSource credentialSource,
  }) async {
    await _vault.saveSignedIn(
      completed.account,
      completed.credential,
      credentialSource,
    );
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
    _accountDetailsByAccount.remove(identityHash);
    _accountDetailsLoadingAccounts.remove(identityHash);
    _accountDetailsErrors.remove(identityHash);
    _accounts = await _vault.loadAccounts();
    if (_selectedAccountId == identityHash) {
      _selectedAccountId = _accounts.firstOrNull?.identityHash;
      _usage = null;
      _profileUsage = null;
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

  Future<void> loadProfile({bool force = false}) async {
    if (_settings.demoModeEnabled || _profileLoading) return;
    final account = selectedAccount;
    final credential = account?.credential;
    if (account == null || credential == null) return;
    _profileLoading = true;
    _profileError = null;
    notifyListeners();
    try {
      if (!force) {
        _profileUsage = await core.cachedProfileUsage(
          accountIdentityHash: account.identityHash,
        );
        if (_profileUsage != null) notifyListeners();
      }
      _profileUsage = await core.fetchProfileUsage(
        credential: credential,
        trigger: SyncTrigger.pageLoad,
      );
    } catch (error) {
      _profileError = error.toString();
    } finally {
      _profileLoading = false;
      notifyListeners();
    }
  }

  Future<void> loadAccountDetails(
    StoredAccount account, {
    bool force = false,
  }) async {
    final identityHash = account.identityHash;
    if (_settings.demoModeEnabled ||
        _accountDetailsLoadingAccounts.contains(identityHash)) {
      return;
    }
    final credential = account.credential;
    if (credential == null) return;
    _accountDetailsLoadingAccounts.add(identityHash);
    _accountDetailsErrors.remove(identityHash);
    notifyListeners();
    try {
      if (!force && !_accountDetailsByAccount.containsKey(identityHash)) {
        final cached = await core.cachedAccountDetails(
          accountIdentityHash: identityHash,
        );
        if (cached != null) {
          _accountDetailsByAccount[identityHash] = cached;
          notifyListeners();
        }
      }
      _accountDetailsByAccount[identityHash] = await core.fetchAccountDetails(
        credential: credential,
        trigger: SyncTrigger.pageLoad,
      );
    } catch (error) {
      _accountDetailsErrors[identityHash] = error.toString();
    } finally {
      _accountDetailsLoadingAccounts.remove(identityHash);
      notifyListeners();
    }
  }

  Future<void> _preloadAccountDetailsCaches() async {
    for (final account in _accounts) {
      try {
        final cached = await core.cachedAccountDetails(
          accountIdentityHash: account.identityHash,
        );
        if (cached != null) {
          _accountDetailsByAccount[account.identityHash] = cached;
        }
      } catch (_) {
        // Account details are optional and may not have been fetched yet.
      }
    }
  }

  Future<void> loadSyncLogs() async {
    try {
      _syncLogs = await core.syncLogs();
      notifyListeners();
    } catch (_) {
      // Diagnostics are optional and must never interrupt primary monitoring.
    }
  }

  Future<void> updateSettings(MonitorSettings value) async {
    final enablingNotifications =
        value.notificationsEnabled && !_settings.notificationsEnabled;
    if (value.demoModeEnabled &&
        !_settings.demoModeEnabled &&
        value.demoSeed == 0) {
      value = value.copyWith(demoSeed: Random.secure().nextInt(0x7fffffff));
    }
    _settings = value;
    await _vault.saveSettings(value);
    _scheduleForegroundRefresh();
    await _backgroundScheduler.configure(
      enabled: value.backgroundRefreshEnabled && !value.demoModeEnabled,
      refreshMinutes: value.refreshMinutes,
    );
    if (enablingNotifications) {
      await _notifications.requestPermission(locale: value.locale);
    }
    notifyListeners();
  }

  void _replaceAccount(AccountInfo account, SecureCredential credential) {
    _accounts = _accounts
        .map(
          (item) => item.identityHash == account.identityHash
              ? StoredAccount.fromAccount(
                  account,
                  credentialSource: item.credentialSource,
                ).withCredential(credential)
              : item,
        )
        .toList(growable: false);
  }

  void _scheduleForegroundRefresh() {
    _foregroundTimer?.cancel();
    if (_settings.refreshMinutes == 0) return;
    _foregroundTimer = Timer.periodic(
      Duration(minutes: _settings.refreshMinutes),
      (_) => unawaited(refresh(trigger: SyncTrigger.foregroundTimer)),
    );
  }

  StoredAccount get _demoAccount {
    final random = Random(_settings.demoSeed);
    return StoredAccount(
      identityHash: 'demo-account',
      email: 'demo${100 + random.nextInt(900)}@example.com',
      plan: ['plus', 'pro'][random.nextInt(2)],
      loginState: LoginState.signedIn,
      lastSuccessfulRefresh: DateTime.now().millisecondsSinceEpoch ~/ 1000,
      credential: const SecureCredential(
        idToken: 'demo',
        accessToken: 'demo',
        refreshToken: 'demo',
      ),
    );
  }

  UsageResult get _demoUsage {
    final random = Random(_settings.demoSeed);
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final account = _demoAccount.account;
    return UsageResult(
      state: UsageState.fresh,
      showingCachedData: false,
      snapshot: UsageSnapshot(
        account: account,
        windows: [
          QuotaWindow(
            id: 'codex:primary',
            title: '5-hour limit',
            usedPercent: (20 + random.nextInt(65)).toDouble(),
            resetAt: now + 7200,
            windowSeconds: 18000,
          ),
          QuotaWindow(
            id: 'codex:secondary',
            title: '1-week limit',
            usedPercent: (10 + random.nextInt(75)).toDouble(),
            resetAt: now + 4 * 86400,
            windowSeconds: 7 * 86400,
          ),
        ],
        resetCreditsAvailable: 2,
        resetCredits: [
          ResetCredit(
            id: 'demo-reset',
            status: 'available',
            grantedAt: now - 86400,
            expiresAt: now + 14 * 86400,
            title: 'Full reset',
            description: 'Demo credit',
          ),
        ],
        credits: const CreditsSnapshot(
          hasCredits: true,
          unlimited: false,
          balance: '25.00',
        ),
        fetchedAt: now,
      ),
    );
  }

  ProfileUsage get _demoProfile {
    final random = Random(_settings.demoSeed);
    final today = DateTime.now();
    final buckets = List.generate(120, (index) {
      final date = DateTime(
        today.year,
        today.month,
        today.day,
      ).subtract(Duration(days: 119 - index));
      return DailyTokenBucket(
        startDate:
            '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}',
        tokens: random.nextInt(2500000),
      );
    });
    final peak = buckets.map((item) => item.tokens).reduce(max);
    final lifetime = buckets.fold<int>(0, (sum, item) => sum + item.tokens);
    return ProfileUsage(
      summary: TokenUsageSummary(
        lifetimeTokens: lifetime,
        peakDailyTokens: peak,
        longestRunningTurnSec: 1420,
        currentStreakDays: 6,
        longestStreakDays: 18,
      ),
      dailyUsageBuckets: buckets,
      fetchedAt: DateTime.now().millisecondsSinceEpoch ~/ 1000,
    );
  }

  AccountDetails get _demoDetails {
    final now = DateTime.now();
    return AccountDetails(
      createdAt:
          now.subtract(const Duration(days: 486)).millisecondsSinceEpoch ~/
          1000,
      email: _demoAccount.email,
      fetchedAt: now.millisecondsSinceEpoch ~/ 1000,
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
