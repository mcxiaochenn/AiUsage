# OpenAI Codex 兼容性研究

研究日期：2026-08-21
上游：[`openai/codex`](https://github.com/openai/codex) `main`，commit `536f86e5cc9ec1ff38457d099bf320b9d08eeeba`。

本项目只把下面的行为视为“官方客户端当前正在使用的实现”，**不把它视为 OpenAI 面向第三方承诺稳定的公开 API**。所有 URL、请求头和 JSON 仅位于 Rust 的 `api::codex` compatibility layer；Flutter 永远不解析 OpenAI 原始 JSON。

## 当前 Usage 与 Reset Credit 路径

`codex-rs/backend-client/src/client/rate_limit_resets.rs` 目前按 `PathStyle` 选择：

| Backend base URL 风格 | Usage | Reset credits |
| --- | --- | --- |
| Codex API | `GET {base}/api/codex/usage` | `GET {base}/api/codex/rate-limit-reset-credits` |
| ChatGPT backend API | `GET {base}/wham/usage` | `GET {base}/wham/rate-limit-reset-credits` |

`backend-client/src/client.rs` 会把 `https://chatgpt.com` 与 `https://chat.openai.com` 自动规范化为带 `/backend-api` 的 base URL；因此 MVP 的默认 provider 是 `https://chatgpt.com/backend-api`，实际 URL 为 `https://chatgpt.com/backend-api/wham/usage`。

当前客户端为请求设置 Bearer authentication、Codex user agent，并在 token 带有 workspace identity 时设置 `ChatGPT-Account-Id`。FedRAMP identity 还会带 `X-OpenAI-Fedramp: true`。本项目只在 `id_token` 的官方 `chatgpt_account_is_fedramp` boolean claim 为真时生成该头，绝不从 UI 输入推断。

官方代码还包含 `POST .../rate-limit-reset-credits/consume`，但本 MVP 完全不实现、也不引用该调用路径。

## 响应形状与兼容规则

官方 OpenAPI 模型位于 `codex-rs/codex-backend-openapi-models`：

```text
plan_type
rate_limit.primary_window
rate_limit.secondary_window
additional_rate_limits[]
rate_limit_reset_credits.available_count
credits.has_credits / credits.unlimited / credits.balance
```

一个 window 当前包含 `used_percent`、`limit_window_seconds`、`reset_after_seconds`、`reset_at`。`secondary_window` 与整个 `rate_limit` 都可以缺失或为 `null`。每个 `additional_rate_limits[]` 当前具有 `limit_name`、`metered_feature` 与其独立的 `rate_limit`。

Rust normalizer 必须：

- 保留 0、1、2 或任意多个有效窗口；
- 对未知字段忽略而不是失败；
- 以 server `limit_name` / `metered_feature` 优先命名 additional limit；
- 仅在 server 未命名时使用 duration 推断 title，未知则显示 `Custom limit`；
- 将 percentage clamp 为 0..100，只从 `used_percent` 计算 remaining；
- 把 malformed window 丢弃为该 window 的解析问题，不让其清空最后成功 snapshot。

`/rate-limit-reset-credits` 的 detail response 当前可含 `credits[]`，条目有 `id`、`reset_type`、`status`、`granted_at`、`expires_at`、`title`、`description`。若 details 获取失败而 Usage body 已有 `available_count`，官方 app-server 测试表明仍应保留 count；MVP 采用相同行为。

Usage 顶层 `credits` 与 reset credit 是两类不同概念：前者描述额外额度是否存在、是否无限和后端给出的余额字符串；后者描述可以重置 rate-limit window 的可用次数。`available_count` 是 reset credit 总数的权威值，detail 列表可能被后端截断。接口只提供单条 reset credit 的 `expires_at`，没有“次数下次补充时间”，因此 UI 只标注到期时间。

## Profile Token 统计与账户资料

官方 app-server 的 `account/usage/read` 将 ChatGPT 账号侧 Profile 数据规范化为 `AccountTokenUsageSummary` 和 `AccountTokenUsageDailyBucket`。当前底层路径为 `GET https://chatgpt.com/backend-api/wham/profiles/me`，可返回 lifetime tokens、peak daily tokens、longest running turn、current/longest streak 与 `daily_usage_buckets`。这些统计由服务端异步生成，已知可能缺少当天 bucket；AiUsage 不把本机额度百分比或本地会话日志合并进去。

账户注册时间按用户指定的只读路径 `GET https://api.openai.com/v1/me` 获取，只读取最外层 `created`。Codex OAuth access token 若被该 endpoint 拒绝，UI 保留注册时间字段并显示不可用，不使用组织创建时间、JWT 签发时间或其他字段猜测。

两条新增路径与 Usage 路径一样属于兼容性研究对象，而不是本项目承诺稳定的公开 OpenAI API。请求仍只在 Rust credential boundary 内执行；Flutter 只接收规范化模型。

## 当前 ChatGPT OAuth

官方登录模块在 `codex-rs/login` 中实现两种受管理的 ChatGPT OAuth：浏览器 loopback 与 device code。app-server README 将 `chatgpt` 和 `chatgptDeviceCode` 都标为 Codex-managed 模式，并说明 Codex 持有并自动 refresh token。

### 浏览器 loopback

`login/src/server.rs` 使用：

- issuer：`https://auth.openai.com`；
- `GET /oauth/authorize`；
- localhost callback：`http://localhost:1455/auth/callback`，端口冲突时回退到 1457；
- PKCE S256、随机 state；
- `scope=openid profile email offline_access api.connectors.read api.connectors.invoke`；
- authorization-code exchange：`POST /oauth/token`，`application/x-www-form-urlencoded`，带 `client_id`、`redirect_uri`、`code_verifier`。

### Device code（MVP 选用）

为避免移动端 loopback callback 的平台差异，MVP 使用上游同样支持的 device-code 方式，而不是要求用户复制 access token：

1. `POST https://auth.openai.com/api/accounts/deviceauth/usercode`，JSON `{ client_id }`；
2. 在系统浏览器打开 `https://auth.openai.com/codex/device` 并向用户展示 code；
3. 间隔轮询 `POST https://auth.openai.com/api/accounts/deviceauth/token`，JSON `{ device_auth_id, user_code }`；
4. 成功后使用返回的 `authorization_code`、`code_verifier` 和 `code_challenge` 完成同一 `/oauth/token` code exchange。

上游 device-code helper 的轮询上限为 15 分钟；本项目将 pending login 同样限制为 15 分钟，拒绝、过期或取消后停止轮询。

上游 `login/src/auth/manager.rs` 的当前 client id 是 `app_EMoamEEZ73f0CkXaXp7hrann`。本项目将它封装为 provider 常量而非散落在 UI；若 provider contract 改变，必须替换/禁用 provider，而不是让 Flutter 硬编码 OAuth 参数。

## Refresh、identity 与错误边界

当前官方 refresh：`POST https://auth.openai.com/oauth/token`，JSON `{ client_id, grant_type: "refresh_token", refresh_token }`。上游在 access JWT 将在 5 分钟内到期时 refresh，并在成功后持久化 **所有**返回的 `id_token`、`access_token`、`refresh_token` 后重新加载内存状态。refresh token 可以旋转，所以本项目必须由 Flutter secure storage 原子替换整组 credential，不能只更新 access token。

`login/src/token_data.rs` 从 `id_token` 的顶层 / profile email 以及 `https://api.openai.com/auth` claim 读取：`chatgpt_plan_type`、`chatgpt_user_id`、`chatgpt_account_id`、`chatgpt_account_is_fedramp`。本项目用 account id 或 user id 的 SHA-256 截断值作为本地 identity hash；数据库不保存 token 或 raw id_token。

MVP refresh 规则：

- 401：读取该账号 secure credential，尝试一次合法 refresh；成功后只重放原请求一次；失败转 `AuthExpired`；
- 429：解析 `Retry-After`，不自动紧密重试；
- 5xx / transport：最多两次指数退避加 jitter；
- schema 失败：转 `ParseError`，保留 cache；
- refresh 的 `invalid_grant`、已撤销或无法复用 token：不重试，要求重新登录；
- refresh 的超时或 5xx：保留 credential 和 stale cache，不把它误报为 logout。

## 实现取舍

本项目不会自动扫描或复制 `~/.codex/auth.json`。高级用户可以通过系统文件选择器主动导入完整的 Codex OAuth `auth.json`：文件限制为 1 MiB，仅在一次 FFI 调用的内存边界中解析，不保留原文件，并拒绝 API Key-only、缺少身份信息或格式异常的内容。Flutter 的 `flutter_secure_storage` 是唯一 credential owner；Rust 返回解析或刷新后的 token bundle，并负责 HTTP、raw JSON、normalization、cache metadata 与 SQLite history。

在上线前、每次升级 `CodexProvider` 前，应重新核对上游 `backend-client/src/client/rate_limit_resets.rs`、`backend-client/src/client.rs`、`login/src/server.rs`、`login/src/device_code_auth.rs` 与 `login/src/auth/manager.rs`。
