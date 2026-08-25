import 'dart:async';
import 'dart:convert';
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
    controller._settings = settings;
    controller._restoreSelection();
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
  ProviderKind? _selectedProvider;
  String? _selectedAccountId;
  ProviderKind? _selectedDemoProvider;
  String? _selectedDemoAccountId;
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
      _settings.demoModeEnabled ? _demoAccounts : List.unmodifiable(_accounts);
  List<ProviderKind> get availableProviders => _providersFor(accounts);
  ProviderKind? get selectedProvider => _settings.demoModeEnabled
      ? _selectedDemoProvider ?? _demoAccounts.first.provider
      : _selectedProvider;
  List<StoredAccount> get currentProviderAccounts {
    final provider = selectedProvider;
    if (provider == null) return const [];
    return accounts
        .where((item) => item.provider == provider)
        .toList(growable: false);
  }

  StoredAccount? get selectedAccount => _settings.demoModeEnabled
      ? _demoAccounts.cast<StoredAccount?>().firstWhere(
          (item) =>
              item?.identityHash == _selectedDemoAccountId &&
              item?.provider == selectedProvider,
          orElse: () => _demoAccounts.firstWhere(
            (item) => item.provider == selectedProvider,
          ),
        )
      : _accounts.cast<StoredAccount?>().firstWhere(
          (item) =>
              item?.identityHash == _selectedAccountId &&
              item?.provider == selectedProvider,
          orElse: () => _accounts
              .where((item) => item.provider == selectedProvider)
              .cast<StoredAccount?>()
              .firstOrNull,
        );
  UsageResult? get usage => _settings.demoModeEnabled
      ? _demoUsageFor(selectedAccount?.provider ?? ProviderKind.codex)
      : _usage;
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
      _restoreSelection();
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
    if (_settings.demoModeEnabled) {
      final account = _demoAccounts
          .where((item) => item.identityHash == identityHash)
          .firstOrNull;
      if (account == null) return;
      _selectedDemoProvider = account.provider;
      _selectedDemoAccountId = account.identityHash;
      notifyListeners();
      return;
    }
    final account = _accounts
        .where((item) => item.identityHash == identityHash)
        .firstOrNull;
    if (account == null) return;
    if (_selectedAccountId == identityHash &&
        _selectedProvider == account.provider) {
      return;
    }
    _selectedProvider = account.provider;
    _selectedAccountId = identityHash;
    await _persistSelection();
    _usage = null;
    _profileUsage = null;
    _profileError = null;
    notifyListeners();
    await loadCached();
    unawaited(refresh());
  }

  Future<void> selectProvider(ProviderKind provider) async {
    if (_settings.demoModeEnabled) {
      _selectedDemoProvider = provider;
      final account = _demoAccounts
          .where((item) => item.provider == provider)
          .firstOrNull;
      _selectedDemoAccountId = account?.identityHash;
      notifyListeners();
      return;
    }
    final providerAccounts = _accounts
        .where((item) => item.provider == provider)
        .toList(growable: false);
    if (providerAccounts.isEmpty) return;
    final remembered = _settings.selectedAccountByProvider[provider.name];
    final account = providerAccounts.firstWhere(
      (item) => item.identityHash == remembered,
      orElse: () => providerAccounts.first,
    );
    if (_selectedProvider == provider &&
        _selectedAccountId == account.identityHash) {
      return;
    }
    _selectedProvider = provider;
    _selectedAccountId = account.identityHash;
    await _persistSelection();
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
    if (account == null || !account.hasCredential || _refreshing) return;
    _refreshing = true;
    notifyListeners();
    try {
      final result = await _refreshProvider(account, trigger);
      _usage = result;
      if (result.updatedCredential != null) {
        await _vault.updateCredential(
          account.identityHash,
          result.updatedCredential!,
        );
      }
      if (result.updatedMimoCredential != null) {
        await _vault.updateMimoCredential(
          account.identityHash,
          result.updatedMimoCredential!,
        );
      }
      if (result.snapshot != null) {
        await _vault.updateAccount(
          result.snapshot!.account,
          avatarUrl: result.updatedCredential == null
              ? account.avatarUrl
              : _avatarUrlFromCredential(result.updatedCredential!),
        );
        _replaceAccount(result.snapshot!.account, account, result);
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

  Future<UsageResult> _refreshProvider(
    StoredAccount account,
    SyncTrigger trigger,
  ) => switch (account.provider) {
    ProviderKind.codex => core.refreshUsage(
      credential: account.credential!,
      trigger: trigger,
    ),
    ProviderKind.deepSeek => core.refreshDeepseekUsage(
      apiKey: account.apiKey!,
      trigger: trigger,
    ),
    ProviderKind.mimo => core.refreshMimoUsage(
      credential: account.mimoCredential!,
      trigger: trigger,
    ),
  };

  Future<DeviceCodeLoginStart> beginAddAccount() => core.beginDeviceLogin();

  Future<DeviceCodeLoginPoll> pollDeviceLogin(String loginId) =>
      core.pollDeviceLogin(loginId: loginId);

  Future<void> cancelDeviceLogin(String loginId) =>
      core.cancelDeviceLogin(loginId: loginId);

  Future<void> importAccount(Uint8List content, {String? displayName}) async {
    final completed = await core.importCodexAuthJson(content: content);
    await acceptLogin(
      completed,
      credentialSource: CredentialSource.authJson,
      displayName: displayName,
    );
  }

  Future<void> acceptLogin(
    DeviceCodeLoginComplete completed, {
    required CredentialSource credentialSource,
    String? displayName,
  }) async {
    await _vault.saveSignedIn(
      completed.account,
      completed.credential,
      credentialSource,
      displayName: _normalizedName(displayName),
      avatarUrl: _avatarUrlFromCredential(completed.credential),
    );
    _accounts = await _vault.loadAccounts();
    _selectedProvider = ProviderKind.codex;
    _selectedAccountId = completed.account.identityHash;
    await _persistSelection();
    _usage = null;
    notifyListeners();
    await refresh();
  }

  Future<void> addDeepSeekAccount({
    required String apiKey,
    String? alias,
  }) async {
    final normalizedKey = apiKey.trim();
    if (normalizedKey.isEmpty) {
      throw const FormatException('deepseek.empty_key');
    }
    final result = await core.refreshDeepseekUsage(
      apiKey: normalizedKey,
      trigger: SyncTrigger.manual,
    );
    final snapshot = result.snapshot;
    if (snapshot == null || result.state != UsageState.fresh) {
      throw StateError(result.message ?? 'deepseek.validation_failed');
    }
    await _vault.saveDeepSeek(
      snapshot.account,
      normalizedKey,
      displayName: (alias == null || alias.trim().isEmpty)
          ? null
          : alias.trim(),
    );
    _accounts = await _vault.loadAccounts();
    _selectedProvider = ProviderKind.deepSeek;
    _selectedAccountId = snapshot.account.identityHash;
    await _persistSelection();
    _usage = result;
    notifyListeners();
  }

  Future<MimoLoginResult> beginMimoAccount({
    required String username,
    required String password,
    String? displayName,
  }) async {
    final result = await core.beginMimoLogin(
      username: username.trim(),
      password: password,
    );
    if (result.account != null && result.credential != null) {
      await _acceptMimoLogin(
        result,
        source: CredentialSource.xiaomiPassword,
        displayName: displayName,
        accountHint: username.trim(),
      );
    }
    return result;
  }

  Future<void> completeMimoWebAccount({
    required String accountCookie,
    required String platformCookie,
    String? displayName,
    String? accountHint,
  }) async {
    final result = await core.completeMimoWebLogin(
      accountCookie: accountCookie,
      platformCookie: platformCookie,
    );
    await _acceptMimoLogin(
      result,
      source: CredentialSource.xiaomiWeb,
      displayName: displayName,
      accountHint: accountHint,
    );
  }

  Future<void> _acceptMimoLogin(
    MimoLoginResult result, {
    required CredentialSource source,
    String? displayName,
    String? accountHint,
  }) async {
    final account = result.account;
    final credential = result.credential;
    if (account == null || credential == null) {
      throw StateError('mimo.login_incomplete');
    }
    await _vault.saveMimo(
      account,
      credential,
      credentialSource: source,
      displayName: _normalizedName(displayName),
      accountHint: accountHint?.trim().isNotEmpty == true
          ? accountHint!.trim()
          : credential.userId,
    );
    _accounts = await _vault.loadAccounts();
    _selectedProvider = ProviderKind.mimo;
    _selectedAccountId = account.identityHash;
    await _persistSelection();
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
    _restoreSelection();
    await _persistSelection();
    _usage = null;
    _profileUsage = null;
    notifyListeners();
    await loadCached();
  }

  Future<void> renameAccount(String identityHash, String? displayName) async {
    await _vault.renameAccount(identityHash, displayName);
    _accounts = await _vault.loadAccounts();
    notifyListeners();
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
    if (account == null ||
        account.provider != ProviderKind.codex ||
        credential == null) {
      return;
    }
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
    if (account.provider != ProviderKind.codex || credential == null) return;
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

  Future<void> clearSyncLogs() async {
    await core.clearSyncLogs();
    _syncLogs = const [];
    notifyListeners();
  }

  Future<void> purgeAllUserData() async {
    _foregroundTimer?.cancel();
    await _backgroundScheduler.configure(enabled: false, refreshMinutes: 0);
    await _notifications.cancelAll();
    await _vault.clearAll();
    await core.purgeAllData();
    _accounts = const [];
    _selectedProvider = null;
    _selectedAccountId = null;
    _usage = null;
    _profileUsage = null;
    _accountDetailsByAccount.clear();
    _accountDetailsLoadingAccounts.clear();
    _accountDetailsErrors.clear();
    _syncLogs = const [];
    _settings = const MonitorSettings();
    notifyListeners();
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

  void _replaceAccount(
    AccountInfo account,
    StoredAccount previous,
    UsageResult result,
  ) {
    _accounts = _accounts
        .map(
          (item) => item.identityHash == account.identityHash
              ? StoredAccount.fromAccount(
                  account,
                  displayName: item.displayName,
                  credentialSource: item.credentialSource,
                  avatarUrl: result.updatedCredential == null
                      ? item.avatarUrl
                      : _avatarUrlFromCredential(result.updatedCredential!),
                  mimoAccountHint: item.mimoAccountHint,
                ).withCredentials(
                  codexCredential:
                      result.updatedCredential ?? previous.credential,
                  apiKey: previous.apiKey,
                  mimoCredential:
                      result.updatedMimoCredential ?? previous.mimoCredential,
                )
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

  void _restoreSelection() {
    final providers = _providersFor(_accounts);
    if (providers.isEmpty) {
      _selectedProvider = null;
      _selectedAccountId = null;
      return;
    }
    final provider = providers.contains(_settings.selectedProvider)
        ? _settings.selectedProvider!
        : providers.first;
    final remembered = _settings.selectedAccountByProvider[provider.name];
    final account = _accounts.firstWhere(
      (item) => item.provider == provider && item.identityHash == remembered,
      orElse: () => _accounts.firstWhere((item) => item.provider == provider),
    );
    _selectedProvider = provider;
    _selectedAccountId = account.identityHash;
  }

  Future<void> _persistSelection() async {
    final provider = _selectedProvider;
    final accountId = _selectedAccountId;
    if (provider == null || accountId == null) return;
    final selected = Map<String, String>.from(
      _settings.selectedAccountByProvider,
    )..[provider.name] = accountId;
    _settings = _settings.copyWith(
      selectedProvider: provider,
      selectedAccountByProvider: Map.unmodifiable(selected),
    );
    await _vault.saveSettings(_settings);
  }

  List<ProviderKind> _providersFor(Iterable<StoredAccount> values) => [
    for (final provider in ProviderKind.values)
      if (values.any((item) => item.provider == provider)) provider,
  ];

  String? _normalizedName(String? value) {
    final normalized = value?.trim();
    return normalized == null || normalized.isEmpty ? null : normalized;
  }

  String? _avatarUrlFromCredential(SecureCredential credential) {
    try {
      final parts = credential.idToken.split('.');
      if (parts.length < 2) return null;
      final payload = utf8.decode(
        base64Url.decode(base64Url.normalize(parts[1])),
      );
      final claims = jsonDecode(payload) as Map<String, dynamic>;
      final profile = claims['https://api.openai.com/profile'];
      final candidates = <Object?>[
        claims['picture'],
        claims['image_url'],
        claims['avatar_url'],
        if (profile is Map) profile['picture'],
        if (profile is Map) profile['image_url'],
        if (profile is Map) profile['avatar_url'],
      ];
      for (final candidate in candidates) {
        if (candidate is! String) continue;
        final uri = Uri.tryParse(candidate.trim());
        if (uri != null && uri.scheme == 'https' && uri.host.isNotEmpty) {
          return uri.toString();
        }
      }
    } catch (_) {
      // An identity token without a profile image must not interrupt login.
    }
    return null;
  }

  List<StoredAccount> get _demoAccounts {
    final random = Random(_settings.demoSeed);
    final refreshedAt = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    return [
      StoredAccount(
        identityHash: 'demo-codex',
        provider: ProviderKind.codex,
        email: 'demo${100 + random.nextInt(900)}@example.com',
        plan: ['plus', 'pro'][random.nextInt(2)],
        loginState: LoginState.signedIn,
        lastSuccessfulRefresh: refreshedAt,
        credential: const SecureCredential(
          idToken: 'demo',
          accessToken: 'demo',
          refreshToken: 'demo',
        ),
      ),
      StoredAccount(
        identityHash: 'demo-deepseek',
        provider: ProviderKind.deepSeek,
        displayName: 'DeepSeek Demo',
        plan: 'API',
        loginState: LoginState.signedIn,
        lastSuccessfulRefresh: refreshedAt,
        apiKey: 'demo',
        credentialSource: CredentialSource.apiKey,
      ),
      StoredAccount(
        identityHash: 'demo-mimo',
        provider: ProviderKind.mimo,
        displayName: 'MiMo Demo',
        plan: 'Token Plan',
        loginState: LoginState.signedIn,
        lastSuccessfulRefresh: refreshedAt,
        mimoCredential: const MimoCredential(
          userId: 'demo',
          passToken: 'demo',
          serviceToken: 'demo',
          serviceSlh: '',
          servicePh: '',
        ),
        credentialSource: CredentialSource.xiaomiPassword,
      ),
    ];
  }

  UsageResult _demoUsageFor(ProviderKind provider) {
    final random = Random(_settings.demoSeed);
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final account = _demoAccounts
        .firstWhere((item) => item.provider == provider)
        .account;
    if (provider == ProviderKind.deepSeek) {
      return UsageResult(
        state: UsageState.fresh,
        showingCachedData: false,
        snapshot: UsageSnapshot(
          account: account,
          windows: const [],
          balances: const [
            BalanceMetric(
              id: 'deepseek:CNY:total',
              label: 'Total balance',
              amount: '88.20',
              currency: 'CNY',
              primary: true,
            ),
            BalanceMetric(
              id: 'deepseek:CNY:granted',
              label: 'Granted balance',
              amount: '8.20',
              currency: 'CNY',
              primary: false,
            ),
          ],
          providerQuotas: const [],
          fetchedAt: now,
        ),
      );
    }
    if (provider == ProviderKind.mimo) {
      return UsageResult(
        state: UsageState.fresh,
        showingCachedData: false,
        snapshot: UsageSnapshot(
          account: account,
          windows: const [],
          balances: const [
            BalanceMetric(
              id: 'mimo:total',
              label: 'Total balance',
              amount: '42.00',
              currency: 'CNY',
              primary: true,
            ),
            BalanceMetric(
              id: 'mimo:gift',
              label: 'Gift balance',
              amount: '12.00',
              currency: 'CNY',
              primary: false,
            ),
          ],
          providerQuotas: [
            ProviderQuotaMetric(
              id: 'mimo:plan_total_token',
              title: 'Plan tokens',
              used: '240000',
              limit: '1000000',
              remaining: '760000',
              usedPercent: 24,
              expiresAt: now + 14 * 86400,
              unit: 'tokens',
            ),
          ],
          fetchedAt: now,
        ),
      );
    }
    return UsageResult(
      state: UsageState.fresh,
      showingCachedData: false,
      snapshot: UsageSnapshot(
        account: account,
        balances: const [],
        providerQuotas: const [],
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
      email: _demoAccounts.first.email,
      fetchedAt: now.millisecondsSinceEpoch ~/ 1000,
    );
  }

  @override
  void dispose() {
    _foregroundTimer?.cancel();
    super.dispose();
  }
}
