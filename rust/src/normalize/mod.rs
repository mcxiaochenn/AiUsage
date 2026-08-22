//! Tolerant translation from undocumented OpenAI JSON to stable domain models.

use chrono::{DateTime, NaiveDate};
use serde_json::Value;

use crate::models::{
    AccountDetails, AccountInfo, CreditsSnapshot, DailyTokenBucket, ProfileUsage, QuotaWindow,
    ResetCredit, TokenUsageSummary, UsageSnapshot,
};

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
            credits: self.value.get("credits").map(|credits| CreditsSnapshot {
                has_credits: credits
                    .get("has_credits")
                    .and_then(Value::as_bool)
                    .unwrap_or(false),
                unlimited: credits
                    .get("unlimited")
                    .and_then(Value::as_bool)
                    .unwrap_or(false),
                balance: credits.get("balance").and_then(|value| match value {
                    Value::String(value) => Some(value.clone()),
                    Value::Number(value) => Some(value.to_string()),
                    _ => None,
                }),
            }),
            fetched_at,
        }
    }
}

pub fn parse_profile_usage(body: &str, fetched_at: i64) -> Result<ProfileUsage, String> {
    let value: Value = serde_json::from_str(body)
        .map_err(|error| format!("schema_mismatch: Invalid Profile JSON: {error}"))?;
    let stats = value.get("stats").unwrap_or(&value);
    if value
        .get("metadata")
        .and_then(|metadata| metadata.get("stats_error"))
        .is_some_and(non_empty_json_value)
    {
        return Err("backend_stats_error: Profile statistics are unavailable".to_string());
    }
    let number = |name: &str| {
        stats
            .get(name)
            .or_else(|| value.get(name))
            .and_then(value_as_i64)
    };
    let raw_buckets = stats
        .get("daily_usage_buckets")
        .or_else(|| value.get("daily_usage_buckets"))
        .ok_or_else(|| "schema_mismatch: Profile daily_usage_buckets is missing".to_string())?;
    let items = raw_buckets.as_array().ok_or_else(|| {
        "schema_mismatch: Profile daily_usage_buckets is not an array".to_string()
    })?;
    let daily_usage_buckets = items
        .iter()
        .filter_map(|item| {
            let start_date = item.get("start_date")?.as_str()?;
            if NaiveDate::parse_from_str(start_date, "%Y-%m-%d").is_err() {
                return None;
            }
            Some(DailyTokenBucket {
                start_date: start_date.to_string(),
                tokens: item.get("tokens").and_then(value_as_i64)?.max(0),
            })
        })
        .collect::<Vec<_>>();
    if !items.is_empty() && daily_usage_buckets.is_empty() {
        return Err(
            "schema_mismatch: Profile daily_usage_buckets contains no valid entries".to_string(),
        );
    }
    Ok(ProfileUsage {
        summary: TokenUsageSummary {
            lifetime_tokens: number("lifetime_tokens"),
            peak_daily_tokens: number("peak_daily_tokens"),
            longest_running_turn_sec: number("longest_running_turn_sec"),
            current_streak_days: number("current_streak_days"),
            longest_streak_days: number("longest_streak_days"),
        },
        daily_usage_buckets,
        fetched_at,
    })
}

fn non_empty_json_value(value: &Value) -> bool {
    match value {
        Value::Null => false,
        Value::Bool(value) => *value,
        Value::Number(value) => value.as_f64().is_some_and(|value| value != 0.0),
        Value::String(value) => !value.trim().is_empty(),
        Value::Array(value) => !value.is_empty(),
        Value::Object(value) => !value.is_empty(),
    }
}

pub fn parse_account_details(body: &str, fetched_at: i64) -> Result<AccountDetails, String> {
    let value: Value = serde_json::from_str(body).map_err(|error| error.to_string())?;
    let created_at = value
        .get("created")
        .and_then(value_as_i64)
        .filter(|value| *value > 0)
        .ok_or_else(|| "Account creation time is unavailable".to_string())?;
    Ok(AccountDetails {
        created_at,
        email: value
            .get("email")
            .and_then(Value::as_str)
            .map(ToOwned::to_owned),
        fetched_at,
    })
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
    fn parses_finite_and_unlimited_credit_balances() {
        let finite = RawWhamUsage::parse(
            r#"{"credits":{"has_credits":true,"unlimited":false,"balance":"9.99"}}"#,
        )
        .unwrap()
        .normalize(account(), 1);
        assert_eq!(finite.credits.unwrap().balance.as_deref(), Some("9.99"));

        let unlimited = RawWhamUsage::parse(
            r#"{"credits":{"has_credits":true,"unlimited":true,"balance":null}}"#,
        )
        .unwrap()
        .normalize(account(), 1);
        assert!(unlimited.credits.unwrap().unlimited);
    }

    #[test]
    fn parses_profile_summary_daily_buckets_and_account_creation() {
        let profile = parse_profile_usage(
            r#"{"stats":{"lifetime_tokens":123,"peak_daily_tokens":50,"current_streak_days":2},"daily_usage_buckets":[{"start_date":"2026-08-22","tokens":12}]}"#,
            100,
        )
        .unwrap();
        assert_eq!(profile.summary.lifetime_tokens, Some(123));
        assert_eq!(profile.daily_usage_buckets[0].tokens, 12);

        let details = parse_account_details(
            r#"{"created":1700000000,"email":"user@example.com","orgs":{"data":[{"created":1}]}}"#,
            101,
        )
        .unwrap();
        assert_eq!(details.created_at, 1_700_000_000);
        assert!(parse_account_details(r#"{"email":"user@example.com"}"#, 1).is_err());
    }

    #[test]
    fn parses_nested_profile_daily_buckets_before_legacy_top_level_buckets() {
        let profile = parse_profile_usage(
            r#"{
                "stats": {
                    "lifetime_tokens": 123,
                    "daily_usage_buckets": [
                        {"start_date":"2026-08-20","tokens":12},
                        {"start_date":"2026-08-19","tokens":-4}
                    ]
                },
                "daily_usage_buckets": [
                    {"start_date":"legacy","tokens":999}
                ]
            }"#,
            100,
        )
        .unwrap();

        assert_eq!(profile.daily_usage_buckets.len(), 2);
        assert_eq!(profile.daily_usage_buckets[0].start_date, "2026-08-20");
        assert_eq!(profile.daily_usage_buckets[0].tokens, 12);
        assert_eq!(profile.daily_usage_buckets[1].start_date, "2026-08-19");
        assert_eq!(profile.daily_usage_buckets[1].tokens, 0);
    }

    #[test]
    fn accepts_empty_profile_buckets_and_keeps_valid_partial_entries() {
        let empty = parse_profile_usage(r#"{"stats":{"daily_usage_buckets":[]}}"#, 1).unwrap();
        assert!(empty.daily_usage_buckets.is_empty());

        let partial = parse_profile_usage(
            r#"{"stats":{"daily_usage_buckets":[
                {"start_date":"not-a-date","tokens":5},
                {"start_date":"2026-02-30","tokens":6},
                {"start_date":"2026-08-20","tokens":7},
                {"tokens":9}
            ]}}"#,
            2,
        )
        .unwrap();
        assert_eq!(partial.daily_usage_buckets.len(), 1);
        assert_eq!(partial.daily_usage_buckets[0].start_date, "2026-08-20");
    }

    #[test]
    fn rejects_missing_null_wrong_type_and_entirely_invalid_profile_buckets() {
        for body in [
            r#"{"stats":{"lifetime_tokens":1}}"#,
            r#"{"stats":{"daily_usage_buckets":null}}"#,
            r#"{"stats":{"daily_usage_buckets":{}}}"#,
            r#"{"stats":{"daily_usage_buckets":[{"start_date":"2026-02-30","tokens":4}]}}"#,
        ] {
            let error = parse_profile_usage(body, 1).unwrap_err();
            assert!(
                error.contains("schema_mismatch"),
                "unexpected error: {error}"
            );
        }
    }

    #[test]
    fn rejects_profile_backend_stats_errors() {
        let error = parse_profile_usage(
            r#"{"metadata":{"stats_error":"daily stats unavailable"},"stats":{"daily_usage_buckets":[]}}"#,
            1,
        )
        .unwrap_err();
        assert!(error.contains("backend_stats_error"));

        for stats_error in ["false", "0"] {
            let body = format!(
                r#"{{"metadata":{{"stats_error":{stats_error}}},"stats":{{"daily_usage_buckets":[]}}}}"#
            );
            assert!(parse_profile_usage(&body, 1).is_ok());
        }
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
