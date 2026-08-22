//! Seven-day local quota history. The schema never contains OAuth credentials
//! or raw OpenAI JSON.

use rusqlite::{Connection, OptionalExtension, params};

use crate::models::{AccountInfo, HistoryPoint, UsageSnapshot};

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
                "INSERT INTO usage_snapshots (timestamp, account_identity_hash, reset_credits_available)
                 VALUES (?1, ?2, ?3)",
                params![
                    snapshot.fetched_at,
                    snapshot.account.identity_hash,
                    snapshot.reset_credits_available,
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
                "SELECT id, timestamp, reset_credits_available FROM usage_snapshots
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
                ))
            })
            .optional()
            .map_err(sql_error)?;
        let Some((snapshot_id, fetched_at, reset_credits_available)) = row else {
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
            reset_credits: None,
            fetched_at,
        }))
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
                   ON quota_windows(snapshot_id);",
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
        Ok(())
    }
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
}
