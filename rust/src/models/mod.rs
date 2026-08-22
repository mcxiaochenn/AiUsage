//! Stable models exposed to Flutter. These intentionally do not mirror the
//! undocumented OpenAI response bodies.

use serde::{Deserialize, Serialize};

#[derive(Clone, Debug, Serialize, Deserialize, PartialEq, Eq)]
pub struct SecureCredential {
    pub id_token: String,
    pub access_token: String,
    pub refresh_token: String,
}

/// Non-secret account metadata. `identity_hash` is the only account identifier
/// written to SQLite; it is a SHA-256 digest derived from JWT claims.
#[derive(Clone, Debug, Serialize, Deserialize, PartialEq, Eq)]
pub struct AccountInfo {
    pub identity_hash: String,
    pub email: Option<String>,
    pub plan: Option<String>,
    pub workspace_id: Option<String>,
    pub is_fedramp: bool,
    pub login_state: LoginState,
    pub last_successful_refresh: Option<i64>,
    pub credential_status: CredentialStatus,
}

#[derive(Clone, Debug, Serialize, Deserialize, PartialEq, Eq)]
pub enum LoginState {
    SignedIn,
    SignedOut,
    Expired,
}

#[derive(Clone, Debug, Serialize, Deserialize, PartialEq, Eq)]
pub enum CredentialStatus {
    Available,
    Missing,
    RefreshRequired,
}

#[derive(Clone, Debug, Serialize, Deserialize, PartialEq)]
pub struct QuotaWindow {
    pub id: String,
    pub title: String,
    pub used_percent: f64,
    pub reset_at: i64,
    pub window_seconds: i64,
}

impl QuotaWindow {
    pub fn remaining_percent(&self) -> f64 {
        100.0 - self.used_percent
    }
}

#[derive(Clone, Debug, Serialize, Deserialize, PartialEq, Eq)]
pub struct ResetCredit {
    pub id: String,
    pub status: String,
    pub granted_at: i64,
    pub expires_at: Option<i64>,
    pub title: Option<String>,
    pub description: Option<String>,
}

#[derive(Clone, Debug, Serialize, Deserialize, PartialEq)]
pub struct UsageSnapshot {
    pub account: AccountInfo,
    pub windows: Vec<QuotaWindow>,
    pub reset_credits_available: Option<i64>,
    pub reset_credits: Option<Vec<ResetCredit>>,
    pub fetched_at: i64,
}

#[derive(Clone, Debug, Serialize, Deserialize, PartialEq, Eq)]
pub enum UsageState {
    Fresh,
    Stale,
    AuthExpired,
    Offline,
    RateLimited,
    ServerError,
    ParseError,
}

#[derive(Clone, Debug, Serialize, Deserialize, PartialEq)]
pub struct UsageResult {
    pub snapshot: Option<UsageSnapshot>,
    pub state: UsageState,
    pub showing_cached_data: bool,
    pub message: Option<String>,
    pub retry_after_seconds: Option<i64>,
    /// Present only after an OAuth refresh or device-code sign-in. Flutter must
    /// replace its secure-storage value atomically and must never place this in
    /// SQLite or logs.
    pub updated_credential: Option<SecureCredential>,
}

#[derive(Clone, Debug, Serialize, Deserialize, PartialEq, Eq)]
pub struct DeviceCodeLoginStart {
    pub login_id: String,
    pub verification_url: String,
    pub user_code: String,
    pub poll_interval_seconds: i64,
}

#[derive(Clone, Debug, Serialize, Deserialize, PartialEq)]
pub struct DeviceCodeLoginComplete {
    pub credential: SecureCredential,
    pub account: AccountInfo,
}

#[derive(Clone, Debug, Serialize, Deserialize, PartialEq)]
pub struct DeviceCodeLoginPoll {
    pub pending: bool,
    pub completed: Option<DeviceCodeLoginComplete>,
}

#[derive(Clone, Debug, Serialize, Deserialize, PartialEq)]
pub struct HistoryPoint {
    pub timestamp: i64,
    pub window_id: String,
    pub used_percent: f64,
}
