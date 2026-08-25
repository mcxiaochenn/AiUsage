//! Application service used by the flutter_rust_bridge API.

use std::collections::HashMap;
use std::sync::{Mutex, OnceLock};

use reqwest::Client;
use uuid::Uuid;

use crate::api::codex::{ApiFailure, CodexProvider, HttpObservation};
use crate::api::deepseek::{DeepSeekProvider, parse_balance};
use crate::api::mimo::{MimoProvider, parse_balance as parse_mimo_balance, parse_token_plan};
use crate::auth::{self, AuthError, DeviceCodePoll, PendingDeviceCode};
use crate::history::HistoryRepository;
use crate::models::{
    AccountDetails, AccountInfo, DeviceCodeLoginComplete, DeviceCodeLoginPoll,
    DeviceCodeLoginStart, HistoryPoint, MimoCredential, MimoLoginResult, ProfileUsage,
    ProviderKind, SecureCredential, SyncLogEntry, SyncTrigger, UsageResult, UsageState,
};
use crate::normalize::{
    RawWhamUsage, parse_account_details, parse_credit_details, parse_profile_usage,
};

static CORE: OnceLock<CoreService> = OnceLock::new();

struct CoreService {
    history: Mutex<HistoryRepository>,
    provider: CodexProvider,
    deepseek_provider: DeepSeekProvider,
    mimo_provider: MimoProvider,
    oauth_client: Client,
    pending_device_logins: Mutex<HashMap<String, PendingDeviceCode>>,
    mimo_sessions: tokio::sync::Mutex<HashMap<String, MimoCredential>>,
}

impl CoreService {
    fn create(database_path: &str) -> Result<Self, String> {
        let provider = CodexProvider::production()?;
        let deepseek_provider = DeepSeekProvider::production()?;
        let mimo_provider = MimoProvider::production()?;
        let oauth_client = Client::builder()
            .connect_timeout(std::time::Duration::from_secs(12))
            .timeout(std::time::Duration::from_secs(20))
            .build()
            .map_err(|error| format!("OAuth client setup failed: {error}"))?;
        Ok(Self {
            history: Mutex::new(HistoryRepository::open(database_path)?),
            provider,
            deepseek_provider,
            mimo_provider,
            oauth_client,
            pending_device_logins: Mutex::new(HashMap::new()),
            mimo_sessions: tokio::sync::Mutex::new(HashMap::new()),
        })
    }
}

pub async fn refresh_deepseek_usage(api_key: String, trigger: SyncTrigger) -> UsageResult {
    let key = api_key.trim();
    if key.is_empty() || key.contains(['\r', '\n']) {
        return result_without_snapshot(
            UsageState::AuthExpired,
            "DeepSeek API key is invalid".to_string(),
        );
    }
    let service = match core() {
        Ok(service) => service,
        Err(error) => return result_without_snapshot(UsageState::ServerError, error),
    };
    let identity_hash = auth::provider_identity_hash("deepseek", key);
    let mut account = AccountInfo {
        provider: ProviderKind::DeepSeek,
        identity_hash: identity_hash.clone(),
        email: None,
        plan: Some("API".to_string()),
        workspace_id: None,
        is_fedramp: false,
        login_state: crate::models::LoginState::SignedIn,
        last_successful_refresh: None,
        credential_status: crate::models::CredentialStatus::Available,
    };
    let observation = service.deepseek_provider.balance_json(key).await;
    if let Some(failure) = observation.failure.as_ref() {
        record_observation(
            service,
            &identity_hash,
            trigger,
            &observation,
            api_failure_label(failure),
        );
        return cached_failure(
            service,
            account,
            api_failure_state(failure),
            provider_failure_message("DeepSeek", failure),
            None,
            retry_after(failure),
        );
    }
    let fetched_at = auth::now_unix();
    let (available, balances, partial) = match parse_balance(&observation.body) {
        Ok(value) => value,
        Err(error) => {
            record_observation_with_error_kind(
                service,
                &identity_hash,
                trigger,
                &observation,
                "parse_error",
                Some("schema_mismatch"),
            );
            return cached_failure(service, account, UsageState::ParseError, error, None, None);
        }
    };
    account.last_successful_refresh = Some(fetched_at);
    let snapshot = crate::models::UsageSnapshot {
        account,
        windows: Vec::new(),
        balances,
        provider_quotas: Vec::new(),
        reset_credits_available: None,
        reset_credits: None,
        credits: None,
        fetched_at,
    };
    let cache_error = service
        .history
        .lock()
        .map_err(|_| "Quota history is unavailable".to_string())
        .and_then(|mut history| history.record_snapshot(&snapshot))
        .err();
    record_observation(
        service,
        &identity_hash,
        trigger,
        &observation,
        if partial { "partial" } else { "fresh" },
    );
    UsageResult {
        snapshot: Some(snapshot),
        state: UsageState::Fresh,
        showing_cached_data: false,
        message: cache_error.or_else(|| {
            partial
                .then(|| "Some DeepSeek balance entries were ignored".to_string())
                .or_else(|| {
                    (!available).then(|| "DeepSeek reports this account unavailable".to_string())
                })
        }),
        retry_after_seconds: None,
        updated_credential: None,
        updated_mimo_credential: None,
    }
}

pub async fn begin_mimo_login(
    username: String,
    password: String,
) -> Result<MimoLoginResult, String> {
    core()?.mimo_provider.login(username, password).await
}

pub fn complete_mimo_web_login(
    account_cookie: String,
    platform_cookie: String,
) -> Result<MimoLoginResult, String> {
    core()?
        .mimo_provider
        .credential_from_web_cookies(&account_cookie, &platform_cookie)
}

pub async fn refresh_mimo_usage(credential: MimoCredential, trigger: SyncTrigger) -> UsageResult {
    let service = match core() {
        Ok(service) => service,
        Err(error) => return result_without_snapshot(UsageState::ServerError, error),
    };
    let identity_hash = auth::provider_identity_hash("mimo", &credential.user_id);
    let mut effective = credential;
    let mut updated = None;
    let mut balance_observation = service.mimo_provider.balance_json(&effective).await;
    if matches!(balance_observation.failure, Some(ApiFailure::Unauthorized)) {
        // Serialize renewal per process. A second foreground/background caller
        // first reuses the session produced by the first one instead of
        // performing another SSO exchange.
        let mut sessions = service.mimo_sessions.lock().await;
        if let Some(current) = sessions.get(&identity_hash).cloned() {
            let current_observation = service.mimo_provider.balance_json(&current).await;
            if current_observation.failure.is_none() {
                effective = current.clone();
                updated = Some(current);
                balance_observation = current_observation;
            }
        }
        if matches!(balance_observation.failure, Some(ApiFailure::Unauthorized)) {
            match service.mimo_provider.renew(&effective).await {
                Ok(value) => {
                    effective = value.clone();
                    sessions.insert(identity_hash.clone(), value.clone());
                    updated = Some(value);
                    balance_observation = service.mimo_provider.balance_json(&effective).await;
                }
                Err(_) => {
                    drop(sessions);
                    record_observation(
                        service,
                        &identity_hash,
                        trigger,
                        &balance_observation,
                        "reauthentication_required",
                    );
                    return cached_mimo_failure(
                        service,
                        mimo_account(&effective.user_id, None),
                        UsageState::AuthExpired,
                        "MiMo requires interactive sign-in".to_string(),
                        None,
                    );
                }
            }
        }
        drop(sessions);
    }
    let detail_observation = service
        .mimo_provider
        .token_plan_detail_json(&effective)
        .await;
    let usage_observation = service
        .mimo_provider
        .token_plan_usage_json(&effective)
        .await;

    let balances = if balance_observation.failure.is_none() {
        parse_mimo_balance(&balance_observation.body).ok()
    } else {
        None
    };
    let quotas = if usage_observation.failure.is_none() {
        parse_token_plan(
            detail_observation
                .failure
                .is_none()
                .then_some(detail_observation.body.as_str()),
            &usage_observation.body,
        )
        .ok()
    } else {
        None
    };

    record_mimo_observation(
        service,
        &identity_hash,
        trigger,
        &balance_observation,
        balances.is_some(),
    );
    record_mimo_observation(
        service,
        &identity_hash,
        trigger,
        &detail_observation,
        detail_observation.failure.is_none(),
    );
    record_mimo_observation(
        service,
        &identity_hash,
        trigger,
        &usage_observation,
        quotas.is_some(),
    );

    if balances.is_none() && quotas.is_none() {
        let failure = balance_observation
            .failure
            .as_ref()
            .or(usage_observation.failure.as_ref());
        let state = failure
            .map(api_failure_state)
            .unwrap_or(UsageState::ParseError);
        let message = failure
            .map(|failure| provider_failure_message("MiMo", failure))
            .unwrap_or_else(|| "MiMo response could not be decoded".to_string());
        return cached_mimo_failure(
            service,
            mimo_account(&effective.user_id, None),
            state,
            message,
            updated,
        );
    }

    let fetched_at = auth::now_unix();
    let mut account = mimo_account(&effective.user_id, Some(fetched_at));
    account.credential_status = crate::models::CredentialStatus::Available;
    let partial = balances.is_none() || quotas.is_none();
    let snapshot = crate::models::UsageSnapshot {
        account,
        windows: Vec::new(),
        balances: balances.unwrap_or_default(),
        provider_quotas: quotas.unwrap_or_default(),
        reset_credits_available: None,
        reset_credits: None,
        credits: None,
        fetched_at,
    };
    let cache_error = service
        .history
        .lock()
        .map_err(|_| "Quota history is unavailable".to_string())
        .and_then(|mut history| history.record_snapshot(&snapshot))
        .err();
    UsageResult {
        snapshot: Some(snapshot),
        state: UsageState::Fresh,
        showing_cached_data: false,
        message: cache_error.or_else(|| {
            partial.then(|| "Some MiMo account data is temporarily unavailable".to_string())
        }),
        retry_after_seconds: None,
        updated_credential: None,
        updated_mimo_credential: updated,
    }
}

fn mimo_account(user_id: &str, refreshed_at: Option<i64>) -> AccountInfo {
    AccountInfo {
        provider: ProviderKind::Mimo,
        identity_hash: auth::provider_identity_hash("mimo", user_id),
        email: None,
        plan: Some("MiMo".to_string()),
        workspace_id: None,
        is_fedramp: false,
        login_state: crate::models::LoginState::SignedIn,
        last_successful_refresh: refreshed_at,
        credential_status: crate::models::CredentialStatus::Available,
    }
}

fn cached_mimo_failure(
    service: &CoreService,
    account: AccountInfo,
    state: UsageState,
    message: String,
    updated_mimo_credential: Option<MimoCredential>,
) -> UsageResult {
    let snapshot = service
        .history
        .lock()
        .ok()
        .and_then(|history| history.latest_snapshot(&account).ok())
        .flatten();
    UsageResult {
        showing_cached_data: snapshot.is_some(),
        snapshot,
        state,
        message: Some(message),
        retry_after_seconds: None,
        updated_credential: None,
        updated_mimo_credential,
    }
}

fn record_mimo_observation(
    service: &CoreService,
    identity_hash: &str,
    trigger: SyncTrigger,
    observation: &HttpObservation,
    parsed: bool,
) {
    let (state, error) = if let Some(failure) = observation.failure.as_ref() {
        (api_failure_label(failure), Some(api_failure_label(failure)))
    } else if parsed {
        ("fresh", None)
    } else {
        ("parse_error", Some("schema_mismatch"))
    };
    record_observation_with_error_kind(service, identity_hash, trigger, observation, state, error);
}

pub fn initialize(database_path: String) -> Result<(), String> {
    if CORE.get().is_some() {
        return Ok(());
    }
    let service = CoreService::create(&database_path)?;
    CORE.set(service)
        .map_err(|_| "Core service is already initialized".to_string())
}

pub async fn begin_device_login() -> Result<DeviceCodeLoginStart, String> {
    let service = core()?;
    let pending = auth::start_device_code(&service.oauth_client)
        .await
        .map_err(auth_error_message)?;
    let login_id = Uuid::new_v4().to_string();
    service
        .pending_device_logins
        .lock()
        .map_err(|_| "Device login state is unavailable".to_string())?
        .insert(login_id.clone(), pending.clone());
    Ok(DeviceCodeLoginStart {
        login_id,
        verification_url: pending.verification_url,
        user_code: pending.user_code,
        poll_interval_seconds: pending.interval_seconds,
    })
}

pub async fn poll_device_login(login_id: String) -> Result<DeviceCodeLoginPoll, String> {
    let service = core()?;
    let pending = service
        .pending_device_logins
        .lock()
        .map_err(|_| "Device login state is unavailable".to_string())?
        .get(&login_id)
        .cloned()
        .ok_or_else(|| "This device login has expired or was cancelled".to_string())?;
    match auth::poll_device_code(&service.oauth_client, &pending)
        .await
        .map_err(auth_error_message)?
    {
        DeviceCodePoll::Pending => Ok(DeviceCodeLoginPoll {
            pending: true,
            completed: None,
        }),
        DeviceCodePoll::Authorized(credential) => {
            service
                .pending_device_logins
                .lock()
                .map_err(|_| "Device login state is unavailable".to_string())?
                .remove(&login_id);
            let account = auth::account_from_credential(&credential).map_err(auth_error_message)?;
            Ok(DeviceCodeLoginPoll {
                pending: false,
                completed: Some(DeviceCodeLoginComplete {
                    credential,
                    account,
                }),
            })
        }
    }
}

pub fn cancel_device_login(login_id: String) -> Result<(), String> {
    core()?
        .pending_device_logins
        .lock()
        .map_err(|_| "Device login state is unavailable".to_string())?
        .remove(&login_id);
    Ok(())
}

pub fn import_codex_auth_json(content: Vec<u8>) -> Result<DeviceCodeLoginComplete, String> {
    let credential = auth::import_auth_json(&content).map_err(auth_error_message)?;
    let account = auth::account_from_credential(&credential).map_err(auth_error_message)?;
    Ok(DeviceCodeLoginComplete {
        credential,
        account,
    })
}

pub async fn refresh_usage(credential: SecureCredential, trigger: SyncTrigger) -> UsageResult {
    let original_account = match auth::account_from_credential(&credential) {
        Ok(account) => account,
        Err(_) => {
            return no_identity_result(UsageState::AuthExpired, "Credential identity is invalid");
        }
    };
    let service = match core() {
        Ok(service) => service,
        Err(message) => return result_without_snapshot(UsageState::ServerError, message),
    };

    let mut effective_credential = credential;
    let mut updated_credential = None;
    if auth::access_token_needs_refresh(&effective_credential) {
        match auth::refresh_credential(&service.oauth_client, &effective_credential).await {
            Ok(refreshed) => {
                effective_credential = refreshed.clone();
                updated_credential = Some(refreshed);
            }
            Err(error) => {
                return cached_failure(
                    service,
                    original_account,
                    auth_error_state(&error),
                    auth_error_message(error),
                    None,
                    None,
                );
            }
        }
    }

    let mut account = match auth::account_from_credential(&effective_credential) {
        Ok(account) => account,
        Err(_) => original_account,
    };
    if updated_credential.is_some() {
        account.last_successful_refresh = Some(auth::now_unix());
    }

    let mut observation = service
        .provider
        .usage_json(
            &effective_credential,
            account.workspace_id.as_deref(),
            account.is_fedramp,
        )
        .await;
    record_observation(
        service,
        &account.identity_hash,
        trigger,
        &observation,
        observation
            .failure
            .as_ref()
            .map(api_failure_label)
            .unwrap_or("fresh"),
    );
    if matches!(observation.failure, Some(ApiFailure::Unauthorized)) {
        match auth::refresh_credential(&service.oauth_client, &effective_credential).await {
            Ok(refreshed) => {
                effective_credential = refreshed.clone();
                updated_credential = Some(refreshed);
                account = auth::account_from_credential(&effective_credential).unwrap_or(account);
                account.last_successful_refresh = Some(auth::now_unix());
                observation = service
                    .provider
                    .usage_json(
                        &effective_credential,
                        account.workspace_id.as_deref(),
                        account.is_fedramp,
                    )
                    .await;
                record_observation(
                    service,
                    &account.identity_hash,
                    trigger,
                    &observation,
                    observation
                        .failure
                        .as_ref()
                        .map(api_failure_label)
                        .unwrap_or("fresh"),
                );
            }
            Err(error) => {
                return cached_failure(
                    service,
                    account,
                    auth_error_state(&error),
                    auth_error_message(error),
                    None,
                    None,
                );
            }
        }
    }
    if let Some(failure) = observation.failure.as_ref() {
        return cached_failure(
            service,
            account,
            api_failure_state(failure),
            api_failure_message(failure),
            updated_credential,
            retry_after(failure),
        );
    }
    let usage_json = observation.body;

    let fetched_at = auth::now_unix();
    let raw = match RawWhamUsage::parse(&usage_json) {
        Ok(raw) => raw,
        Err(_) => {
            return cached_failure(
                service,
                account,
                UsageState::ParseError,
                "OpenAI returned an unsupported Usage response".to_string(),
                updated_credential,
                None,
            );
        }
    };
    account.last_successful_refresh = Some(fetched_at);
    let mut snapshot = raw.normalize(account.clone(), fetched_at);

    // Details are optional. A failure here never discards `available_count`
    // already carried by the usage response.
    let credit_observation = service
        .provider
        .reset_credits_json(
            &effective_credential,
            account.workspace_id.as_deref(),
            account.is_fedramp,
        )
        .await;
    record_observation(
        service,
        &account.identity_hash,
        trigger,
        &credit_observation,
        credit_observation
            .failure
            .as_ref()
            .map(api_failure_label)
            .unwrap_or("fresh"),
    );
    if credit_observation.failure.is_none()
        && let Ok(details) = parse_credit_details(&credit_observation.body)
    {
        if details.0.is_some() {
            snapshot.reset_credits_available = details.0;
        }
        snapshot.reset_credits = Some(details.1);
    }

    let history_message = service
        .history
        .lock()
        .map_err(|_| "Quota history is unavailable".to_string())
        .and_then(|mut history| history.record_snapshot(&snapshot))
        .err();
    UsageResult {
        snapshot: Some(snapshot),
        state: UsageState::Fresh,
        showing_cached_data: false,
        message: history_message,
        retry_after_seconds: None,
        updated_credential,
        updated_mimo_credential: None,
    }
}

pub async fn fetch_profile_usage(
    credential: SecureCredential,
    trigger: SyncTrigger,
) -> Result<ProfileUsage, String> {
    let service = core()?;
    let account = auth::account_from_credential(&credential).map_err(auth_error_message)?;
    let observation = service
        .provider
        .profile_json(
            &credential,
            account.workspace_id.as_deref(),
            account.is_fedramp,
        )
        .await;
    handle_profile_observation(
        service,
        &account.identity_hash,
        trigger,
        &observation,
        auth::now_unix(),
    )
}

pub fn cached_profile_usage(account_identity_hash: String) -> Result<Option<ProfileUsage>, String> {
    core()?
        .history
        .lock()
        .map_err(|_| "Profile cache is unavailable".to_string())?
        .profile_usage(&account_identity_hash)
}

pub async fn fetch_account_details(
    credential: SecureCredential,
    trigger: SyncTrigger,
) -> Result<AccountDetails, String> {
    let service = core()?;
    let account = auth::account_from_credential(&credential).map_err(auth_error_message)?;
    let observation = service.provider.account_details_json(&credential).await;
    record_observation(
        service,
        &account.identity_hash,
        trigger,
        &observation,
        observation
            .failure
            .as_ref()
            .map(api_failure_label)
            .unwrap_or("fresh"),
    );
    if let Some(failure) = observation.failure.as_ref() {
        return Err(api_failure_message(failure));
    }
    let details = parse_account_details(&observation.body, auth::now_unix())?;
    service
        .history
        .lock()
        .map_err(|_| "Account details cache is unavailable".to_string())?
        .save_account_details(&account.identity_hash, &details)?;
    Ok(details)
}

pub fn cached_account_details(
    account_identity_hash: String,
) -> Result<Option<AccountDetails>, String> {
    core()?
        .history
        .lock()
        .map_err(|_| "Account details cache is unavailable".to_string())?
        .account_details(&account_identity_hash)
}

pub fn sync_logs() -> Result<Vec<SyncLogEntry>, String> {
    core()?
        .history
        .lock()
        .map_err(|_| "Diagnostics are unavailable".to_string())?
        .sync_logs()
}

pub fn clear_sync_logs() -> Result<(), String> {
    core()?
        .history
        .lock()
        .map_err(|_| "Diagnostics are unavailable".to_string())?
        .clear_sync_logs()
}

pub fn purge_all_data() -> Result<(), String> {
    core()?
        .history
        .lock()
        .map_err(|_| "Local data is unavailable".to_string())?
        .purge_all_data()
}

pub fn cached_usage(account: AccountInfo) -> Result<UsageResult, String> {
    let snapshot = core()?
        .history
        .lock()
        .map_err(|_| "Quota history is unavailable".to_string())?
        .latest_snapshot(&account)?;
    Ok(UsageResult {
        showing_cached_data: snapshot.is_some(),
        snapshot,
        state: UsageState::Stale,
        message: None,
        retry_after_seconds: None,
        updated_credential: None,
        updated_mimo_credential: None,
    })
}

pub fn history(account_identity_hash: String, since: i64) -> Result<Vec<HistoryPoint>, String> {
    core()?
        .history
        .lock()
        .map_err(|_| "Quota history is unavailable".to_string())?
        .history(&account_identity_hash, since)
}

pub fn remove_account_data(account_identity_hash: String) -> Result<(), String> {
    core()?
        .history
        .lock()
        .map_err(|_| "Quota history is unavailable".to_string())?
        .remove_account(&account_identity_hash)
}

fn core() -> Result<&'static CoreService, String> {
    CORE.get()
        .ok_or_else(|| "Core has not been initialized".to_string())
}

fn record_observation(
    service: &CoreService,
    identity_hash: &str,
    trigger: SyncTrigger,
    observation: &HttpObservation,
    result_state: &str,
) {
    let error_kind = observation.failure.as_ref().map(api_failure_label);
    record_observation_with_error_kind(
        service,
        identity_hash,
        trigger,
        observation,
        result_state,
        error_kind,
    );
}

fn record_observation_with_error_kind(
    service: &CoreService,
    identity_hash: &str,
    trigger: SyncTrigger,
    observation: &HttpObservation,
    result_state: &str,
    error_kind: Option<&str>,
) {
    let started_at = auth::now_unix() - (observation.duration_ms / 1000);
    if let Ok(history) = service.history.lock() {
        let _ = history.record_sync_log(
            identity_hash,
            trigger,
            &observation.endpoint,
            started_at,
            observation.duration_ms,
            observation.status_code,
            result_state,
            error_kind,
            &observation.body,
        );
    }
}

fn handle_profile_observation(
    service: &CoreService,
    identity_hash: &str,
    trigger: SyncTrigger,
    observation: &HttpObservation,
    fetched_at: i64,
) -> Result<ProfileUsage, String> {
    if let Some(failure) = observation.failure.as_ref() {
        record_observation(
            service,
            identity_hash,
            trigger,
            observation,
            api_failure_label(failure),
        );
        return Err(api_failure_message(failure));
    }

    let profile = match parse_profile_usage(&observation.body, fetched_at) {
        Ok(profile) => profile,
        Err(error) => {
            record_observation_with_error_kind(
                service,
                identity_hash,
                trigger,
                observation,
                "parse_error",
                Some(profile_parse_error_kind(&error)),
            );
            return Err(error);
        }
    };
    let result_state = if profile.daily_usage_buckets.is_empty() {
        "empty"
    } else {
        "fresh"
    };
    service
        .history
        .lock()
        .map_err(|_| "Profile cache is unavailable".to_string())?
        .save_profile_usage(identity_hash, &profile)?;
    record_observation_with_error_kind(
        service,
        identity_hash,
        trigger,
        observation,
        result_state,
        None,
    );
    Ok(profile)
}

fn profile_parse_error_kind(error: &str) -> &'static str {
    if error.starts_with("backend_stats_error:") {
        "backend_stats_error"
    } else {
        "schema_mismatch"
    }
}

fn api_failure_label(failure: &ApiFailure) -> &'static str {
    match failure {
        ApiFailure::Unauthorized => "unauthorized",
        ApiFailure::RateLimited(_) => "rate_limited",
        ApiFailure::Server => "server_error",
        ApiFailure::Offline => "offline",
        ApiFailure::Other => "rejected",
    }
}

fn cached_failure(
    service: &CoreService,
    account: AccountInfo,
    state: UsageState,
    message: String,
    updated_credential: Option<SecureCredential>,
    retry_after_seconds: Option<i64>,
) -> UsageResult {
    let snapshot = service
        .history
        .lock()
        .ok()
        .and_then(|history| history.latest_snapshot(&account).ok())
        .flatten();
    UsageResult {
        showing_cached_data: snapshot.is_some(),
        snapshot,
        state,
        message: Some(message),
        retry_after_seconds,
        updated_credential,
        updated_mimo_credential: None,
    }
}

fn no_identity_result(state: UsageState, message: &str) -> UsageResult {
    result_without_snapshot(state, message.to_string())
}

fn result_without_snapshot(state: UsageState, message: String) -> UsageResult {
    UsageResult {
        snapshot: None,
        state,
        showing_cached_data: false,
        message: Some(message),
        retry_after_seconds: None,
        updated_credential: None,
        updated_mimo_credential: None,
    }
}

fn auth_error_state(error: &AuthError) -> UsageState {
    match error {
        AuthError::Permanent => UsageState::AuthExpired,
        AuthError::Transport => UsageState::Offline,
        _ => UsageState::ServerError,
    }
}

fn auth_error_message(error: AuthError) -> String {
    error.to_string()
}

fn api_failure_state(failure: &ApiFailure) -> UsageState {
    match failure {
        ApiFailure::Unauthorized => UsageState::AuthExpired,
        ApiFailure::RateLimited(_) => UsageState::RateLimited,
        ApiFailure::Server | ApiFailure::Other => UsageState::ServerError,
        ApiFailure::Offline => UsageState::Offline,
    }
}

fn api_failure_message(failure: &ApiFailure) -> String {
    match failure {
        ApiFailure::Unauthorized => "OpenAI rejected the credential".to_string(),
        ApiFailure::RateLimited(Some(seconds)) => {
            format!("OpenAI rate limited this request; retry after {seconds}s")
        }
        ApiFailure::RateLimited(None) => "OpenAI rate limited this request".to_string(),
        ApiFailure::Server => "OpenAI service is temporarily unavailable".to_string(),
        ApiFailure::Offline => "Unable to reach OpenAI".to_string(),
        ApiFailure::Other => "OpenAI rejected the Usage request".to_string(),
    }
}

fn provider_failure_message(provider: &str, failure: &ApiFailure) -> String {
    match failure {
        ApiFailure::Unauthorized => format!("{provider} rejected the credential"),
        ApiFailure::RateLimited(Some(seconds)) => {
            format!("{provider} rate limited this request; retry after {seconds}s")
        }
        ApiFailure::RateLimited(None) => format!("{provider} rate limited this request"),
        ApiFailure::Server => format!("{provider} is temporarily unavailable"),
        ApiFailure::Offline => format!("Unable to reach {provider}"),
        ApiFailure::Other => format!("{provider} rejected the request"),
    }
}

fn retry_after(failure: &ApiFailure) -> Option<i64> {
    match failure {
        ApiFailure::RateLimited(seconds) => *seconds,
        _ => None,
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::models::{
        CredentialStatus, DailyTokenBucket, LoginState, QuotaWindow, TokenUsageSummary,
        UsageSnapshot,
    };

    fn profile(tokens: i64, fetched_at: i64) -> ProfileUsage {
        ProfileUsage {
            summary: TokenUsageSummary {
                lifetime_tokens: Some(tokens),
                peak_daily_tokens: Some(tokens),
                longest_running_turn_sec: None,
                current_streak_days: None,
                longest_streak_days: None,
            },
            daily_usage_buckets: vec![DailyTokenBucket {
                start_date: "2026-08-20".to_string(),
                tokens,
            }],
            fetched_at,
        }
    }

    fn profile_service() -> CoreService {
        CoreService {
            history: Mutex::new(HistoryRepository::open(":memory:").unwrap()),
            provider: CodexProvider::production().unwrap(),
            deepseek_provider: DeepSeekProvider::production().unwrap(),
            mimo_provider: MimoProvider::production().unwrap(),
            oauth_client: Client::new(),
            pending_device_logins: Mutex::new(HashMap::new()),
            mimo_sessions: tokio::sync::Mutex::new(HashMap::new()),
        }
    }

    fn profile_observation(body: &str) -> HttpObservation {
        HttpObservation {
            endpoint: "profile-usage".to_string(),
            status_code: Some(200),
            body: body.to_string(),
            duration_ms: 12,
            failure: None,
        }
    }

    #[test]
    fn maps_401_429_and_5xx_to_distinct_ui_states() {
        assert_eq!(
            api_failure_state(&ApiFailure::Unauthorized),
            UsageState::AuthExpired
        );
        assert_eq!(
            api_failure_state(&ApiFailure::RateLimited(Some(45))),
            UsageState::RateLimited
        );
        assert_eq!(
            api_failure_state(&ApiFailure::Server),
            UsageState::ServerError
        );
        assert_eq!(retry_after(&ApiFailure::RateLimited(Some(45))), Some(45));
    }

    #[test]
    fn a_refresh_failure_keeps_the_last_sqlite_snapshot() {
        let account = AccountInfo {
            provider: crate::models::ProviderKind::Codex,
            identity_hash: "account-hash".to_string(),
            email: Some("user@example.com".to_string()),
            plan: Some("pro".to_string()),
            workspace_id: None,
            is_fedramp: false,
            login_state: LoginState::SignedIn,
            last_successful_refresh: Some(1_700_000_000),
            credential_status: CredentialStatus::Available,
        };
        let snapshot = UsageSnapshot {
            account: account.clone(),
            windows: vec![QuotaWindow {
                id: "primary".to_string(),
                title: "Custom limit".to_string(),
                used_percent: 42.0,
                reset_at: 1_700_000_100,
                window_seconds: 3600,
            }],
            balances: Vec::new(),
            provider_quotas: Vec::new(),
            reset_credits_available: None,
            reset_credits: None,
            credits: None,
            fetched_at: 1_700_000_000,
        };
        let mut history = HistoryRepository::open(":memory:").unwrap();
        history.record_snapshot(&snapshot).unwrap();
        let service = CoreService {
            history: Mutex::new(history),
            provider: CodexProvider::production().unwrap(),
            deepseek_provider: DeepSeekProvider::production().unwrap(),
            mimo_provider: MimoProvider::production().unwrap(),
            oauth_client: Client::new(),
            pending_device_logins: Mutex::new(HashMap::new()),
            mimo_sessions: tokio::sync::Mutex::new(HashMap::new()),
        };

        let result = cached_failure(
            &service,
            account,
            UsageState::Offline,
            "Unable to reach OpenAI".to_string(),
            None,
            None,
        );

        assert_eq!(result.state, UsageState::Offline);
        assert!(result.showing_cached_data);
        assert_eq!(result.snapshot.unwrap().windows[0].used_percent, 42.0);
    }

    #[test]
    fn profile_parse_failure_keeps_cache_and_records_schema_mismatch() {
        let service = profile_service();
        service
            .history
            .lock()
            .unwrap()
            .save_profile_usage("account-hash", &profile(5, 1))
            .unwrap();

        let result = handle_profile_observation(
            &service,
            "account-hash",
            SyncTrigger::PageLoad,
            &profile_observation(r#"{"stats":{"lifetime_tokens":99}}"#),
            2,
        );

        assert!(result.is_err());
        let history = service.history.lock().unwrap();
        let cached = history.profile_usage("account-hash").unwrap().unwrap();
        assert_eq!(cached.daily_usage_buckets[0].tokens, 5);
        let logs = history.sync_logs().unwrap();
        assert_eq!(logs[0].result_state, "parse_error");
        assert_eq!(logs[0].error_kind.as_deref(), Some("schema_mismatch"));
    }

    #[test]
    fn profile_success_overwrites_cache_and_records_empty_or_fresh() {
        let service = profile_service();
        service
            .history
            .lock()
            .unwrap()
            .save_profile_usage("account-hash", &profile(5, 1))
            .unwrap();

        let empty = handle_profile_observation(
            &service,
            "account-hash",
            SyncTrigger::PageLoad,
            &profile_observation(r#"{"stats":{"daily_usage_buckets":[]}}"#),
            2,
        )
        .unwrap();
        assert!(empty.daily_usage_buckets.is_empty());

        let fresh = handle_profile_observation(
            &service,
            "account-hash",
            SyncTrigger::Manual,
            &profile_observation(
                r#"{"stats":{"daily_usage_buckets":[{"start_date":"2026-08-21","tokens":8}]}}"#,
            ),
            3,
        )
        .unwrap();
        assert_eq!(fresh.daily_usage_buckets[0].tokens, 8);

        let history = service.history.lock().unwrap();
        let cached = history.profile_usage("account-hash").unwrap().unwrap();
        assert_eq!(cached.daily_usage_buckets[0].tokens, 8);
        let logs = history.sync_logs().unwrap();
        assert_eq!(logs[0].result_state, "fresh");
        assert_eq!(logs[1].result_state, "empty");
    }

    #[test]
    fn profile_backend_error_has_distinct_diagnostic_kind() {
        let service = profile_service();
        let result = handle_profile_observation(
            &service,
            "account-hash",
            SyncTrigger::PageLoad,
            &profile_observation(
                r#"{"metadata":{"stats_error":"unavailable"},"stats":{"daily_usage_buckets":[]}}"#,
            ),
            2,
        );

        assert!(result.is_err());
        let logs = service.history.lock().unwrap().sync_logs().unwrap();
        assert_eq!(logs[0].result_state, "parse_error");
        assert_eq!(logs[0].error_kind.as_deref(), Some("backend_stats_error"));
    }
}
