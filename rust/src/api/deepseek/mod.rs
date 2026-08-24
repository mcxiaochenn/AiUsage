use std::time::{Duration, Instant};

use reqwest::{Client, StatusCode};
use serde_json::Value;

use crate::api::codex::{ApiFailure, HttpObservation};
use crate::models::BalanceMetric;

const BALANCE_URL: &str = "https://api.deepseek.com/user/balance";

#[derive(Clone, Debug)]
pub(crate) struct DeepSeekProvider {
    client: Client,
}

impl DeepSeekProvider {
    pub(crate) fn production() -> Result<Self, String> {
        let client = Client::builder()
            .connect_timeout(Duration::from_secs(12))
            .timeout(Duration::from_secs(20))
            .build()
            .map_err(|error| format!("DeepSeek HTTP client setup failed: {error}"))?;
        Ok(Self { client })
    }

    pub(crate) async fn balance_json(&self, api_key: &str) -> HttpObservation {
        let started = Instant::now();
        let response = self
            .client
            .get(BALANCE_URL)
            .bearer_auth(api_key)
            .header("Accept", "application/json")
            .header("User-Agent", "AiUsage/0.1")
            .send()
            .await;
        let response = match response {
            Ok(value) => value,
            Err(error) => {
                return HttpObservation {
                    endpoint: "deepseek-balance".to_string(),
                    status_code: None,
                    body: String::new(),
                    duration_ms: started.elapsed().as_millis() as i64,
                    failure: Some(if error.is_connect() || error.is_timeout() {
                        ApiFailure::Offline
                    } else {
                        ApiFailure::Other
                    }),
                };
            }
        };
        let status = response.status();
        let retry_after = response
            .headers()
            .get("Retry-After")
            .and_then(|value| value.to_str().ok())
            .and_then(|value| value.parse::<i64>().ok());
        let body = response.text().await.unwrap_or_default();
        let failure = if status.is_success() {
            None
        } else if status == StatusCode::UNAUTHORIZED {
            Some(ApiFailure::Unauthorized)
        } else if status == StatusCode::TOO_MANY_REQUESTS {
            Some(ApiFailure::RateLimited(retry_after))
        } else if status.is_server_error() {
            Some(ApiFailure::Server)
        } else {
            Some(ApiFailure::Other)
        };
        HttpObservation {
            endpoint: "deepseek-balance".to_string(),
            status_code: Some(i64::from(status.as_u16())),
            body,
            duration_ms: started.elapsed().as_millis() as i64,
            failure,
        }
    }
}

pub(crate) fn parse_balance(body: &str) -> Result<(bool, Vec<BalanceMetric>, bool), String> {
    let value: Value = serde_json::from_str(body)
        .map_err(|_| "schema_mismatch: DeepSeek balance response is not valid JSON".to_string())?;
    let available = value
        .get("is_available")
        .and_then(Value::as_bool)
        .ok_or_else(|| "schema_mismatch: DeepSeek is_available is missing".to_string())?;
    let entries = value
        .get("balance_infos")
        .and_then(Value::as_array)
        .ok_or_else(|| "schema_mismatch: DeepSeek balance_infos is missing".to_string())?;
    let mut metrics = Vec::new();
    let mut invalid = 0usize;
    for entry in entries {
        let Some(currency) = entry
            .get("currency")
            .and_then(Value::as_str)
            .filter(|value| matches!(*value, "CNY" | "USD"))
        else {
            invalid += 1;
            continue;
        };
        let values = [
            ("total", "Total balance", "total_balance", true),
            ("granted", "Granted balance", "granted_balance", false),
            ("topped-up", "Topped-up balance", "topped_up_balance", false),
        ];
        let parsed = values
            .iter()
            .map(|(id, label, key, primary)| {
                decimal_text(entry.get(*key)?).map(|amount| BalanceMetric {
                    id: format!("deepseek:{currency}:{id}"),
                    label: (*label).to_string(),
                    amount,
                    currency: Some(currency.to_string()),
                    primary: *primary,
                })
            })
            .collect::<Option<Vec<_>>>();
        if let Some(parsed) = parsed {
            metrics.extend(parsed);
        } else {
            invalid += 1;
        }
    }
    if !entries.is_empty() && metrics.is_empty() {
        return Err(
            "schema_mismatch: DeepSeek balance_infos contains no valid entries".to_string(),
        );
    }
    Ok((available, metrics, invalid > 0))
}

fn decimal_text(value: &Value) -> Option<String> {
    let text = match value {
        Value::String(value) => value.trim().to_string(),
        Value::Number(value) => value.to_string(),
        _ => return None,
    };
    let unsigned = text.strip_prefix(['+', '-']).unwrap_or(&text);
    let mut parts = unsigned.split('.');
    let whole = parts.next()?;
    let fraction = parts.next();
    if parts.next().is_some()
        || whole.is_empty()
        || !whole.bytes().all(|byte| byte.is_ascii_digit())
        || fraction.is_some_and(|value| {
            value.is_empty() || !value.bytes().all(|byte| byte.is_ascii_digit())
        })
    {
        return None;
    }
    Some(text)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parses_multiple_currencies_without_converting_them() {
        let (_, metrics, partial) = parse_balance(
            r#"{"is_available":true,"balance_infos":[
                {"currency":"CNY","total_balance":"10.50","granted_balance":"1.00","topped_up_balance":"9.50"},
                {"currency":"USD","total_balance":"2.25","granted_balance":"0","topped_up_balance":"2.25"}
            ]}"#,
        )
        .unwrap();
        assert_eq!(metrics.len(), 6);
        assert_eq!(metrics[0].currency.as_deref(), Some("CNY"));
        assert_eq!(metrics[3].currency.as_deref(), Some("USD"));
        assert!(!partial);
    }

    #[test]
    fn keeps_valid_entries_and_rejects_entirely_invalid_arrays() {
        let (_, metrics, partial) = parse_balance(
            r#"{"is_available":true,"balance_infos":[
                {"currency":"EUR","total_balance":"1","granted_balance":"0","topped_up_balance":"1"},
                {"currency":"CNY","total_balance":"2","granted_balance":"0","topped_up_balance":"2"}
            ]}"#,
        )
        .unwrap();
        assert_eq!(metrics.len(), 3);
        assert!(partial);
        assert!(parse_balance(r#"{"is_available":true,"balance_infos":[{}]}"#).is_err());
    }

    #[test]
    fn accepts_a_valid_empty_balance_and_rejects_schema_drift() {
        let (available, metrics, partial) =
            parse_balance(r#"{"is_available":false,"balance_infos":[]}"#).unwrap();
        assert!(!available);
        assert!(metrics.is_empty());
        assert!(!partial);
        assert!(parse_balance(r#"{"is_available":"yes","balance_infos":[]}"#).is_err());
        assert!(parse_balance(r#"{"is_available":true,"balance_infos":null}"#).is_err());
        assert!(parse_balance(
            r#"{"is_available":true,"balance_infos":[{"currency":"CNY","total_balance":"NaN","granted_balance":"0","topped_up_balance":"0"}]}"#
        )
        .is_err());
    }
}
