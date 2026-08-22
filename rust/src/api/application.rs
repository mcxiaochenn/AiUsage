//! flutter_rust_bridge-facing application API. No endpoint response model is
//! exported from this module.

use crate::bridge;
use crate::models::{
    AccountDetails, AccountInfo, DeviceCodeLoginComplete, DeviceCodeLoginPoll,
    DeviceCodeLoginStart, HistoryPoint, ProfileUsage, SecureCredential, SyncLogEntry, SyncTrigger,
    UsageResult,
};

pub fn initialize_core(database_path: String) -> Result<(), String> {
    bridge::initialize(database_path)
}

pub async fn begin_device_login() -> Result<DeviceCodeLoginStart, String> {
    bridge::begin_device_login().await
}

pub async fn poll_device_login(login_id: String) -> Result<DeviceCodeLoginPoll, String> {
    bridge::poll_device_login(login_id).await
}

pub fn cancel_device_login(login_id: String) -> Result<(), String> {
    bridge::cancel_device_login(login_id)
}

pub fn import_codex_auth_json(content: Vec<u8>) -> Result<DeviceCodeLoginComplete, String> {
    bridge::import_codex_auth_json(content)
}

pub async fn refresh_usage(credential: SecureCredential, trigger: SyncTrigger) -> UsageResult {
    bridge::refresh_usage(credential, trigger).await
}

pub async fn fetch_profile_usage(
    credential: SecureCredential,
    trigger: SyncTrigger,
) -> Result<ProfileUsage, String> {
    bridge::fetch_profile_usage(credential, trigger).await
}

pub fn cached_profile_usage(account_identity_hash: String) -> Result<Option<ProfileUsage>, String> {
    bridge::cached_profile_usage(account_identity_hash)
}

pub async fn fetch_account_details(
    credential: SecureCredential,
    trigger: SyncTrigger,
) -> Result<AccountDetails, String> {
    bridge::fetch_account_details(credential, trigger).await
}

pub fn cached_account_details(
    account_identity_hash: String,
) -> Result<Option<AccountDetails>, String> {
    bridge::cached_account_details(account_identity_hash)
}

pub fn sync_logs() -> Result<Vec<SyncLogEntry>, String> {
    bridge::sync_logs()
}

pub fn cached_usage(account: AccountInfo) -> Result<UsageResult, String> {
    bridge::cached_usage(account)
}

pub fn usage_history(
    account_identity_hash: String,
    since: i64,
) -> Result<Vec<HistoryPoint>, String> {
    bridge::history(account_identity_hash, since)
}

pub fn remove_account_data(account_identity_hash: String) -> Result<(), String> {
    bridge::remove_account_data(account_identity_hash)
}
