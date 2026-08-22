import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../rust/models.dart';

/// OAuth credential 的唯一持久化位置。
///
/// flutter_secure_storage 在 Android 使用 Keystore，在 Apple 平台使用
/// Keychain，在 Windows 使用受系统保护的凭据存储，在 Linux 使用 Secret
/// Service。账号索引不含 token；它也放在同一安全存储中以减少元数据泄露面。
class SecureAccountVault {
  SecureAccountVault({FlutterSecureStorage? storage})
    : _storage = storage ?? FlutterSecureStorage();

  static const _indexKey = 'codex_usage_monitor.account_index.v1';
  static const _settingsKey = 'codex_usage_monitor.settings.v1';

  final FlutterSecureStorage _storage;

  String _credentialKey(String identityHash) =>
      'codex_usage_monitor.credential.$identityHash.v1';

  Future<List<StoredAccount>> loadAccounts() async {
    final serialized = await _storage.read(key: _indexKey);
    if (serialized == null) return const [];

    try {
      final entries = (jsonDecode(serialized) as List<dynamic>)
          .cast<Map<String, dynamic>>();
      final accounts = <StoredAccount>[];
      for (final entry in entries) {
        final record = StoredAccount.fromMetadata(entry);
        final secret = await _storage.read(
          key: _credentialKey(record.identityHash),
        );
        accounts.add(record.withCredential(_credentialFromJson(secret)));
      }
      return accounts;
    } catch (_) {
      // A damaged index must not erase the credentials that may still be
      // recoverable from the platform keychain.
      return const [];
    }
  }

  Future<void> saveSignedIn(
    AccountInfo account,
    SecureCredential credential,
  ) async {
    final accounts = await loadAccounts();
    final updated = StoredAccount.fromAccount(
      account,
    ).withCredential(credential);
    final next = <StoredAccount>[
      updated,
      ...accounts.where((item) => item.identityHash != updated.identityHash),
    ];
    await _storage.write(
      key: _credentialKey(updated.identityHash),
      value: jsonEncode(_credentialToJson(credential)),
    );
    await _writeIndex(next);
  }

  Future<void> updateCredential(
    String identityHash,
    SecureCredential credential,
  ) async {
    await _storage.write(
      key: _credentialKey(identityHash),
      value: jsonEncode(_credentialToJson(credential)),
    );
  }

  Future<void> updateAccount(AccountInfo account) async {
    final accounts = await loadAccounts();
    final next = accounts
        .map(
          (item) => item.identityHash == account.identityHash
              ? StoredAccount.fromAccount(
                  account,
                ).withCredential(item.credential)
              : item,
        )
        .toList(growable: false);
    await _writeIndex(next);
  }

  Future<void> signOut(String identityHash) async {
    await _storage.delete(key: _credentialKey(identityHash));
    final accounts = await loadAccounts();
    final next = accounts
        .map(
          (item) => item.identityHash == identityHash ? item.signedOut() : item,
        )
        .toList(growable: false);
    await _writeIndex(next);
  }

  Future<void> removeAccount(String identityHash) async {
    await _storage.delete(key: _credentialKey(identityHash));
    final accounts = await loadAccounts();
    await _writeIndex(
      accounts.where((item) => item.identityHash != identityHash).toList(),
    );
  }

  Future<MonitorSettings> loadSettings() async {
    final serialized = await _storage.read(key: _settingsKey);
    if (serialized == null) return const MonitorSettings();
    try {
      return MonitorSettings.fromJson(
        jsonDecode(serialized) as Map<String, dynamic>,
      );
    } catch (_) {
      return const MonitorSettings();
    }
  }

  Future<void> saveSettings(MonitorSettings settings) =>
      _storage.write(key: _settingsKey, value: jsonEncode(settings.toJson()));

  Future<void> _writeIndex(List<StoredAccount> accounts) => _storage.write(
    key: _indexKey,
    value: jsonEncode(accounts.map((item) => item.toMetadata()).toList()),
  );

  SecureCredential? _credentialFromJson(String? serialized) {
    if (serialized == null) return null;
    try {
      final json = jsonDecode(serialized) as Map<String, dynamic>;
      return SecureCredential(
        idToken: json['id_token'] as String,
        accessToken: json['access_token'] as String,
        refreshToken: json['refresh_token'] as String,
      );
    } catch (_) {
      return null;
    }
  }

  Map<String, String> _credentialToJson(SecureCredential credential) => {
    'id_token': credential.idToken,
    'access_token': credential.accessToken,
    'refresh_token': credential.refreshToken,
  };
}

class StoredAccount {
  const StoredAccount({
    required this.identityHash,
    this.email,
    this.plan,
    this.workspaceId,
    this.isFedramp = false,
    required this.loginState,
    this.lastSuccessfulRefresh,
    this.credential,
  });

  final String identityHash;
  final String? email;
  final String? plan;
  final String? workspaceId;
  final bool isFedramp;
  final LoginState loginState;
  final int? lastSuccessfulRefresh;
  final SecureCredential? credential;

  factory StoredAccount.fromAccount(AccountInfo account) => StoredAccount(
    identityHash: account.identityHash,
    email: account.email,
    plan: account.plan,
    workspaceId: account.workspaceId,
    isFedramp: account.isFedramp,
    loginState: account.loginState,
    lastSuccessfulRefresh: account.lastSuccessfulRefresh,
  );

  factory StoredAccount.fromMetadata(Map<String, dynamic> json) =>
      StoredAccount(
        identityHash: json['identity_hash'] as String,
        email: json['email'] as String?,
        plan: json['plan'] as String?,
        workspaceId: json['workspace_id'] as String?,
        isFedramp: json['is_fedramp'] as bool? ?? false,
        loginState: LoginState.values.byName(
          json['login_state'] as String? ?? LoginState.signedOut.name,
        ),
        lastSuccessfulRefresh: json['last_successful_refresh'] as int?,
      );

  AccountInfo get account => AccountInfo(
    identityHash: identityHash,
    email: email,
    plan: plan,
    workspaceId: workspaceId,
    isFedramp: isFedramp,
    loginState: credential == null ? LoginState.signedOut : loginState,
    lastSuccessfulRefresh: lastSuccessfulRefresh,
    credentialStatus: credential == null
        ? CredentialStatus.missing
        : CredentialStatus.available,
  );

  StoredAccount withCredential(SecureCredential? value) => StoredAccount(
    identityHash: identityHash,
    email: email,
    plan: plan,
    workspaceId: workspaceId,
    isFedramp: isFedramp,
    loginState: value == null ? LoginState.signedOut : LoginState.signedIn,
    lastSuccessfulRefresh: lastSuccessfulRefresh,
    credential: value,
  );

  StoredAccount signedOut() => withCredential(null);

  Map<String, Object?> toMetadata() => {
    'identity_hash': identityHash,
    'email': email,
    'plan': plan,
    'workspace_id': workspaceId,
    'is_fedramp': isFedramp,
    'login_state': loginState.name,
    'last_successful_refresh': lastSuccessfulRefresh,
  };
}

enum ThemePreference { system, light, dark }

class MonitorSettings {
  const MonitorSettings({
    this.theme = ThemePreference.system,
    this.refreshMinutes = 15,
    this.showResetCredits = true,
    this.notificationsEnabled = false,
  });

  final ThemePreference theme;
  final int refreshMinutes;
  final bool showResetCredits;
  final bool notificationsEnabled;

  factory MonitorSettings.fromJson(Map<String, dynamic> json) =>
      MonitorSettings(
        theme: ThemePreference.values.byName(
          json['theme'] as String? ?? ThemePreference.system.name,
        ),
        refreshMinutes: switch (json['refresh_minutes']) {
          0 || 5 || 15 || 30 => json['refresh_minutes'] as int,
          _ => 15,
        },
        showResetCredits: json['show_reset_credits'] as bool? ?? true,
        notificationsEnabled: json['notifications_enabled'] as bool? ?? false,
      );

  MonitorSettings copyWith({
    ThemePreference? theme,
    int? refreshMinutes,
    bool? showResetCredits,
    bool? notificationsEnabled,
  }) => MonitorSettings(
    theme: theme ?? this.theme,
    refreshMinutes: refreshMinutes ?? this.refreshMinutes,
    showResetCredits: showResetCredits ?? this.showResetCredits,
    notificationsEnabled: notificationsEnabled ?? this.notificationsEnabled,
  );

  Map<String, Object> toJson() => {
    'theme': theme.name,
    'refresh_minutes': refreshMinutes,
    'show_reset_credits': showResetCredits,
    'notifications_enabled': notificationsEnabled,
  };
}
