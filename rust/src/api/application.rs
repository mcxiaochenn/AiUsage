//! flutter_rust_bridge-facing application API. No endpoint response model is
//! exported from this module.

use crate::bridge;
use crate::models::{
    AccountInfo, DeviceCodeLoginComplete, DeviceCodeLoginPoll, DeviceCodeLoginStart, HistoryPoint,
    SecureCredential, UsageResult,
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

pub async fn refresh_usage(credential: SecureCredential) -> UsageResult {
    bridge::refresh_usage(credential).await
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
