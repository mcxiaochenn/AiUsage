//! Tolerant translation from undocumented OpenAI JSON to stable domain models.

use chrono::DateTime;
use serde_json::Value;

use crate::models::{AccountInfo, QuotaWindow, ResetCredit, UsageSnapshot};

#[derive(Clone, Debug)]
pub struct RawWhamUsage {
    value: Value,
}

impl RawWhamUsage {
    pub fn parse(body: &str) -> Result<Self, serde_json::Error> {
        Ok(Self {
            value: serde_json::from_str(body)?,
        })
    }

    pub fn normalize(self, mut account: AccountInfo, fetched_at: i64) -> UsageSnapshot {
        if account.plan.is_none() {
            account.plan = self
                .value
                .get("plan_type")
                .and_then(Value::as_str)
                .map(ToOwned::to_owned);
        }

        let mut windows = Vec::new();
        if let Some(rate_limit) = self.value.get("rate_limit") {
            collect_windows(&mut windows, "codex", None, rate_limit, fetched_at);
        }
        if let Some(additional) = self
            .value
            .get("additional_rate_limits")
            .and_then(Value::as_array)
        {
            for (index, item) in additional.iter().enumerate() {
                let limit_id = item
                    .get("metered_feature")
                    .and_then(Value::as_str)
                    .filter(|value| !value.trim().is_empty())
                    .map(ToOwned::to_owned)
                    .unwrap_or_else(|| format!("additional-{index}"));
                let label = item
                    .get("limit_name")
                    .and_then(Value::as_str)
                    .filter(|value| !value.trim().is_empty())
                    .map(ToOwned::to_owned);
                if let Some(rate_limit) = item.get("rate_limit") {
                    collect_windows(
                        &mut windows,
                        &limit_id,
                        label.as_deref(),
                        rate_limit,
                        fetched_at,
                    );
                }
            }
        }

        UsageSnapshot {
            account,
            windows,
            reset_credits_available: self
                .value
                .get("rate_limit_reset_credits")
                .and_then(|value| value.get("available_count"))
                .and_then(value_as_i64),
            reset_credits: None,
            fetched_at,
        }
    }
}

pub fn parse_credit_details(
    body: &str,
) -> Result<(Option<i64>, Vec<ResetCredit>), serde_json::Error> {
    let value: Value = serde_json::from_str(body)?;
    let available_count = value.get("available_count").and_then(value_as_i64);
    let credits = value
        .get("credits")
        .and_then(Value::as_array)
        .map(|items| {
            items
                .iter()
                .filter_map(|item| {
                    let id = item.get("id")?.as_str()?.to_string();
                    Some(ResetCredit {
                        id,
                        status: item
                            .get("status")
                            .and_then(Value::as_str)
                            .unwrap_or("unknown")
                            .to_string(),
                        granted_at: item
                            .get("granted_at")
                            .and_then(parse_timestamp)
                            .unwrap_or_default(),
                        expires_at: item.get("expires_at").and_then(parse_timestamp),
                        title: item
                            .get("title")
                            .and_then(Value::as_str)
                            .map(ToOwned::to_owned),
                        description: item
                            .get("description")
                            .and_then(Value::as_str)
                            .map(ToOwned::to_owned),
                    })
                })
                .collect()
        })
        .unwrap_or_default();
    Ok((available_count, credits))
}

fn collect_windows(
    output: &mut Vec<QuotaWindow>,
    limit_id: &str,
    label: Option<&str>,
    rate_limit: &Value,
    fetched_at: i64,
) {
    for (slot, raw_window) in [
        ("primary", rate_limit.get("primary_window")),
        ("secondary", rate_limit.get("secondary_window")),
    ] {
        let Some(raw_window) = raw_window else {
            continue;
        };
        let Some(used_percent) = raw_window.get("used_percent").and_then(Value::as_f64) else {
            continue;
        };
        if !used_percent.is_finite() {
            continue;
        }
        let window_seconds = raw_window
            .get("limit_window_seconds")
            .and_then(value_as_i64)
            .filter(|seconds| *seconds > 0)
            .unwrap_or_default();
        let reset_at = raw_window
            .get("reset_at")
            .and_then(value_as_i64)
            .filter(|timestamp| *timestamp > 0)
            .or_else(|| {
                raw_window
                    .get("reset_after_seconds")
                    .and_then(value_as_i64)
                    .filter(|seconds| *seconds >= 0)
                    .map(|seconds| fetched_at + seconds)
            })
            .unwrap_or_default();
        let title = label
            .map(server_label)
            .unwrap_or_else(|| duration_title(window_seconds));
        output.push(QuotaWindow {
            id: format!("{limit_id}:{slot}"),
            title,
            used_percent: used_percent.clamp(0.0, 100.0),
            reset_at,
            window_seconds,
        });
    }
}

fn value_as_i64(value: &Value) -> Option<i64> {
    value
        .as_i64()
        .or_else(|| value.as_f64().map(|number| number.round() as i64))
}

fn parse_timestamp(value: &Value) -> Option<i64> {
    value_as_i64(value).or_else(|| {
        value
            .as_str()
            .and_then(|raw| DateTime::parse_from_rfc3339(raw).ok())
            .map(|date_time| date_time.timestamp())
    })
}

fn duration_title(seconds: i64) -> String {
    if seconds <= 0 {
        return "Custom limit".to_string();
    }
    if seconds % 604_800 == 0 {
        return format!("{}-week limit", seconds / 604_800);
    }
    if seconds % 86_400 == 0 {
        return format!("{}-day limit", seconds / 86_400);
    }
    if seconds % 3_600 == 0 {
        return format!("{}-hour limit", seconds / 3_600);
    }
    if seconds % 60 == 0 {
        return format!("{}-minute limit", seconds / 60);
    }
    "Custom limit".to_string()
}

fn server_label(value: &str) -> String {
    value
        .split(['_', '-'])
        .filter(|part| !part.is_empty())
        .map(|part| {
            let mut characters = part.chars();
            match characters.next() {
                Some(first) => format!("{}{}", first.to_uppercase(), characters.as_str()),
                None => String::new(),
            }
        })
        .collect::<Vec<_>>()
        .join(" ")
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::models::{CredentialStatus, LoginState};

    fn account() -> AccountInfo {
        AccountInfo {
            identity_hash: "account-hash".to_string(),
            email: Some("user@example.com".to_string()),
            plan: None,
            workspace_id: Some("workspace-1".to_string()),
            is_fedramp: false,
            login_state: LoginState::SignedIn,
            last_successful_refresh: None,
            credential_status: CredentialStatus::Available,
        }
    }

    fn fixture(name: &str) -> RawWhamUsage {
        let body = match name {
            "normal_with_additional" => {
                include_str!("../../tests/fixtures/normal_with_additional.json")
            }
            "one_window" => include_str!("../../tests/fixtures/one_window.json"),
            "malformed_window" => include_str!("../../tests/fixtures/malformed_window.json"),
            "unknown_and_missing" => include_str!("../../tests/fixtures/unknown_and_missing.json"),
            _ => panic!("unknown fixture"),
        };
        RawWhamUsage::parse(body).unwrap()
    }

    #[test]
    fn keeps_primary_secondary_and_additional_windows() {
        let snapshot = fixture("normal_with_additional").normalize(account(), 1_700_000_000);
        assert_eq!(snapshot.windows.len(), 3);
        assert_eq!(snapshot.windows[0].title, "5-hour limit");
        assert_eq!(snapshot.windows[1].title, "1-week limit");
        assert_eq!(snapshot.windows[2].title, "Codex Spark");
        assert_eq!(snapshot.reset_credits_available, Some(2));
    }

    #[test]
    fn supports_one_window_and_clamps_percentages() {
        let snapshot = fixture("one_window").normalize(account(), 1_700_000_000);
        assert_eq!(snapshot.windows.len(), 1);
        assert_eq!(snapshot.windows[0].used_percent, 100.0);
        assert_eq!(snapshot.windows[0].remaining_percent(), 0.0);
    }

    #[test]
    fn ignores_malformed_window_but_keeps_valid_ones() {
        let snapshot = fixture("malformed_window").normalize(account(), 1_700_000_000);
        assert_eq!(snapshot.windows.len(), 1);
        assert_eq!(snapshot.windows[0].used_percent, 0.0);
    }

    #[test]
    fn accepts_missing_optional_fields_and_unknown_fields() {
        let snapshot = fixture("unknown_and_missing").normalize(account(), 1_700_000_000);
        assert_eq!(snapshot.windows.len(), 1);
        assert_eq!(snapshot.windows[0].title, "Custom limit");
        assert_eq!(snapshot.reset_credits_available, None);
    }

    #[test]
    fn parses_credit_details_without_requiring_them() {
        let (count, credits) =
            parse_credit_details(include_str!("../../tests/fixtures/reset_credits.json")).unwrap();
        assert_eq!(count, Some(2));
        assert_eq!(credits.len(), 2);
        assert_eq!(credits[0].title.as_deref(), Some("Full reset"));
    }

    #[test]
    fn labels_unknown_duration_as_custom_limit() {
        assert_eq!(duration_title(17), "Custom limit");
    }

    #[test]
    fn now_helper_is_sane() {
        assert!(crate::auth::now_unix() > 1_700_000_000);
    }
}
