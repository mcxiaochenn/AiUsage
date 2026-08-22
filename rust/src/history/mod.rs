//! Seven-day local quota history. The schema never contains OAuth credentials
//! or raw OpenAI JSON.

use rusqlite::{Connection, OptionalExtension, params};

use crate::models::{
    AccountDetails, AccountInfo, HistoryPoint, ProfileUsage, SyncLogEntry, SyncTrigger,
    UsageSnapshot,
};

const RETENTION_SECONDS: i64 = 7 * 24 * 60 * 60;

pub struct HistoryRepository {
    connection: Connection,
}

impl HistoryRepository {
    pub fn open(database_path: &str) -> Result<Self, String> {
        let connection = Connection::open(database_path).map_err(sql_error)?;
        let mut repository = Self { connection };
        repository.migrate()?;
        repository.purge_expired(crate::auth::now_unix())?;
        Ok(repository)
    }

    pub fn record_snapshot(&mut self, snapshot: &UsageSnapshot) -> Result<(), String> {
        let transaction = self.connection.transaction().map_err(sql_error)?;
        transaction
            .execute(
                "INSERT INTO accounts (identity_hash, email, plan, last_successful_refresh, updated_at)
                 VALUES (?1, ?2, ?3, ?4, ?5)
                 ON CONFLICT(identity_hash) DO UPDATE SET
                   email = excluded.email,
                   plan = excluded.plan,
                   last_successful_refresh = excluded.last_successful_refresh,
                   updated_at = excluded.updated_at",
                params![
                    snapshot.account.identity_hash,
                    snapshot.account.email,
                    snapshot.account.plan,
                    snapshot.account.last_successful_refresh,
                    snapshot.fetched_at,
                ],
            )
            .map_err(sql_error)?;
        transaction
            .execute(
                "INSERT INTO usage_snapshots
                 (timestamp, account_identity_hash, reset_credits_available, reset_credits_json,
                  credits_has, credits_unlimited, credits_balance)
                 VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7)",
                params![
                    snapshot.fetched_at,
                    snapshot.account.identity_hash,
                    snapshot.reset_credits_available,
                    snapshot
                        .reset_credits
                        .as_ref()
                        .and_then(|value| serde_json::to_string(value).ok()),
                    snapshot.credits.as_ref().map(|value| value.has_credits),
                    snapshot.credits.as_ref().map(|value| value.unlimited),
                    snapshot
                        .credits
                        .as_ref()
                        .and_then(|value| value.balance.clone()),
                ],
            )
            .map_err(sql_error)?;
        let snapshot_id = transaction.last_insert_rowid();
        for window in &snapshot.windows {
            transaction
                .execute(
                    "INSERT INTO quota_windows
                     (snapshot_id, window_id, title, used_percent, reset_at, window_seconds)
                     VALUES (?1, ?2, ?3, ?4, ?5, ?6)",
                    params![
                        snapshot_id,
                        window.id,
                        window.title,
                        window.used_percent,
                        window.reset_at,
                        window.window_seconds,
                    ],
                )
                .map_err(sql_error)?;
        }
        transaction.commit().map_err(sql_error)?;
        self.purge_expired(snapshot.fetched_at)
    }

    pub fn latest_snapshot(&self, account: &AccountInfo) -> Result<Option<UsageSnapshot>, String> {
        let mut statement = self
            .connection
            .prepare(
                "SELECT id, timestamp, reset_credits_available, reset_credits_json,
                        credits_has, credits_unlimited, credits_balance
                 FROM usage_snapshots
                 WHERE account_identity_hash = ?1
                 ORDER BY timestamp DESC, id DESC LIMIT 1",
            )
            .map_err(sql_error)?;
        let row = statement
            .query_row([&account.identity_hash], |row| {
                Ok((
                    row.get::<_, i64>(0)?,
                    row.get::<_, i64>(1)?,
                    row.get::<_, Option<i64>>(2)?,
                    row.get::<_, Option<String>>(3)?,
                    row.get::<_, Option<bool>>(4)?,
                    row.get::<_, Option<bool>>(5)?,
                    row.get::<_, Option<String>>(6)?,
                ))
            })
            .optional()
            .map_err(sql_error)?;
        let Some((
            snapshot_id,
            fetched_at,
            reset_credits_available,
            reset_credits_json,
            credits_has,
            credits_unlimited,
            credits_balance,
        )) = row
        else {
            return Ok(None);
        };

        let mut windows_statement = self
            .connection
            .prepare(
                "SELECT window_id, title, used_percent, reset_at, window_seconds
                 FROM quota_windows WHERE snapshot_id = ?1 ORDER BY id ASC",
            )
            .map_err(sql_error)?;
        let windows = windows_statement
            .query_map([snapshot_id], |row| {
                Ok(crate::models::QuotaWindow {
                    id: row.get(0)?,
                    title: row.get(1)?,
                    used_percent: row.get(2)?,
                    reset_at: row.get(3)?,
                    window_seconds: row.get(4)?,
                })
            })
            .map_err(sql_error)?
            .collect::<Result<Vec<_>, _>>()
            .map_err(sql_error)?;
        Ok(Some(UsageSnapshot {
            account: account.clone(),
            windows,
            reset_credits_available,
            reset_credits: reset_credits_json.and_then(|value| serde_json::from_str(&value).ok()),
            credits: credits_has.map(|has_credits| crate::models::CreditsSnapshot {
                has_credits,
                unlimited: credits_unlimited.unwrap_or(false),
                balance: credits_balance,
            }),
            fetched_at,
        }))
    }

    pub fn save_account_details(
        &self,
        identity_hash: &str,
        details: &AccountDetails,
    ) -> Result<(), String> {
        let json = serde_json::to_string(details).map_err(|error| error.to_string())?;
        self.connection
            .execute(
                "INSERT INTO account_details (account_identity_hash, payload_json, fetched_at)
                 VALUES (?1, ?2, ?3)
                 ON CONFLICT(account_identity_hash) DO UPDATE SET
                   payload_json = excluded.payload_json, fetched_at = excluded.fetched_at",
                params![identity_hash, json, details.fetched_at],
            )
            .map_err(sql_error)?;
        Ok(())
    }

    pub fn account_details(&self, identity_hash: &str) -> Result<Option<AccountDetails>, String> {
        self.cached_json("account_details", identity_hash)
    }

    pub fn save_profile_usage(
        &self,
        identity_hash: &str,
        profile: &ProfileUsage,
    ) -> Result<(), String> {
        let json = serde_json::to_string(profile).map_err(|error| error.to_string())?;
        self.connection
            .execute(
                "INSERT INTO profile_usage (account_identity_hash, payload_json, fetched_at)
                 VALUES (?1, ?2, ?3)
                 ON CONFLICT(account_identity_hash) DO UPDATE SET
                   payload_json = excluded.payload_json, fetched_at = excluded.fetched_at",
                params![identity_hash, json, profile.fetched_at],
            )
            .map_err(sql_error)?;
        Ok(())
    }

    pub fn profile_usage(&self, identity_hash: &str) -> Result<Option<ProfileUsage>, String> {
        self.cached_json("profile_usage", identity_hash)
    }

    fn cached_json<T: serde::de::DeserializeOwned>(
        &self,
        table: &str,
        identity_hash: &str,
    ) -> Result<Option<T>, String> {
        let sql =
            format!("SELECT payload_json FROM {table} WHERE account_identity_hash = ?1 LIMIT 1");
        let payload = self
            .connection
            .query_row(&sql, [identity_hash], |row| row.get::<_, String>(0))
            .optional()
            .map_err(sql_error)?;
        payload
            .map(|value| serde_json::from_str(&value).map_err(|error| error.to_string()))
            .transpose()
    }

    #[allow(clippy::too_many_arguments)]
    pub fn record_sync_log(
        &self,
        identity_hash: &str,
        trigger: SyncTrigger,
        endpoint: &str,
        started_at: i64,
        duration_ms: i64,
        status_code: Option<i64>,
        result_state: &str,
        error_kind: Option<&str>,
        response_body: &str,
    ) -> Result<(), String> {
        const MAX_BODY_BYTES: usize = 64 * 1024;
        let sanitized = sanitize_response(response_body);
        let (response_body, truncated) = truncate_utf8(&sanitized, MAX_BODY_BYTES);
        self.connection
            .execute(
                "INSERT INTO sync_logs
                 (account_identity_hash, trigger, endpoint, started_at, duration_ms, status_code,
                  result_state, error_kind, response_body, truncated)
                 VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10)",
                params![
                    identity_hash,
                    format!("{trigger:?}"),
                    endpoint,
                    started_at,
                    duration_ms,
                    status_code,
                    result_state,
                    error_kind,
                    response_body,
                    truncated,
                ],
            )
            .map_err(sql_error)?;
        self.connection
            .execute(
                "DELETE FROM sync_logs WHERE id NOT IN
                 (SELECT id FROM sync_logs ORDER BY id DESC LIMIT 200)",
                [],
            )
            .map_err(sql_error)?;
        Ok(())
    }

    pub fn sync_logs(&self) -> Result<Vec<SyncLogEntry>, String> {
        let mut statement = self
            .connection
            .prepare(
                "SELECT id, account_identity_hash, trigger, endpoint, started_at, duration_ms,
                        status_code, result_state, error_kind, response_body, truncated
                 FROM sync_logs ORDER BY id DESC LIMIT 200",
            )
            .map_err(sql_error)?;
        statement
            .query_map([], |row| {
                let trigger: String = row.get(2)?;
                Ok(SyncLogEntry {
                    id: row.get(0)?,
                    account_identity_hash: row.get(1)?,
                    trigger: match trigger.as_str() {
                        "Resume" => SyncTrigger::Resume,
                        "ForegroundTimer" => SyncTrigger::ForegroundTimer,
                        "Background" => SyncTrigger::Background,
                        "PageLoad" => SyncTrigger::PageLoad,
                        _ => SyncTrigger::Manual,
                    },
                    endpoint: row.get(3)?,
                    started_at: row.get(4)?,
                    duration_ms: row.get(5)?,
                    status_code: row.get(6)?,
                    result_state: row.get(7)?,
                    error_kind: row.get(8)?,
                    response_body: row.get(9)?,
                    truncated: row.get(10)?,
                })
            })
            .map_err(sql_error)?
            .collect::<Result<Vec<_>, _>>()
            .map_err(sql_error)
    }

    pub fn history(&self, identity_hash: &str, since: i64) -> Result<Vec<HistoryPoint>, String> {
        let mut statement = self
            .connection
            .prepare(
                "SELECT snapshots.timestamp, windows.window_id, windows.used_percent
                 FROM usage_snapshots AS snapshots
                 JOIN quota_windows AS windows ON windows.snapshot_id = snapshots.id
                 WHERE snapshots.account_identity_hash = ?1 AND snapshots.timestamp >= ?2
                 ORDER BY snapshots.timestamp ASC, windows.window_id ASC",
            )
            .map_err(sql_error)?;
        statement
            .query_map(params![identity_hash, since], |row| {
                Ok(HistoryPoint {
                    timestamp: row.get(0)?,
                    window_id: row.get(1)?,
                    used_percent: row.get(2)?,
                })
            })
            .map_err(sql_error)?
            .collect::<Result<Vec<_>, _>>()
            .map_err(sql_error)
    }

    pub fn remove_account(&mut self, identity_hash: &str) -> Result<(), String> {
        self.connection
            .execute(
                "DELETE FROM quota_windows WHERE snapshot_id IN
                 (SELECT id FROM usage_snapshots WHERE account_identity_hash = ?1)",
                [identity_hash],
            )
            .map_err(sql_error)?;
        self.connection
            .execute(
                "DELETE FROM usage_snapshots WHERE account_identity_hash = ?1",
                [identity_hash],
            )
            .map_err(sql_error)?;
        self.connection
            .execute(
                "DELETE FROM accounts WHERE identity_hash = ?1",
                [identity_hash],
            )
            .map_err(sql_error)?;
        for table in ["account_details", "profile_usage", "sync_logs"] {
            self.connection
                .execute(
                    &format!("DELETE FROM {table} WHERE account_identity_hash = ?1"),
                    [identity_hash],
                )
                .map_err(sql_error)?;
        }
        Ok(())
    }

    pub fn purge_expired(&mut self, now: i64) -> Result<(), String> {
        let cutoff = now - RETENTION_SECONDS;
        self.connection
            .execute(
                "DELETE FROM quota_windows WHERE snapshot_id IN
                 (SELECT id FROM usage_snapshots WHERE timestamp < ?1)",
                [cutoff],
            )
            .map_err(sql_error)?;
        self.connection
            .execute("DELETE FROM usage_snapshots WHERE timestamp < ?1", [cutoff])
            .map_err(sql_error)?;
        self.connection
            .execute(
                "DELETE FROM accounts WHERE identity_hash NOT IN
                 (SELECT DISTINCT account_identity_hash FROM usage_snapshots)",
                [],
            )
            .map_err(sql_error)?;
        Ok(())
    }

    fn migrate(&self) -> Result<(), String> {
        self.connection
            .execute_batch(
                "PRAGMA foreign_keys = ON;
                 CREATE TABLE IF NOT EXISTS accounts (
                   identity_hash TEXT PRIMARY KEY NOT NULL,
                   email TEXT,
                   plan TEXT,
                   last_successful_refresh INTEGER,
                   updated_at INTEGER NOT NULL
                 );
                 CREATE TABLE IF NOT EXISTS usage_snapshots (
                   id INTEGER PRIMARY KEY AUTOINCREMENT,
                   timestamp INTEGER NOT NULL,
                   account_identity_hash TEXT NOT NULL,
                   reset_credits_available INTEGER,
                   reset_credits_json TEXT,
                   credits_has INTEGER,
                   credits_unlimited INTEGER,
                   credits_balance TEXT,
                   FOREIGN KEY(account_identity_hash) REFERENCES accounts(identity_hash)
                 );
                 CREATE TABLE IF NOT EXISTS quota_windows (
                   id INTEGER PRIMARY KEY AUTOINCREMENT,
                   snapshot_id INTEGER NOT NULL,
                   window_id TEXT NOT NULL,
                   title TEXT NOT NULL,
                   used_percent REAL NOT NULL,
                   reset_at INTEGER NOT NULL,
                   window_seconds INTEGER NOT NULL,
                   FOREIGN KEY(snapshot_id) REFERENCES usage_snapshots(id)
                 );
                 CREATE INDEX IF NOT EXISTS usage_snapshots_by_account_time
                   ON usage_snapshots(account_identity_hash, timestamp);
                 CREATE INDEX IF NOT EXISTS quota_windows_by_snapshot
                   ON quota_windows(snapshot_id);
                 CREATE TABLE IF NOT EXISTS account_details (
                   account_identity_hash TEXT PRIMARY KEY NOT NULL,
                   payload_json TEXT NOT NULL,
                   fetched_at INTEGER NOT NULL
                 );
                 CREATE TABLE IF NOT EXISTS profile_usage (
                   account_identity_hash TEXT PRIMARY KEY NOT NULL,
                   payload_json TEXT NOT NULL,
                   fetched_at INTEGER NOT NULL
                 );
                 CREATE TABLE IF NOT EXISTS sync_logs (
                   id INTEGER PRIMARY KEY AUTOINCREMENT,
                   account_identity_hash TEXT NOT NULL,
                   trigger TEXT NOT NULL,
                   endpoint TEXT NOT NULL,
                   started_at INTEGER NOT NULL,
                   duration_ms INTEGER NOT NULL,
                   status_code INTEGER,
                   result_state TEXT NOT NULL,
                   error_kind TEXT,
                   response_body TEXT NOT NULL,
                   truncated INTEGER NOT NULL DEFAULT 0
                 );
                 CREATE INDEX IF NOT EXISTS sync_logs_by_time ON sync_logs(id DESC);",
            )
            .map_err(sql_error)?;

        // Early development builds used the same schema without the optional
        // reset-credit count. Keep migrations additive so an installed MVP
        // never has to discard its seven-day cache when this field appears.
        let mut columns = self
            .connection
            .prepare("PRAGMA table_info(usage_snapshots)")
            .map_err(sql_error)?;
        let has_reset_credit_column = columns
            .query_map([], |row| row.get::<_, String>(1))
            .map_err(sql_error)?
            .collect::<Result<Vec<_>, _>>()
            .map_err(sql_error)?
            .iter()
            .any(|name| name == "reset_credits_available");
        if !has_reset_credit_column {
            self.connection
                .execute(
                    "ALTER TABLE usage_snapshots ADD COLUMN reset_credits_available INTEGER",
                    [],
                )
                .map_err(sql_error)?;
        }
        let columns = [
            ("reset_credits_json", "TEXT"),
            ("credits_has", "INTEGER"),
            ("credits_unlimited", "INTEGER"),
            ("credits_balance", "TEXT"),
        ];
        let existing = self
            .connection
            .prepare("PRAGMA table_info(usage_snapshots)")
            .and_then(|mut statement| {
                statement
                    .query_map([], |row| row.get::<_, String>(1))?
                    .collect::<Result<Vec<_>, _>>()
            })
            .map_err(sql_error)?;
        for (name, kind) in columns {
            if !existing.iter().any(|value| value == name) {
                self.connection
                    .execute(
                        &format!("ALTER TABLE usage_snapshots ADD COLUMN {name} {kind}"),
                        [],
                    )
                    .map_err(sql_error)?;
            }
        }
        Ok(())
    }
}

fn truncate_utf8(value: &str, max_bytes: usize) -> (String, bool) {
    if value.len() <= max_bytes {
        return (value.to_string(), false);
    }
    let mut end = max_bytes;
    while !value.is_char_boundary(end) {
        end -= 1;
    }
    (value[..end].to_string(), true)
}

fn sanitize_response(value: &str) -> String {
    let Ok(mut json) = serde_json::from_str::<serde_json::Value>(value) else {
        if sensitive_json_text(value) {
            return "[redacted non-JSON response]".to_string();
        }
        return value.to_string();
    };
    redact_value(&mut json);
    serde_json::to_string_pretty(&json).unwrap_or_else(|_| "[unavailable response]".to_string())
}

fn redact_value(value: &mut serde_json::Value) {
    match value {
        serde_json::Value::Object(map) => {
            for (key, value) in map {
                if sensitive_json_key(key, value) {
                    *value = serde_json::Value::String("[redacted]".to_string());
                } else {
                    redact_value(value);
                }
            }
        }
        serde_json::Value::Array(items) => {
            for item in items {
                redact_value(item);
            }
        }
        serde_json::Value::String(text) if sensitive_json_text(text) => {
            *text = "[redacted]".to_string();
        }
        _ => {}
    }
}

fn sensitive_json_key(key: &str, value: &serde_json::Value) -> bool {
    let lower = key.to_ascii_lowercase();
    let compact = lower
        .chars()
        .filter(|character| character.is_ascii_alphanumeric())
        .collect::<String>();
    let numeric_usage_tokens = compact.ends_with("tokens") && value.is_number();
    lower == "id"
        || lower.ends_with("_id")
        || lower.ends_with("-id")
        || (compact.contains("token") && !numeric_usage_tokens)
        || compact.contains("authorization")
        || compact.contains("apikey")
        || compact.contains("clientsecret")
        || [
            "accountid",
            "workspaceid",
            "userid",
            "organizationid",
            "projectid",
            "apikeyid",
        ]
        .iter()
        .any(|suffix| compact.ends_with(suffix))
}

fn sensitive_json_text(value: &str) -> bool {
    let lower = value.to_ascii_lowercase();
    [
        "authorization",
        "bearer ",
        "access_token",
        "refresh_token",
        "id_token",
        "sk-",
        "chatgpt-account-id",
        "chatgpt_account_id",
        "chatgptaccountid",
        "account-id",
        "account_id",
        "accountid",
        "workspace-id",
        "workspace_id",
        "workspaceid",
    ]
    .iter()
    .any(|needle| lower.contains(needle))
}

fn sql_error(error: rusqlite::Error) -> String {
    format!("SQLite error: {error}")
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::models::{CredentialStatus, LoginState, QuotaWindow};

    fn snapshot(timestamp: i64) -> UsageSnapshot {
        UsageSnapshot {
            account: AccountInfo {
                identity_hash: "account-hash".to_string(),
                email: Some("user@example.com".to_string()),
                plan: Some("pro".to_string()),
                workspace_id: None,
                is_fedramp: false,
                login_state: LoginState::SignedIn,
                last_successful_refresh: Some(timestamp),
                credential_status: CredentialStatus::Available,
            },
            windows: vec![QuotaWindow {
                id: "codex:primary".to_string(),
                title: "1-hour limit".to_string(),
                used_percent: 42.0,
                reset_at: timestamp + 100,
                window_seconds: 3600,
            }],
            reset_credits_available: Some(2),
            reset_credits: None,
            credits: None,
            fetched_at: timestamp,
        }
    }

    #[test]
    fn records_loads_and_purges_history() {
        let mut repository = HistoryRepository {
            connection: Connection::open_in_memory().unwrap(),
        };
        repository.migrate().unwrap();
        repository
            .record_snapshot(&snapshot(1_700_000_000))
            .unwrap();
        let cached = repository
            .latest_snapshot(&snapshot(1_700_000_000).account)
            .unwrap()
            .unwrap();
        assert_eq!(cached.windows[0].used_percent, 42.0);
        assert_eq!(
            repository
                .history("account-hash", 1_699_999_000)
                .unwrap()
                .len(),
            1
        );
        repository
            .purge_expired(1_700_000_000 + RETENTION_SECONDS + 1)
            .unwrap();
        assert!(
            repository
                .latest_snapshot(&snapshot(1_700_000_000).account)
                .unwrap()
                .is_none()
        );
    }

    #[test]
    fn upgrades_the_pre_credit_snapshot_schema_without_dropping_history() {
        let connection = Connection::open_in_memory().unwrap();
        connection
            .execute_batch(
                "CREATE TABLE accounts (
                   identity_hash TEXT PRIMARY KEY NOT NULL,
                   email TEXT, plan TEXT, last_successful_refresh INTEGER, updated_at INTEGER NOT NULL
                 );
                 CREATE TABLE usage_snapshots (
                   id INTEGER PRIMARY KEY AUTOINCREMENT,
                   timestamp INTEGER NOT NULL,
                   account_identity_hash TEXT NOT NULL
                 );
                 CREATE TABLE quota_windows (
                   id INTEGER PRIMARY KEY AUTOINCREMENT,
                   snapshot_id INTEGER NOT NULL,
                   window_id TEXT NOT NULL, title TEXT NOT NULL, used_percent REAL NOT NULL,
                   reset_at INTEGER NOT NULL, window_seconds INTEGER NOT NULL
                 );",
            )
            .unwrap();
        let mut repository = HistoryRepository { connection };
        repository.migrate().unwrap();
        repository
            .record_snapshot(&snapshot(1_700_000_000))
            .unwrap();
        assert_eq!(
            repository
                .latest_snapshot(&snapshot(1_700_000_000).account)
                .unwrap()
                .unwrap()
                .reset_credits_available,
            Some(2)
        );
    }

    #[test]
    fn diagnostics_are_redacted_truncated_and_bounded() {
        let repository = HistoryRepository {
            connection: Connection::open_in_memory().unwrap(),
        };
        repository.migrate().unwrap();
        let sensitive = format!(
            "{{\"access_token\":\"secret\",\"account_id\":\"raw\",\"ChatGPT-Account-Id\":\"header-raw\",\"accountId\":\"camel-raw\",\"message\":\"Authorization: Bearer embedded-secret\",\"body\":\"{}\"}}",
            "x".repeat(70 * 1024)
        );
        for index in 0..205 {
            repository
                .record_sync_log(
                    "account-hash",
                    SyncTrigger::Manual,
                    "usage",
                    index,
                    10,
                    Some(200),
                    "fresh",
                    None,
                    &sensitive,
                )
                .unwrap();
        }
        let logs = repository.sync_logs().unwrap();
        assert_eq!(logs.len(), 200);
        assert!(logs[0].truncated);
        assert!(!logs[0].response_body.contains("secret"));
        assert!(!logs[0].response_body.contains("raw"));
        assert!(!logs[0].response_body.contains("Bearer"));
    }

    #[test]
    fn diagnostic_sanitizer_keeps_usage_numbers_and_redacts_credentials() {
        let sanitized = sanitize_response(
            r#"{
                "stats":{"lifetime_tokens":123,"peak_daily_tokens":45},
                "daily_usage_buckets":[{"start_date":"2026-08-21","tokens":12}],
                "apiKey":"sk-key-secret",
                "client_secret":"client-secret",
                "x-authorization":"credential",
                "message":"upstream rejected sk-embedded-secret"
            }"#,
        );

        assert!(sanitized.contains("123"));
        assert!(sanitized.contains("45"));
        assert!(sanitized.contains("12"));
        assert!(!sanitized.contains("sk-key-secret"));
        assert!(!sanitized.contains("client-secret"));
        assert!(!sanitized.contains("credential"));
        assert!(!sanitized.contains("sk-embedded-secret"));

        for plain_text in [
            "upstream rejected sk-proj-secret",
            "ChatGPT-Account-Id: raw-account",
            "workspaceId=raw-workspace",
        ] {
            assert_eq!(
                sanitize_response(plain_text),
                "[redacted non-JSON response]"
            );
        }
    }

    #[test]
    fn removing_account_clears_profile_details_and_diagnostics() {
        let mut repository = HistoryRepository {
            connection: Connection::open_in_memory().unwrap(),
        };
        repository.migrate().unwrap();
        let sample = snapshot(1_700_000_000);
        repository.record_snapshot(&sample).unwrap();
        let details = AccountDetails {
            created_at: 1,
            email: None,
            fetched_at: 2,
        };
        repository
            .save_account_details("account-hash", &details)
            .unwrap();
        repository
            .record_sync_log(
                "account-hash",
                SyncTrigger::PageLoad,
                "account-details",
                1,
                1,
                Some(200),
                "fresh",
                None,
                "{}",
            )
            .unwrap();
        repository.remove_account("account-hash").unwrap();
        assert!(
            repository
                .account_details("account-hash")
                .unwrap()
                .is_none()
        );
        assert!(repository.sync_logs().unwrap().is_empty());
    }
}
