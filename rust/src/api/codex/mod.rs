//! Compatibility layer for Codex's internally-used Usage endpoints.
//!
//! Only this module knows endpoint spelling and request headers. A future
//! upstream API change is isolated here; nothing in Flutter sees raw JSON.

use std::time::Duration;

use reqwest::{Client, StatusCode};

use crate::models::SecureCredential;

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub(crate) enum PathStyle {
    CodexApi,
    ChatGptBackendApi,
}

#[derive(Clone, Debug)]
pub(crate) struct CodexProvider {
    base_url: String,
    path_style: PathStyle,
    client: Client,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub(crate) enum ApiFailure {
    Unauthorized,
    RateLimited(Option<i64>),
    Server,
    Offline,
    Other,
}

impl CodexProvider {
    pub(crate) fn production() -> Result<Self, String> {
        Self::from_base_url("https://chatgpt.com/backend-api")
    }

    pub(crate) fn from_base_url(base_url: &str) -> Result<Self, String> {
        let mut normalized = base_url.trim_end_matches('/').to_string();
        if (normalized.starts_with("https://chatgpt.com")
            || normalized.starts_with("https://chat.openai.com"))
            && !normalized.contains("/backend-api")
        {
            normalized.push_str("/backend-api");
        }
        let path_style = if normalized.contains("/backend-api") {
            PathStyle::ChatGptBackendApi
        } else {
            PathStyle::CodexApi
        };
        let client = Client::builder()
            .connect_timeout(Duration::from_secs(12))
            .timeout(Duration::from_secs(20))
            .build()
            .map_err(|error| format!("HTTP client setup failed: {error}"))?;
        Ok(Self {
            base_url: normalized,
            path_style,
            client,
        })
    }

    pub(crate) fn usage_url(&self) -> String {
        match self.path_style {
            PathStyle::CodexApi => format!("{}/api/codex/usage", self.base_url),
            PathStyle::ChatGptBackendApi => format!("{}/wham/usage", self.base_url),
        }
    }

    pub(crate) fn reset_credits_url(&self) -> String {
        match self.path_style {
            PathStyle::CodexApi => format!("{}/api/codex/rate-limit-reset-credits", self.base_url),
            PathStyle::ChatGptBackendApi => {
                format!("{}/wham/rate-limit-reset-credits", self.base_url)
            }
        }
    }

    pub(crate) async fn usage_json(
        &self,
        credential: &SecureCredential,
        workspace_id: Option<&str>,
        is_fedramp: bool,
    ) -> Result<String, ApiFailure> {
        self.get_json(&self.usage_url(), credential, workspace_id, is_fedramp)
            .await
    }

    pub(crate) async fn reset_credits_json(
        &self,
        credential: &SecureCredential,
        workspace_id: Option<&str>,
        is_fedramp: bool,
    ) -> Result<String, ApiFailure> {
        self.get_json(
            &self.reset_credits_url(),
            credential,
            workspace_id,
            is_fedramp,
        )
        .await
    }

    async fn get_json(
        &self,
        url: &str,
        credential: &SecureCredential,
        workspace_id: Option<&str>,
        is_fedramp: bool,
    ) -> Result<String, ApiFailure> {
        for attempt in 0..=2 {
            let mut request = self
                .client
                .get(url)
                .bearer_auth(&credential.access_token)
                .header("Accept", "application/json")
                .header("User-Agent", "AiUsage/0.1");
            if let Some(workspace_id) = workspace_id.filter(|value| !value.is_empty()) {
                request = request.header("ChatGPT-Account-Id", workspace_id);
            }
            if is_fedramp {
                request = request.header("X-OpenAI-Fedramp", "true");
            }
            let response = request.send().await.map_err(map_transport)?;
            let status = response.status();
            if status.is_success() {
                return response.text().await.map_err(map_transport);
            }
            if status == StatusCode::UNAUTHORIZED {
                return Err(ApiFailure::Unauthorized);
            }
            if status == StatusCode::TOO_MANY_REQUESTS {
                return Err(ApiFailure::RateLimited(retry_after_seconds(&response)));
            }
            if status.is_server_error() {
                if attempt < 2 {
                    tokio::time::sleep(backoff_delay(attempt)).await;
                    continue;
                }
                return Err(ApiFailure::Server);
            }
            return Err(ApiFailure::Other);
        }
        Err(ApiFailure::Server)
    }
}

fn map_transport(error: reqwest::Error) -> ApiFailure {
    if error.is_connect() || error.is_timeout() {
        ApiFailure::Offline
    } else {
        ApiFailure::Other
    }
}

fn retry_after_seconds(response: &reqwest::Response) -> Option<i64> {
    response
        .headers()
        .get("Retry-After")
        .and_then(|value| value.to_str().ok())
        .and_then(|value| value.trim().parse::<i64>().ok())
        .filter(|seconds| *seconds >= 0)
}

fn backoff_delay(attempt: u32) -> Duration {
    let base_millis = 350_u64.saturating_mul(2_u64.pow(attempt));
    let jitter_millis = (crate::auth::now_unix() as u64 % 200) + 1;
    Duration::from_millis(base_millis + jitter_millis)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn uses_the_current_wham_path_for_chatgpt_backend() {
        let provider = CodexProvider::from_base_url("https://chatgpt.com").unwrap();
        assert_eq!(
            provider.usage_url(),
            "https://chatgpt.com/backend-api/wham/usage"
        );
        assert_eq!(
            provider.reset_credits_url(),
            "https://chatgpt.com/backend-api/wham/rate-limit-reset-credits"
        );
    }

    #[test]
    fn retains_codex_api_compatibility_path() {
        let provider = CodexProvider::from_base_url("https://example.test").unwrap();
        assert_eq!(provider.usage_url(), "https://example.test/api/codex/usage");
    }

    #[test]
    fn failure_states_remain_distinct() {
        assert_eq!(ApiFailure::Unauthorized, ApiFailure::Unauthorized);
        assert_eq!(
            ApiFailure::RateLimited(Some(30)),
            ApiFailure::RateLimited(Some(30))
        );
        assert_eq!(ApiFailure::Server, ApiFailure::Server);
    }
}
