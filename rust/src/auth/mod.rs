//! OpenAI OAuth implementation based on the current `openai/codex` source.
//! Credentials only exist here transiently; persistence is delegated to Flutter
//! secure storage through the bridge result types.

use std::time::{SystemTime, UNIX_EPOCH};

use base64::{Engine as _, engine::general_purpose::URL_SAFE_NO_PAD};
use reqwest::{Client, StatusCode};
use serde::{Deserialize, Serialize};
use serde_json::Value;
use sha2::{Digest, Sha256};
use thiserror::Error;

use crate::models::{AccountInfo, CredentialStatus, LoginState, SecureCredential};

pub const AUTH_ISSUER: &str = "https://auth.openai.com";
/// Current upstream value in `codex-rs/login/src/auth/manager.rs`. It is kept
/// here, rather than in Flutter, so a provider update is a one-file change.
pub const CODEX_OAUTH_CLIENT_ID: &str = "app_EMoamEEZ73f0CkXaXp7hrann";
const DEVICE_CODE_MAX_WAIT_SECONDS: i64 = 15 * 60;
pub const AUTH_JSON_MAX_BYTES: usize = 1024 * 1024;

#[derive(Debug, Error)]
pub enum AuthError {
    #[error("OpenAI authorization has expired or was revoked")]
    Permanent,
    #[error("OAuth service rejected the request ({0})")]
    Rejected(u16),
    #[error("OAuth transport failure")]
    Transport,
    #[error("OAuth response could not be decoded")]
    Decode,
    #[error("OAuth response omitted required credentials")]
    MissingCredential,
    #[error("OAuth login is no longer pending")]
    NotPending,
    #[error("auth_import.file_too_large")]
    FileTooLarge,
    #[error("auth_import.invalid_json")]
    InvalidAuthJson,
    #[error("auth_import.api_key_only")]
    ApiKeyOnly,
}

#[derive(Clone, Debug)]
pub struct PendingDeviceCode {
    pub device_auth_id: String,
    pub user_code: String,
    pub interval_seconds: i64,
    pub started_at: i64,
    pub verification_url: String,
}

#[derive(Clone, Debug)]
pub enum DeviceCodePoll {
    Pending,
    Authorized(SecureCredential),
}

#[derive(Serialize)]
struct DeviceCodeStartRequest<'a> {
    client_id: &'a str,
}

#[derive(Deserialize)]
struct DeviceCodeStartResponse {
    device_auth_id: String,
    #[serde(alias = "usercode")]
    user_code: String,
    #[serde(default)]
    interval: Value,
    #[serde(default, alias = "verification_url")]
    verification_uri: Option<String>,
    #[serde(default)]
    verification_uri_complete: Option<String>,
}

#[derive(Serialize)]
struct DeviceCodePollRequest<'a> {
    device_auth_id: &'a str,
    user_code: &'a str,
}

#[derive(Deserialize)]
struct DeviceCodeAuthorizedResponse {
    authorization_code: String,
    code_verifier: String,
}

#[derive(Deserialize)]
struct TokenResponse {
    id_token: Option<String>,
    access_token: Option<String>,
    refresh_token: Option<String>,
}

pub fn import_auth_json(content: &[u8]) -> Result<SecureCredential, AuthError> {
    if content.len() > AUTH_JSON_MAX_BYTES {
        return Err(AuthError::FileTooLarge);
    }
    let document: Value =
        serde_json::from_slice(content).map_err(|_| AuthError::InvalidAuthJson)?;
    let tokens = document.get("tokens").and_then(Value::as_object);
    if tokens.is_none()
        && document
            .get("OPENAI_API_KEY")
            .and_then(Value::as_str)
            .is_some_and(|value| !value.trim().is_empty())
    {
        return Err(AuthError::ApiKeyOnly);
    }
    let tokens = tokens.ok_or(AuthError::MissingCredential)?;
    let read = |key: &str| {
        tokens
            .get(key)
            .and_then(Value::as_str)
            .filter(|value| !value.is_empty())
            .map(ToOwned::to_owned)
            .ok_or(AuthError::MissingCredential)
    };
    let credential = SecureCredential {
        id_token: read("id_token")?,
        access_token: read("access_token")?,
        refresh_token: read("refresh_token")?,
    };
    account_from_credential(&credential)?;
    Ok(credential)
}

#[derive(Serialize)]
struct RefreshRequest<'a> {
    client_id: &'a str,
    grant_type: &'static str,
    refresh_token: &'a str,
}

pub fn now_unix() -> i64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|duration| duration.as_secs() as i64)
        .unwrap_or_default()
}

pub fn account_from_credential(credential: &SecureCredential) -> Result<AccountInfo, AuthError> {
    let claims = decode_claims(&credential.id_token).ok_or(AuthError::Decode)?;
    let auth = claims
        .get("https://api.openai.com/auth")
        .and_then(Value::as_object);
    let profile_email = claims
        .get("https://api.openai.com/profile")
        .and_then(Value::as_object)
        .and_then(|profile| profile.get("email"))
        .and_then(Value::as_str);
    let email = claims
        .get("email")
        .and_then(Value::as_str)
        .or(profile_email)
        .map(ToOwned::to_owned);
    let workspace_id = auth
        .and_then(|value| value.get("chatgpt_account_id"))
        .and_then(Value::as_str)
        .map(ToOwned::to_owned);
    let user_id = auth
        .and_then(|value| {
            value
                .get("chatgpt_user_id")
                .or_else(|| value.get("user_id"))
        })
        .and_then(Value::as_str)
        .or_else(|| claims.get("sub").and_then(Value::as_str));
    let plan = auth
        .and_then(|value| value.get("chatgpt_plan_type"))
        .and_then(Value::as_str)
        .map(ToOwned::to_owned);
    let is_fedramp = auth
        .and_then(|value| value.get("chatgpt_account_is_fedramp"))
        .and_then(Value::as_bool)
        .unwrap_or(false);

    let identity_source = workspace_id
        .as_deref()
        .or(user_id)
        .or(email.as_deref())
        .ok_or(AuthError::Decode)?;

    Ok(AccountInfo {
        identity_hash: identity_hash(identity_source),
        email,
        plan,
        workspace_id,
        is_fedramp,
        login_state: LoginState::SignedIn,
        last_successful_refresh: None,
        credential_status: CredentialStatus::Available,
    })
}

pub fn access_token_needs_refresh(credential: &SecureCredential) -> bool {
    let Some(claims) = decode_claims(&credential.access_token) else {
        return false;
    };
    let Some(expires_at) = claims.get("exp").and_then(Value::as_i64) else {
        return false;
    };
    expires_at <= now_unix() + 5 * 60
}

pub async fn start_device_code(client: &Client) -> Result<PendingDeviceCode, AuthError> {
    let response = client
        .post(format!("{AUTH_ISSUER}/api/accounts/deviceauth/usercode"))
        .json(&DeviceCodeStartRequest {
            client_id: CODEX_OAUTH_CLIENT_ID,
        })
        .send()
        .await
        .map_err(map_transport)?;
    if !response.status().is_success() {
        return Err(status_error(response.status(), None));
    }
    let response = response
        .json::<DeviceCodeStartResponse>()
        .await
        .map_err(|_| AuthError::Decode)?;
    let interval_seconds = flexible_seconds(&response.interval)
        .unwrap_or(5)
        .clamp(1, 60);
    Ok(PendingDeviceCode {
        device_auth_id: response.device_auth_id,
        user_code: response.user_code,
        interval_seconds,
        started_at: now_unix(),
        verification_url: response
            .verification_uri_complete
            .or(response.verification_uri)
            .unwrap_or_else(|| format!("{AUTH_ISSUER}/codex/device")),
    })
}

pub async fn poll_device_code(
    client: &Client,
    pending: &PendingDeviceCode,
) -> Result<DeviceCodePoll, AuthError> {
    if device_code_expired(pending) {
        return Err(AuthError::Permanent);
    }
    let response = client
        .post(format!("{AUTH_ISSUER}/api/accounts/deviceauth/token"))
        .json(&DeviceCodePollRequest {
            device_auth_id: &pending.device_auth_id,
            user_code: &pending.user_code,
        })
        .send()
        .await
        .map_err(map_transport)?;
    if response.status() == StatusCode::FORBIDDEN || response.status() == StatusCode::NOT_FOUND {
        return Ok(DeviceCodePoll::Pending);
    }
    if !response.status().is_success() {
        return Err(status_error(response.status(), None));
    }
    let authorization = response
        .json::<DeviceCodeAuthorizedResponse>()
        .await
        .map_err(|_| AuthError::Decode)?;
    let credential = exchange_authorization_code(
        client,
        &authorization.authorization_code,
        &authorization.code_verifier,
        &format!("{AUTH_ISSUER}/deviceauth/callback"),
    )
    .await?;
    Ok(DeviceCodePoll::Authorized(credential))
}

pub async fn refresh_credential(
    client: &Client,
    current: &SecureCredential,
) -> Result<SecureCredential, AuthError> {
    let response = client
        .post(format!("{AUTH_ISSUER}/oauth/token"))
        .json(&RefreshRequest {
            client_id: CODEX_OAUTH_CLIENT_ID,
            grant_type: "refresh_token",
            refresh_token: &current.refresh_token,
        })
        .send()
        .await
        .map_err(map_transport)?;
    if !response.status().is_success() {
        let status = response.status();
        let body = response.text().await.unwrap_or_default();
        return Err(status_error(status, Some(&body)));
    }
    let token = response
        .json::<TokenResponse>()
        .await
        .map_err(|_| AuthError::Decode)?;
    merge_token_response(token, current)
}

async fn exchange_authorization_code(
    client: &Client,
    code: &str,
    code_verifier: &str,
    redirect_uri: &str,
) -> Result<SecureCredential, AuthError> {
    let response = client
        .post(format!("{AUTH_ISSUER}/oauth/token"))
        .form(&[
            ("grant_type", "authorization_code"),
            ("code", code),
            ("redirect_uri", redirect_uri),
            ("client_id", CODEX_OAUTH_CLIENT_ID),
            ("code_verifier", code_verifier),
        ])
        .send()
        .await
        .map_err(map_transport)?;
    if !response.status().is_success() {
        let status = response.status();
        return Err(status_error(status, None));
    }
    let token = response
        .json::<TokenResponse>()
        .await
        .map_err(|_| AuthError::Decode)?;
    merge_token_response(
        token,
        &SecureCredential {
            id_token: String::new(),
            access_token: String::new(),
            refresh_token: String::new(),
        },
    )
}

fn merge_token_response(
    response: TokenResponse,
    current: &SecureCredential,
) -> Result<SecureCredential, AuthError> {
    let id_token = response
        .id_token
        .unwrap_or_else(|| current.id_token.clone());
    let access_token = response
        .access_token
        .unwrap_or_else(|| current.access_token.clone());
    let refresh_token = response
        .refresh_token
        .unwrap_or_else(|| current.refresh_token.clone());
    if id_token.is_empty() || access_token.is_empty() || refresh_token.is_empty() {
        return Err(AuthError::MissingCredential);
    }
    Ok(SecureCredential {
        id_token,
        access_token,
        refresh_token,
    })
}

fn map_transport(error: reqwest::Error) -> AuthError {
    let _is_network_problem = error.is_connect() || error.is_timeout();
    AuthError::Transport
}

fn status_error(status: StatusCode, body: Option<&str>) -> AuthError {
    let invalid_grant = body
        .map(|value| value.to_ascii_lowercase().contains("invalid_grant"))
        .unwrap_or(false);
    if status == StatusCode::UNAUTHORIZED || invalid_grant {
        AuthError::Permanent
    } else {
        AuthError::Rejected(status.as_u16())
    }
}

fn decode_claims(jwt: &str) -> Option<Value> {
    let mut parts = jwt.split('.');
    let _header = parts.next()?;
    let payload = parts.next()?;
    let _signature = parts.next()?;
    let bytes = URL_SAFE_NO_PAD.decode(payload).ok()?;
    serde_json::from_slice(&bytes).ok()
}

fn identity_hash(source: &str) -> String {
    let digest = Sha256::digest(source.as_bytes());
    // A short digest is enough for local account separation while avoiding a
    // raw user/workspace identifier in SQLite.
    digest[..16]
        .iter()
        .map(|byte| format!("{byte:02x}"))
        .collect()
}

fn flexible_seconds(value: &Value) -> Option<i64> {
    value
        .as_i64()
        .or_else(|| value.as_str().and_then(|raw| raw.trim().parse().ok()))
}

fn device_code_expired(pending: &PendingDeviceCode) -> bool {
    now_unix().saturating_sub(pending.started_at) > DEVICE_CODE_MAX_WAIT_SECONDS
}

#[cfg(test)]
mod tests {
    use super::*;

    fn credential_with_claims(claims: Value) -> SecureCredential {
        let encoded = URL_SAFE_NO_PAD.encode(serde_json::to_vec(&claims).unwrap());
        SecureCredential {
            id_token: format!("a.{encoded}.c"),
            access_token: "access".to_string(),
            refresh_token: "refresh".to_string(),
        }
    }

    #[test]
    fn extracts_identity_from_current_claim_namespace() {
        let account = account_from_credential(&credential_with_claims(serde_json::json!({
            "email": "user@example.com",
            "https://api.openai.com/auth": {
                "chatgpt_account_id": "workspace-1",
                "chatgpt_user_id": "user-1",
                "chatgpt_plan_type": "pro",
                "chatgpt_account_is_fedramp": true
            }
        })))
        .unwrap();
        assert_eq!(account.email.as_deref(), Some("user@example.com"));
        assert_eq!(account.plan.as_deref(), Some("pro"));
        assert_eq!(account.workspace_id.as_deref(), Some("workspace-1"));
        assert!(account.is_fedramp);
        assert_ne!(account.identity_hash, "workspace-1");
    }

    #[test]
    fn malformed_jwt_is_rejected() {
        let credential = SecureCredential {
            id_token: "not-a-jwt".to_string(),
            access_token: String::new(),
            refresh_token: String::new(),
        };
        assert!(matches!(
            account_from_credential(&credential),
            Err(AuthError::Decode)
        ));
    }

    #[test]
    fn expired_access_token_requires_refresh() {
        let encoded = URL_SAFE_NO_PAD
            .encode(serde_json::to_vec(&serde_json::json!({ "exp": now_unix() - 1 })).unwrap());
        let credential = SecureCredential {
            id_token: "a.b.c".to_string(),
            access_token: format!("a.{encoded}.c"),
            refresh_token: "refresh".to_string(),
        };
        assert!(access_token_needs_refresh(&credential));
    }

    #[test]
    fn device_code_login_has_a_bounded_wait() {
        let expired = PendingDeviceCode {
            device_auth_id: "device".to_string(),
            user_code: "code".to_string(),
            interval_seconds: 5,
            started_at: now_unix() - DEVICE_CODE_MAX_WAIT_SECONDS - 1,
            verification_url: format!("{AUTH_ISSUER}/codex/device"),
        };
        assert!(device_code_expired(&expired));
    }

    #[test]
    fn imports_current_codex_auth_json_shape() {
        let encoded = URL_SAFE_NO_PAD.encode(
            serde_json::to_vec(&serde_json::json!({
                "sub": "user-1",
                "email": "user@example.com"
            }))
            .unwrap(),
        );
        let document = serde_json::json!({
            "tokens": {
                "id_token": format!("a.{encoded}.c"),
                "access_token": "test-access-token",
                "refresh_token": "test-refresh-token"
            }
        });
        let credential = import_auth_json(&serde_json::to_vec(&document).unwrap()).unwrap();
        assert_eq!(credential.access_token, "test-access-token");
    }

    #[test]
    fn rejects_api_key_only_auth_json() {
        let error = import_auth_json(br#"{"OPENAI_API_KEY":"test-key"}"#).unwrap_err();
        assert!(matches!(error, AuthError::ApiKeyOnly));
    }

    #[test]
    fn rejects_missing_tokens_and_malformed_json() {
        assert!(matches!(
            import_auth_json(br#"{"tokens":{}}"#),
            Err(AuthError::MissingCredential)
        ));
        assert!(matches!(
            import_auth_json(b"not-json"),
            Err(AuthError::InvalidAuthJson)
        ));
    }

    #[test]
    fn rejects_oversized_auth_json() {
        let content = vec![b' '; AUTH_JSON_MAX_BYTES + 1];
        assert!(matches!(
            import_auth_json(&content),
            Err(AuthError::FileTooLarge)
        ));
    }
}
