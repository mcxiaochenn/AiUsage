//! Application service used by the flutter_rust_bridge API.

use std::collections::HashMap;
use std::sync::{Mutex, OnceLock};

use reqwest::Client;
use uuid::Uuid;

use crate::api::codex::{ApiFailure, CodexProvider, HttpObservation};
use crate::auth::{self, AuthError, DeviceCodePoll, PendingDeviceCode};
use crate::history::HistoryRepository;
use crate::models::{
    AccountDetails, AccountInfo, DeviceCodeLoginComplete, DeviceCodeLoginPoll,
    DeviceCodeLoginStart, HistoryPoint, ProfileUsage, SecureCredential, SyncLogEntry, SyncTrigger,
    UsageResult, UsageState,
};
use crate::normalize::{
    RawWhamUsage, parse_account_details, parse_credit_details, parse_profile_usage,
};

static CORE: OnceLock<CoreService> = OnceLock::new();

struct CoreService {
    history: Mutex<HistoryRepository>,
    provider: CodexProvider,
    oauth_client: Client,
    pending_device_logins: Mutex<HashMap<String, PendingDeviceCode>>,
}

impl CoreService {
    fn create(database_path: &str) -> Result<Self, String> {
        let provider = CodexProvider::production()?;
        let oauth_client = Client::builder()
            .connect_timeout(std::time::Duration::from_secs(12))
            .timeout(std::time::Duration::from_secs(20))
            .build()
            .map_err(|error| format!("OAuth client setup failed: {error}"))?;
        Ok(Self {
            history: Mutex::new(HistoryRepository::open(database_path)?),
            provider,
            oauth_client,
            pending_device_logins: Mutex::new(HashMap::new()),
        })
    }
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
    let profile = parse_profile_usage(&observation.body, auth::now_unix())?;
    service
        .history
        .lock()
        .map_err(|_| "Profile cache is unavailable".to_string())?
        .save_profile_usage(&account.identity_hash, &profile)?;
    Ok(profile)
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
    let started_at = auth::now_unix() - (observation.duration_ms / 1000);
    let error_kind = observation.failure.as_ref().map(api_failure_label);
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

fn retry_after(failure: &ApiFailure) -> Option<i64> {
    match failure {
        ApiFailure::RateLimited(seconds) => *seconds,
        _ => None,
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::models::{CredentialStatus, LoginState, QuotaWindow, UsageSnapshot};

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
            oauth_client: Client::new(),
            pending_device_logins: Mutex::new(HashMap::new()),
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
}
