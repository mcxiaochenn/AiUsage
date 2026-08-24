use std::sync::Arc;
use std::time::{Duration, Instant};

use base64::{Engine as _, engine::general_purpose::STANDARD};
use chrono::{DateTime, Local, NaiveDateTime};
use reqwest::cookie::{CookieStore, Jar};
use reqwest::header::{COOKIE, LOCATION};
use reqwest::{Client, StatusCode, Url, redirect::Policy};
use serde_json::Value;
use sha1::{Digest as _, Sha1};
use zeroize::Zeroize;

use crate::api::codex::{ApiFailure, HttpObservation};
use crate::auth;
use crate::models::{
    AccountInfo, BalanceMetric, CredentialStatus, LoginState, MimoCredential, MimoLoginResult,
    ProviderKind, ProviderQuotaMetric,
};

const API_ROOT: &str = "https://platform.xiaomimimo.com/api/v1";
const PLATFORM_ROOT: &str = "https://platform.xiaomimimo.com/";
const ACCOUNT_ROOT: &str = "https://account.xiaomi.com/";

#[derive(Clone, Debug)]
pub(crate) struct MimoProvider {
    client: Client,
    api_client: Client,
}

impl MimoProvider {
    pub(crate) fn production() -> Result<Self, String> {
        let client = Client::builder()
            .connect_timeout(Duration::from_secs(12))
            .timeout(Duration::from_secs(25))
            .build()
            .map_err(|error| format!("MiMo HTTP client setup failed: {error}"))?;
        let api_client = Client::builder()
            .connect_timeout(Duration::from_secs(12))
            .timeout(Duration::from_secs(25))
            .redirect(Policy::none())
            .build()
            .map_err(|error| format!("MiMo API client setup failed: {error}"))?;
        Ok(Self { client, api_client })
    }

    pub(crate) async fn login(
        &self,
        username: String,
        mut password: String,
    ) -> Result<MimoLoginResult, String> {
        let result = self.login_inner(username.trim(), &password).await;
        password.zeroize();
        result
    }

    async fn login_inner(&self, username: &str, password: &str) -> Result<MimoLoginResult, String> {
        if username.is_empty() || password.is_empty() || username.contains(['\r', '\n']) {
            return Err("mimo_login.invalid_credentials".to_string());
        }
        let login_url = self.login_url().await?;
        let login_meta = self.login_metadata(&login_url, None).await?;
        let sid = string_at(&login_meta, &["sid"]).unwrap_or_else(|| "passport".to_string());
        let form = [
            ("qs", string_at(&login_meta, &["qs"]).unwrap_or_default()),
            ("sid", sid),
            (
                "_sign",
                string_at(&login_meta, &["_sign"]).unwrap_or_default(),
            ),
            (
                "callback",
                string_at(&login_meta, &["callback"]).unwrap_or_default(),
            ),
            ("user", username.to_string()),
            ("hash", format!("{:X}", md5::compute(password.as_bytes()))),
        ];
        let response = self
            .client
            .post("https://account.xiaomi.com/pass/serviceLoginAuth2")
            .query(&[("_json", "true")])
            .header("User-Agent", "AiUsage/0.1 PassportSDK")
            .form(&form)
            .send()
            .await
            .map_err(|_| "mimo_login.transport".to_string())?;
        let value = parse_xiaomi_json(&response.text().await.unwrap_or_default())?;
        let code = value.get("code").and_then(Value::as_i64).unwrap_or(-1);
        let challenge = string_at(&value, &["notificationUrl"])
            .or_else(|| string_at(&value, &["captchaUrl"]))
            .or_else(|| string_at(&value, &["location"]));
        let user_id = string_value(value.get("userId"));
        let pass_token = string_at(&value, &["passToken"]);
        if code != 0 || user_id.is_none() || pass_token.is_none() {
            return Ok(MimoLoginResult {
                account: None,
                credential: None,
                challenge_url: Some(challenge.unwrap_or(login_url)),
            });
        }
        let user_id = user_id.unwrap_or_default();
        let pass_token = pass_token.unwrap_or_default();
        let credential = self
            .finish_sso(&value, &user_id, &pass_token)
            .await
            .map_err(|_| "mimo_login.challenge_required".to_string())?;
        Ok(MimoLoginResult {
            account: Some(account(&user_id)),
            credential: Some(credential),
            challenge_url: None,
        })
    }

    pub(crate) fn credential_from_web_cookies(
        &self,
        account_cookie: &str,
        platform_cookie: &str,
    ) -> Result<MimoLoginResult, String> {
        let account_values = parse_cookie_header(account_cookie)?;
        let platform_values = parse_cookie_header(platform_cookie)?;
        let read = |values: &[(String, String)], key: &str| {
            values
                .iter()
                .find(|(name, _)| name == key)
                .map(|(_, value)| value.clone())
                .filter(|value| !value.is_empty())
        };
        let user_id = read(&account_values, "userId")
            .or_else(|| read(&platform_values, "userId"))
            .ok_or_else(|| "mimo_login.missing_user_id".to_string())?;
        let credential = MimoCredential {
            user_id: user_id.clone(),
            pass_token: read(&account_values, "passToken")
                .ok_or_else(|| "mimo_login.missing_pass_token".to_string())?,
            service_token: read(&platform_values, "api-platform_serviceToken")
                .ok_or_else(|| "mimo_login.missing_service_token".to_string())?,
            service_slh: read(&platform_values, "api-platform_slh").unwrap_or_default(),
            service_ph: read(&platform_values, "api-platform_ph").unwrap_or_default(),
        };
        Ok(MimoLoginResult {
            account: Some(account(&user_id)),
            credential: Some(credential),
            challenge_url: None,
        })
    }

    pub(crate) async fn renew(
        &self,
        credential: &MimoCredential,
    ) -> Result<MimoCredential, String> {
        let login_url = self.login_url().await?;
        let jar = Arc::new(Jar::default());
        let account_url = Url::parse(ACCOUNT_ROOT).map_err(|_| "mimo_login.invalid_url")?;
        jar.add_cookie_str(
            &format!("userId={}; Path=/", credential.user_id),
            &account_url,
        );
        jar.add_cookie_str(
            &format!("passToken={}; Path=/", credential.pass_token),
            &account_url,
        );
        let client = cookie_client(Arc::clone(&jar))?;
        let response = client
            .get(&login_url)
            .send()
            .await
            .map_err(|_| "mimo_login.transport".to_string())?;
        let final_body = response.text().await.unwrap_or_default();
        if let Ok(value) = parse_xiaomi_json(&final_body) {
            if value.get("code").and_then(Value::as_i64).unwrap_or(-1) != 0 {
                return Err("mimo_login.reauthentication_required".to_string());
            }
            follow_sso_location(&client, &value).await?;
        }
        credential_from_jar(&jar, &credential.user_id, &credential.pass_token)
            .ok_or_else(|| "mimo_login.reauthentication_required".to_string())
    }

    pub(crate) async fn balance_json(&self, credential: &MimoCredential) -> HttpObservation {
        self.get_json("mimo-balance", "/balance", credential).await
    }

    pub(crate) async fn token_plan_detail_json(
        &self,
        credential: &MimoCredential,
    ) -> HttpObservation {
        self.get_json("mimo-token-plan-detail", "/tokenPlan/detail", credential)
            .await
    }

    pub(crate) async fn token_plan_usage_json(
        &self,
        credential: &MimoCredential,
    ) -> HttpObservation {
        self.get_json("mimo-token-plan-usage", "/tokenPlan/usage", credential)
            .await
    }

    async fn get_json(
        &self,
        endpoint: &str,
        path: &str,
        credential: &MimoCredential,
    ) -> HttpObservation {
        let started = Instant::now();
        let response = self
            .api_client
            .get(format!("{API_ROOT}{path}"))
            .header(COOKIE, platform_cookie_header(credential))
            .header("Accept", "application/json, text/plain, */*")
            .header("Accept-Language", "en-US,en;q=0.9")
            .header("Origin", "https://platform.xiaomimimo.com")
            .header(
                "Referer",
                "https://platform.xiaomimimo.com/#/console/balance",
            )
            .header("x-timeZone", local_time_zone_header())
            .header("User-Agent", "AiUsage/0.1 (Android; MiMo console client)")
            .send()
            .await;
        let response = match response {
            Ok(value) => value,
            Err(error) => {
                return HttpObservation {
                    endpoint: endpoint.to_string(),
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
        let body = response.text().await.unwrap_or_default();
        let envelope_unauthorized = serde_json::from_str::<Value>(&body)
            .ok()
            .and_then(|value| integer_value(value.get("code")))
            .is_some_and(|code| matches!(code, 401 | 1001 | 10001));
        let failure = if status.is_success() && !envelope_unauthorized {
            None
        } else if status == StatusCode::UNAUTHORIZED
            || status == StatusCode::FORBIDDEN
            || status.is_redirection()
            || envelope_unauthorized
        {
            Some(ApiFailure::Unauthorized)
        } else if status == StatusCode::TOO_MANY_REQUESTS {
            Some(ApiFailure::RateLimited(None))
        } else if status.is_server_error() {
            Some(ApiFailure::Server)
        } else {
            Some(ApiFailure::Other)
        };
        HttpObservation {
            endpoint: endpoint.to_string(),
            status_code: Some(i64::from(status.as_u16())),
            body,
            duration_ms: started.elapsed().as_millis() as i64,
            failure,
        }
    }

    async fn login_url(&self) -> Result<String, String> {
        let response = self
            .api_client
            .get(format!("{API_ROOT}/genLoginUrl"))
            .header("Accept", "application/json")
            .send()
            .await
            .map_err(|_| "mimo_login.transport".to_string())?;
        let status = response.status();
        let location = response
            .headers()
            .get(LOCATION)
            .and_then(|value| value.to_str().ok())
            .map(str::to_string);
        let body = response.text().await.unwrap_or_default();
        parse_login_url_response(status, location.as_deref(), &body)
    }

    async fn login_metadata(
        &self,
        login_url: &str,
        cookies: Option<&str>,
    ) -> Result<Value, String> {
        let mut request = self
            .client
            .get(login_url)
            .query(&[("_json", "true")])
            .header("User-Agent", "AiUsage/0.1 PassportSDK");
        if let Some(cookies) = cookies {
            request = request.header(COOKIE, cookies);
        }
        let response = request
            .send()
            .await
            .map_err(|_| "mimo_login.transport".to_string())?;
        parse_xiaomi_json(&response.text().await.unwrap_or_default())
    }

    async fn finish_sso(
        &self,
        login: &Value,
        user_id: &str,
        pass_token: &str,
    ) -> Result<MimoCredential, String> {
        let jar = Arc::new(Jar::default());
        let client = cookie_client(Arc::clone(&jar))?;
        follow_sso_location(&client, login).await?;
        credential_from_jar(&jar, user_id, pass_token)
            .ok_or_else(|| "mimo_login.challenge_required".to_string())
    }
}

pub(crate) fn parse_balance(body: &str) -> Result<Vec<BalanceMetric>, String> {
    let root: Value = serde_json::from_str(body)
        .map_err(|_| "schema_mismatch: MiMo balance response is invalid".to_string())?;
    ensure_envelope_success(&root)?;
    let data = root.get("data").unwrap_or(&root);
    let currency = data
        .get("currency")
        .and_then(Value::as_str)
        .filter(|value| !value.trim().is_empty())
        .map(str::to_string);
    let fields = [
        ("total", "Total balance", "balance", true),
        ("cash", "Cash balance", "cashBalance", false),
        ("gift", "Gift balance", "giftBalance", false),
        ("frozen", "Frozen balance", "frozenBalance", false),
        ("overdraft", "Overdraft limit", "overdraftLimit", false),
        (
            "remaining-overdraft",
            "Remaining overdraft",
            "remainingOverdraftLimit",
            false,
        ),
    ];
    let metrics = fields
        .into_iter()
        .filter_map(|(id, label, key, primary)| {
            decimal_text(data.get(key)?).map(|amount| BalanceMetric {
                id: format!("mimo:{id}"),
                label: label.to_string(),
                amount,
                currency: currency.clone(),
                primary,
            })
        })
        .collect::<Vec<_>>();
    if metrics.is_empty() {
        return Err("schema_mismatch: MiMo balance contains no valid amounts".to_string());
    }
    Ok(metrics)
}

pub(crate) fn parse_token_plan(
    detail_body: Option<&str>,
    usage_body: &str,
) -> Result<Vec<ProviderQuotaMetric>, String> {
    let root: Value = serde_json::from_str(usage_body)
        .map_err(|_| "schema_mismatch: MiMo token plan response is invalid".to_string())?;
    ensure_envelope_success(&root)?;
    let items_value = root
        .pointer("/data/monthUsage/items")
        .or_else(|| root.pointer("/data/usage/items"))
        .or_else(|| root.pointer("/usage/items"))
        .ok_or_else(|| "schema_mismatch: MiMo token plan items are missing".to_string())?;
    if items_value.is_null() {
        return Ok(Vec::new());
    }
    let items = items_value
        .as_array()
        .ok_or_else(|| "schema_mismatch: MiMo token plan items are invalid".to_string())?;
    let expires_at = detail_body.and_then(parse_plan_expiry);
    let mut output = Vec::new();
    for item in items {
        let Some(name) = item.get("name").and_then(Value::as_str) else {
            continue;
        };
        let title = match name {
            "plan_total_token" => "Plan tokens",
            "compensation_total_token" => "Compensation tokens",
            _ => name,
        };
        let Some(used) = integer_value(item.get("used")) else {
            continue;
        };
        let Some(limit) = integer_value(item.get("limit")) else {
            continue;
        };
        let remaining = (limit - used).max(0);
        let percent = if limit > 0 {
            ((used as f64 / limit as f64) * 100.0).clamp(0.0, 100.0)
        } else {
            0.0
        };
        output.push(ProviderQuotaMetric {
            id: format!("mimo:{name}"),
            title: title.to_string(),
            used: used.to_string(),
            limit: limit.to_string(),
            remaining: remaining.to_string(),
            used_percent: percent,
            expires_at,
            unit: "tokens".to_string(),
        });
    }
    if !items.is_empty() && output.is_empty() {
        return Err("schema_mismatch: MiMo token plan contains no supported items".to_string());
    }
    Ok(output)
}

fn account(user_id: &str) -> AccountInfo {
    AccountInfo {
        provider: ProviderKind::Mimo,
        identity_hash: auth::provider_identity_hash("mimo", user_id),
        email: None,
        plan: Some("MiMo".to_string()),
        workspace_id: None,
        is_fedramp: false,
        login_state: LoginState::SignedIn,
        last_successful_refresh: None,
        credential_status: CredentialStatus::Available,
    }
}

fn cookie_client(jar: Arc<Jar>) -> Result<Client, String> {
    Client::builder()
        .cookie_provider(jar)
        .connect_timeout(Duration::from_secs(12))
        .timeout(Duration::from_secs(30))
        .build()
        .map_err(|_| "mimo_login.client_setup".to_string())
}

async fn follow_sso_location(client: &Client, value: &Value) -> Result<(), String> {
    let location = string_at(value, &["location"])
        .filter(|value| allowed_login_url(value))
        .ok_or_else(|| "mimo_login.challenge_required".to_string())?;
    let nonce = value.get("nonce").and_then(Value::as_i64);
    let security = string_at(value, &["ssecurity"]);
    let mut url = Url::parse(&location).map_err(|_| "mimo_login.invalid_url".to_string())?;
    if let (Some(nonce), Some(security)) = (nonce, security) {
        let sign = STANDARD.encode(Sha1::digest(format!("nonce={nonce}&{security}").as_bytes()));
        url.query_pairs_mut().append_pair("clientSign", &sign);
    }
    let response = client
        .get(url)
        .send()
        .await
        .map_err(|_| "mimo_login.transport".to_string())?;
    if !response.status().is_success() {
        return Err("mimo_login.challenge_required".to_string());
    }
    Ok(())
}

fn credential_from_jar(jar: &Jar, user_id: &str, pass_token: &str) -> Option<MimoCredential> {
    let url = Url::parse(PLATFORM_ROOT).ok()?;
    let header = jar.cookies(&url)?.to_str().ok()?.to_string();
    let values = parse_cookie_header(&header).ok()?;
    let read = |key: &str| {
        values
            .iter()
            .find(|(name, _)| name == key)
            .map(|(_, value)| value.clone())
    };
    Some(MimoCredential {
        user_id: user_id.to_string(),
        pass_token: pass_token.to_string(),
        service_token: read("api-platform_serviceToken")?,
        service_slh: read("api-platform_slh").unwrap_or_default(),
        service_ph: read("api-platform_ph").unwrap_or_default(),
    })
}

fn platform_cookie_header(credential: &MimoCredential) -> String {
    let mut values = vec![
        format!("userId={}", credential.user_id),
        format!("api-platform_serviceToken={}", credential.service_token),
    ];
    if !credential.service_slh.is_empty() {
        values.push(format!("api-platform_slh={}", credential.service_slh));
    }
    if !credential.service_ph.is_empty() {
        values.push(format!("api-platform_ph={}", credential.service_ph));
    }
    values.join("; ")
}

fn parse_cookie_header(value: &str) -> Result<Vec<(String, String)>, String> {
    if value.contains(['\r', '\n']) {
        return Err("mimo_login.invalid_cookie".to_string());
    }
    Ok(value
        .trim()
        .strip_prefix("Cookie:")
        .unwrap_or(value)
        .split(';')
        .filter_map(|part| {
            let (name, value) = part.trim().split_once('=')?;
            let name = name.trim();
            if name.is_empty() {
                return None;
            }
            Some((name.to_string(), value.trim_matches('"').to_string()))
        })
        .collect())
}

fn parse_xiaomi_json(body: &str) -> Result<Value, String> {
    let body = body
        .trim()
        .strip_prefix("&&&START&&&")
        .unwrap_or(body.trim());
    serde_json::from_str(body).map_err(|_| "mimo_login.invalid_response".to_string())
}

fn parse_login_url_response(
    status: StatusCode,
    location: Option<&str>,
    body: &str,
) -> Result<String, String> {
    let candidate = if status.is_redirection() {
        location.map(str::to_string)
    } else if status.is_success() {
        let value: Value =
            serde_json::from_str(body).map_err(|_| "mimo_login.invalid_response".to_string())?;
        string_at(&value, &["data", "loginUrl"])
            .or_else(|| string_at(&value, &["data", "url"]))
            .or_else(|| string_at(&value, &["loginUrl"]))
            .or_else(|| {
                value
                    .get("data")
                    .and_then(Value::as_str)
                    .map(str::to_string)
            })
            .or_else(|| value.as_str().map(str::to_string))
    } else {
        None
    };
    candidate
        .filter(|url| allowed_login_url(url))
        .ok_or_else(|| "mimo_login.invalid_response".to_string())
}

fn allowed_login_url(value: &str) -> bool {
    Url::parse(value).ok().is_some_and(|url| {
        url.scheme() == "https"
            && url.host_str().is_some_and(|host| {
                host == "account.xiaomi.com"
                    || host.ends_with(".account.xiaomi.com")
                    || host == "platform.xiaomimimo.com"
                    || host.ends_with(".xiaomimimo.com")
            })
    })
}

fn string_at(value: &Value, path: &[&str]) -> Option<String> {
    path.iter()
        .try_fold(value, |current, key| current.get(*key))
        .and_then(|value| string_value(Some(value)))
}

fn string_value(value: Option<&Value>) -> Option<String> {
    match value? {
        Value::String(value) if !value.trim().is_empty() => Some(value.clone()),
        Value::Number(value) => Some(value.to_string()),
        _ => None,
    }
}

fn decimal_text(value: &Value) -> Option<String> {
    let value = string_value(Some(value))?;
    let unsigned = value.strip_prefix(['+', '-']).unwrap_or(&value);
    let mut parts = unsigned.split('.');
    let whole = parts.next()?;
    let fraction = parts.next();
    if parts.next().is_some()
        || whole.is_empty()
        || !whole.bytes().all(|byte| byte.is_ascii_digit())
        || fraction
            .is_some_and(|part| part.is_empty() || !part.bytes().all(|byte| byte.is_ascii_digit()))
    {
        return None;
    }
    Some(value)
}

fn integer_value(value: Option<&Value>) -> Option<i128> {
    string_value(value)?.parse().ok()
}

fn ensure_envelope_success(value: &Value) -> Result<(), String> {
    if value
        .get("code")
        .and_then(Value::as_i64)
        .is_some_and(|code| code != 0)
    {
        return Err("mimo_api.rejected".to_string());
    }
    Ok(())
}

fn parse_plan_expiry(body: &str) -> Option<i64> {
    let root: Value = serde_json::from_str(body).ok()?;
    let data = root.get("data").unwrap_or(&root);
    ["expireTime", "expiresAt", "endTime", "currentPeriodEnd"]
        .iter()
        .find_map(|key| {
            data.get(*key).and_then(|value| {
                value.as_i64().or_else(|| {
                    let text = value.as_str()?;
                    DateTime::parse_from_rfc3339(text)
                        .map(|date| date.timestamp())
                        .ok()
                        .or_else(|| {
                            NaiveDateTime::parse_from_str(text, "%Y-%m-%d %H:%M:%S")
                                .ok()
                                .map(|date| date.and_utc().timestamp())
                        })
                })
            })
        })
}

fn local_time_zone_header() -> String {
    let seconds = Local::now().offset().local_minus_utc();
    let sign = if seconds < 0 { '-' } else { '+' };
    let minutes = seconds.unsigned_abs() / 60;
    format!("UTC{sign}{:02}:{:02}", minutes / 60, minutes % 60)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parses_balance_and_token_plan() {
        let balances = parse_balance(
            r#"{"code":0,"data":{"currency":"CNY","balance":"12.50","cashBalance":"10","giftBalance":"2.50"}}"#,
        )
        .unwrap();
        assert_eq!(balances.len(), 3);
        assert_eq!(balances[0].amount, "12.50");
        let quotas = parse_token_plan(
            Some(r#"{"code":0,"data":{"currentPeriodEnd":"2027-01-15 00:00:00"}}"#),
            r#"{"code":0,"data":{"monthUsage":{"items":[{"name":"plan_total_token","used":25,"limit":100,"percent":25},{"name":"compensation_total_token","used":"10","limit":"50","percent":20}]}}}"#,
        )
        .unwrap();
        assert_eq!(quotas.len(), 2);
        assert_eq!(quotas[0].remaining, "75");
        assert_eq!(quotas[0].used_percent, 25.0);
        assert_eq!(quotas[0].expires_at, Some(1_799_971_200));
    }

    #[test]
    fn accepts_an_account_without_a_token_plan() {
        let quotas = parse_token_plan(
            Some(r#"{"code":0,"data":null}"#),
            r#"{"code":0,"data":{"monthUsage":{"items":null,"percent":0},"usage":null}}"#,
        )
        .unwrap();
        assert!(quotas.is_empty());
    }

    #[test]
    fn rejects_cookie_header_injection_and_unknown_login_hosts() {
        assert!(parse_cookie_header("userId=1\r\nHost: attacker").is_err());
        assert!(!allowed_login_url("http://account.xiaomi.com/pass"));
        assert!(!allowed_login_url(
            "https://account.xiaomi.com.attacker.test"
        ));
        assert!(allowed_login_url("https://account.xiaomi.com/pass"));
    }

    #[test]
    fn parses_redirect_and_legacy_json_login_urls() {
        let redirect = parse_login_url_response(
            StatusCode::FOUND,
            Some("https://account.xiaomi.com/pass/serviceLogin?sid=api-platform"),
            "",
        )
        .unwrap();
        assert_eq!(
            redirect,
            "https://account.xiaomi.com/pass/serviceLogin?sid=api-platform"
        );

        let legacy = parse_login_url_response(
            StatusCode::OK,
            None,
            r#"{"data":{"loginUrl":"https://account.xiaomi.com/pass/serviceLogin?sid=legacy"}}"#,
        )
        .unwrap();
        assert_eq!(
            legacy,
            "https://account.xiaomi.com/pass/serviceLogin?sid=legacy"
        );

        let string_body = parse_login_url_response(
            StatusCode::OK,
            None,
            r#""https://account.xiaomi.com/pass/serviceLogin?sid=string""#,
        )
        .unwrap();
        assert_eq!(
            string_body,
            "https://account.xiaomi.com/pass/serviceLogin?sid=string"
        );
    }

    #[test]
    fn rejects_html_and_untrusted_login_redirects() {
        assert_eq!(
            parse_login_url_response(StatusCode::OK, None, "<!doctype html>").unwrap_err(),
            "mimo_login.invalid_response"
        );
        assert_eq!(
            parse_login_url_response(
                StatusCode::FOUND,
                Some("https://account.xiaomi.com.attacker.test/pass"),
                "",
            )
            .unwrap_err(),
            "mimo_login.invalid_response"
        );
    }

    #[test]
    fn web_cookie_import_keeps_only_required_values() {
        let provider = MimoProvider::production().unwrap();
        let result = provider
            .credential_from_web_cookies(
                "userId=42; passToken=long-lived; tracking=discard",
                "userId=42; api-platform_serviceToken=short; api-platform_slh=slh; api-platform_ph=ph; analytics=x",
            )
            .unwrap();
        let credential = result.credential.unwrap();
        assert_eq!(credential.user_id, "42");
        assert_eq!(credential.service_token, "short");
    }

    #[test]
    fn missing_session_errors_do_not_echo_cookie_values() {
        let provider = MimoProvider::production().unwrap();
        let error = provider
            .credential_from_web_cookies(
                "userId=42; tracking=account-secret",
                "analytics=platform-secret",
            )
            .unwrap_err();
        assert_eq!(error, "mimo_login.missing_pass_token");
        assert!(!error.contains("account-secret"));
        assert!(!error.contains("platform-secret"));
    }

    #[tokio::test]
    #[ignore = "requires live MiMo network access"]
    async fn live_login_url_uses_an_allowed_xiaomi_host() {
        let provider = MimoProvider::production().unwrap();
        let login_url = provider.login_url().await.unwrap();
        assert!(allowed_login_url(&login_url));
        let metadata = provider.login_metadata(&login_url, None).await.unwrap();
        assert!(string_at(&metadata, &["sid"]).is_some());
        assert!(string_at(&metadata, &["_sign"]).is_some());
    }

    #[tokio::test]
    #[ignore = "requires AIUSAGE_MIMO_TEST_USERNAME and AIUSAGE_MIMO_TEST_PASSWORD"]
    async fn live_credentials_reach_session_or_allowed_challenge() {
        let username = std::env::var("AIUSAGE_MIMO_TEST_USERNAME")
            .expect("AIUSAGE_MIMO_TEST_USERNAME is required");
        let password = std::env::var("AIUSAGE_MIMO_TEST_PASSWORD")
            .expect("AIUSAGE_MIMO_TEST_PASSWORD is required");
        let provider = MimoProvider::production().unwrap();
        let result = provider.login(username, password).await.unwrap();
        if let Some(challenge_url) = result.challenge_url {
            assert!(allowed_login_url(&challenge_url));
            return;
        }
        let credential = result
            .credential
            .expect("mimo_live_login_missing_credential");

        let balance = provider.balance_json(&credential).await;
        assert!(
            balance.failure.is_none(),
            "mimo_live_balance_request_failed"
        );
        assert!(!parse_balance(&balance.body).unwrap().is_empty());

        let detail = provider.token_plan_detail_json(&credential).await;
        let usage = provider.token_plan_usage_json(&credential).await;
        assert!(
            detail.failure.is_none() || usage.failure.is_none(),
            "mimo_live_token_plan_requests_failed"
        );
        assert!(
            !parse_token_plan(Some(&detail.body), &usage.body)
                .unwrap()
                .is_empty()
        );
    }
}
