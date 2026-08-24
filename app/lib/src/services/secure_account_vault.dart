import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../rust/models.dart';

/// Provider 凭据的唯一持久化位置。
///
/// flutter_secure_storage 在 Android 使用 Keystore，在 Apple 平台使用
/// Keychain，在 Windows 使用受系统保护的凭据存储，在 Linux 使用 Secret
/// Service。账号索引不含 token；它也放在同一安全存储中以减少元数据泄露面。
class SecureAccountVault {
  SecureAccountVault({FlutterSecureStorage? storage})
    : _storage = storage ?? FlutterSecureStorage();

  static const _indexKey = 'aiusage.account_index.v1';
  static const _settingsKey = 'aiusage.settings.v1';

  final FlutterSecureStorage _storage;

  String _credentialKey(String identityHash) =>
      'aiusage.credential.$identityHash.v1';

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
        accounts.add(
          record._withSecret(_secretFromJson(secret, record.provider)),
        );
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
    CredentialSource credentialSource,
  ) async {
    final accounts = await loadAccounts();
    final updated = StoredAccount.fromAccount(
      account,
      credentialSource: credentialSource,
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

  Future<void> saveDeepSeek(
    AccountInfo account,
    String apiKey, {
    String? displayName,
  }) async {
    final accounts = await loadAccounts();
    final updated = StoredAccount.fromAccount(
      account,
      displayName: displayName,
      credentialSource: CredentialSource.apiKey,
    ).withApiKey(apiKey);
    await _storage.write(
      key: _credentialKey(updated.identityHash),
      value: jsonEncode({'type': 'deepseek_api_key', 'api_key': apiKey}),
    );
    await _writeIndex([
      updated,
      ...accounts.where((item) => item.identityHash != updated.identityHash),
    ]);
  }

  Future<void> saveMimo(
    AccountInfo account,
    MimoCredential credential, {
    required CredentialSource credentialSource,
    String? displayName,
  }) async {
    final accounts = await loadAccounts();
    final updated = StoredAccount.fromAccount(
      account,
      displayName: displayName,
      credentialSource: credentialSource,
    ).withMimoCredential(credential);
    await updateMimoCredential(updated.identityHash, credential);
    await _writeIndex([
      updated,
      ...accounts.where((item) => item.identityHash != updated.identityHash),
    ]);
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

  Future<void> updateMimoCredential(
    String identityHash,
    MimoCredential credential,
  ) => _storage.write(
    key: _credentialKey(identityHash),
    value: jsonEncode({
      'type': 'mimo_session',
      'user_id': credential.userId,
      'pass_token': credential.passToken,
      'service_token': credential.serviceToken,
      'service_slh': credential.serviceSlh,
      'service_ph': credential.servicePh,
    }),
  );

  Future<void> updateAccount(AccountInfo account) async {
    final accounts = await loadAccounts();
    final next = accounts
        .map(
          (item) => item.identityHash == account.identityHash
              ? StoredAccount.fromAccount(
                  account,
                  displayName: item.displayName,
                  credentialSource: item.credentialSource,
                )._withSecret(item._secret)
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

  _StoredSecret? _secretFromJson(String? serialized, ProviderKind provider) {
    if (serialized == null) return null;
    try {
      final json = jsonDecode(serialized) as Map<String, dynamic>;
      final type = json['type'] as String?;
      if (type == 'deepseek_api_key' || provider == ProviderKind.deepSeek) {
        return _StoredSecret(apiKey: json['api_key'] as String);
      }
      if (type == 'mimo_session' || provider == ProviderKind.mimo) {
        return _StoredSecret(
          mimoCredential: MimoCredential(
            userId: json['user_id'] as String,
            passToken: json['pass_token'] as String,
            serviceToken: json['service_token'] as String,
            serviceSlh: json['service_slh'] as String,
            servicePh: json['service_ph'] as String,
          ),
        );
      }
      // v0.1.0 credentials did not carry a type discriminator.
      return _StoredSecret(
        codexCredential: SecureCredential(
          idToken: json['id_token'] as String,
          accessToken: json['access_token'] as String,
          refreshToken: json['refresh_token'] as String,
        ),
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
    this.provider = ProviderKind.codex,
    this.displayName,
    this.email,
    this.plan,
    this.workspaceId,
    this.isFedramp = false,
    required this.loginState,
    this.lastSuccessfulRefresh,
    this.credential,
    this.apiKey,
    this.mimoCredential,
    this.credentialSource = CredentialSource.unknown,
  });

  final String identityHash;
  final ProviderKind provider;
  final String? displayName;
  final String? email;
  final String? plan;
  final String? workspaceId;
  final bool isFedramp;
  final LoginState loginState;
  final int? lastSuccessfulRefresh;
  final SecureCredential? credential;
  final String? apiKey;
  final MimoCredential? mimoCredential;
  final CredentialSource credentialSource;

  factory StoredAccount.fromAccount(
    AccountInfo account, {
    String? displayName,
    CredentialSource credentialSource = CredentialSource.unknown,
  }) => StoredAccount(
    identityHash: account.identityHash,
    provider: account.provider,
    displayName: displayName,
    email: account.email,
    plan: account.plan,
    workspaceId: account.workspaceId,
    isFedramp: account.isFedramp,
    loginState: account.loginState,
    lastSuccessfulRefresh: account.lastSuccessfulRefresh,
    credentialSource: credentialSource,
  );

  factory StoredAccount.fromMetadata(Map<String, dynamic> json) =>
      StoredAccount(
        identityHash: json['identity_hash'] as String,
        provider: _providerFromName(json['provider'] as String?),
        displayName: json['display_name'] as String?,
        email: json['email'] as String?,
        plan: json['plan'] as String?,
        workspaceId: json['workspace_id'] as String?,
        isFedramp: json['is_fedramp'] as bool? ?? false,
        loginState: LoginState.values.byName(
          json['login_state'] as String? ?? LoginState.signedOut.name,
        ),
        lastSuccessfulRefresh: json['last_successful_refresh'] as int?,
        credentialSource: _credentialSourceFromName(
          json['credential_source'] as String?,
        ),
      );

  AccountInfo get account => AccountInfo(
    identityHash: identityHash,
    provider: provider,
    email: email,
    plan: plan,
    workspaceId: workspaceId,
    isFedramp: isFedramp,
    loginState: !hasCredential ? LoginState.signedOut : loginState,
    lastSuccessfulRefresh: lastSuccessfulRefresh,
    credentialStatus: !hasCredential
        ? CredentialStatus.missing
        : CredentialStatus.available,
  );

  StoredAccount withCredential(SecureCredential? value) => StoredAccount(
    identityHash: identityHash,
    provider: provider,
    displayName: displayName,
    email: email,
    plan: plan,
    workspaceId: workspaceId,
    isFedramp: isFedramp,
    loginState: value == null ? LoginState.signedOut : LoginState.signedIn,
    lastSuccessfulRefresh: lastSuccessfulRefresh,
    credential: value,
    credentialSource: credentialSource,
  );

  StoredAccount withApiKey(String? value) =>
      _copyWithSecret(apiKey: value, hasSecret: value != null);

  StoredAccount withMimoCredential(MimoCredential? value) =>
      _copyWithSecret(mimoCredential: value, hasSecret: value != null);

  StoredAccount withCredentials({
    SecureCredential? codexCredential,
    String? apiKey,
    MimoCredential? mimoCredential,
  }) => _copyWithSecret(
    credential: codexCredential,
    apiKey: apiKey,
    mimoCredential: mimoCredential,
    hasSecret:
        codexCredential != null || apiKey != null || mimoCredential != null,
  );

  StoredAccount _withSecret(_StoredSecret? value) => _copyWithSecret(
    credential: value?.codexCredential,
    apiKey: value?.apiKey,
    mimoCredential: value?.mimoCredential,
    hasSecret: value != null,
  );

  _StoredSecret? get _secret => hasCredential
      ? _StoredSecret(
          codexCredential: credential,
          apiKey: apiKey,
          mimoCredential: mimoCredential,
        )
      : null;

  bool get hasCredential =>
      credential != null || apiKey != null || mimoCredential != null;

  StoredAccount _copyWithSecret({
    SecureCredential? credential,
    String? apiKey,
    MimoCredential? mimoCredential,
    required bool hasSecret,
  }) => StoredAccount(
    identityHash: identityHash,
    provider: provider,
    displayName: displayName,
    email: email,
    plan: plan,
    workspaceId: workspaceId,
    isFedramp: isFedramp,
    loginState: hasSecret ? LoginState.signedIn : LoginState.signedOut,
    lastSuccessfulRefresh: lastSuccessfulRefresh,
    credential: credential,
    apiKey: apiKey,
    mimoCredential: mimoCredential,
    credentialSource: credentialSource,
  );

  StoredAccount signedOut() => withCredential(null);

  Map<String, Object?> toMetadata() => {
    'identity_hash': identityHash,
    'provider': provider.name,
    'display_name': displayName,
    'email': email,
    'plan': plan,
    'workspace_id': workspaceId,
    'is_fedramp': isFedramp,
    'login_state': loginState.name,
    'last_successful_refresh': lastSuccessfulRefresh,
    'credential_source': credentialSource.name,
  };
}

enum CredentialSource {
  deviceCode,
  authJson,
  apiKey,
  xiaomiPassword,
  xiaomiWeb,
  unknown,
}

ProviderKind _providerFromName(String? value) {
  for (final provider in ProviderKind.values) {
    if (provider.name == value) return provider;
  }
  return ProviderKind.codex;
}

class _StoredSecret {
  const _StoredSecret({this.codexCredential, this.apiKey, this.mimoCredential});

  final SecureCredential? codexCredential;
  final String? apiKey;
  final MimoCredential? mimoCredential;
}

CredentialSource _credentialSourceFromName(String? value) {
  for (final source in CredentialSource.values) {
    if (source.name == value) return source;
  }
  return CredentialSource.unknown;
}

enum ThemePreference { system, light, dark }

enum LocalePreference { system, english, simplifiedChinese }

class MonitorSettings {
  const MonitorSettings({
    this.theme = ThemePreference.system,
    this.locale = LocalePreference.system,
    this.refreshMinutes = 15,
    this.showResetCredits = true,
    this.notificationsEnabled = false,
    this.dynamicColorEnabled = false,
    this.demoModeEnabled = false,
    this.demoSeed = 0,
    this.backgroundRefreshEnabled = false,
  });

  final ThemePreference theme;
  final LocalePreference locale;
  final int refreshMinutes;
  final bool showResetCredits;
  final bool notificationsEnabled;
  final bool dynamicColorEnabled;
  final bool demoModeEnabled;
  final int demoSeed;
  final bool backgroundRefreshEnabled;

  factory MonitorSettings.fromJson(Map<String, dynamic> json) =>
      MonitorSettings(
        theme: ThemePreference.values.byName(
          json['theme'] as String? ?? ThemePreference.system.name,
        ),
        locale: LocalePreference.values.byName(
          json['locale'] as String? ?? LocalePreference.system.name,
        ),
        refreshMinutes: switch (json['refresh_minutes']) {
          0 || 5 || 15 || 30 => json['refresh_minutes'] as int,
          _ => 15,
        },
        showResetCredits: json['show_reset_credits'] as bool? ?? true,
        notificationsEnabled: json['notifications_enabled'] as bool? ?? false,
        dynamicColorEnabled: json['dynamic_color_enabled'] as bool? ?? false,
        demoModeEnabled: json['demo_mode_enabled'] as bool? ?? false,
        demoSeed: json['demo_seed'] as int? ?? 0,
        backgroundRefreshEnabled:
            json['background_refresh_enabled'] as bool? ?? false,
      );

  MonitorSettings copyWith({
    ThemePreference? theme,
    LocalePreference? locale,
    int? refreshMinutes,
    bool? showResetCredits,
    bool? notificationsEnabled,
    bool? dynamicColorEnabled,
    bool? demoModeEnabled,
    int? demoSeed,
    bool? backgroundRefreshEnabled,
  }) => MonitorSettings(
    theme: theme ?? this.theme,
    locale: locale ?? this.locale,
    refreshMinutes: refreshMinutes ?? this.refreshMinutes,
    showResetCredits: showResetCredits ?? this.showResetCredits,
    notificationsEnabled: notificationsEnabled ?? this.notificationsEnabled,
    dynamicColorEnabled: dynamicColorEnabled ?? this.dynamicColorEnabled,
    demoModeEnabled: demoModeEnabled ?? this.demoModeEnabled,
    demoSeed: demoSeed ?? this.demoSeed,
    backgroundRefreshEnabled:
        backgroundRefreshEnabled ?? this.backgroundRefreshEnabled,
  );

  Map<String, Object> toJson() => {
    'theme': theme.name,
    'locale': locale.name,
    'refresh_minutes': refreshMinutes,
    'show_reset_credits': showResetCredits,
    'notifications_enabled': notificationsEnabled,
    'dynamic_color_enabled': dynamicColorEnabled,
    'demo_mode_enabled': demoModeEnabled,
    'demo_seed': demoSeed,
    'background_refresh_enabled': backgroundRefreshEnabled,
  };
}
