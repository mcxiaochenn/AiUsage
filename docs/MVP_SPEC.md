# AiUsage 跨平台 MVP 技术报告

## 1. 项目目标

开发一个用于监看 OpenAI Codex 套餐额度的跨平台客户端。

首个 MVP 支持：

- Android
- iOS
- Windows
- macOS
- Linux

不支持 Web。

核心功能：

1. 登录 OpenAI / Codex 账号
2. 获取当前 Codex 使用额度
3. 显示已用百分比和剩余额度
4. 显示每个额度窗口的准确重置时间
5. 支持 OpenAI 后续增加的额外模型额度窗口
6. 显示 Rate Limit Reset Credits 数量，但 MVP 不允许直接消耗
7. 支持手动刷新
8. 支持基本历史快照
9. 桌面端支持系统托盘
10. 移动端支持安全凭据存储和有限后台刷新

---

# 2. 技术路线

采用：

```text
Flutter
+
Rust
+
flutter_rust_bridge
```

其中：

```text
Flutter / Dart
负责：
- UI
- 页面导航
- 状态管理
- 系统主题
- 通知
- Tray
- 移动端生命周期
- 平台安全存储适配

Rust
负责：
- OpenAI OAuth / Token 生命周期
- Codex API 请求
- JSON 解析
- Quota Window 标准化
- API 兼容层
- 多账号核心数据模型
- SQLite 历史数据
- Retry / Backoff
```

推荐组件：

```text
Flutter
- Riverpod
- go_router
- flutter_rust_bridge
- flutter_secure_storage 或平台安全存储封装
- tray_manager
- window_manager

Rust
- tokio
- reqwest
- serde
- serde_json
- thiserror
- chrono
- rusqlite / sqlx
```

使用最新稳定且相互兼容的版本，不需要为了本报告固定旧版本。

---

# 3. 为什么采用 Flutter + Rust

项目实际性能瓶颈主要来自网络，而不是 JSON 解析。

因此 Rust 的主要价值不是单纯追求“比 Java 快”，而是：

1. 五个平台共享核心业务逻辑
2. 将未公开 Codex API 完全隔离
3. 与 OpenAI 官方 Codex 的 Rust 实现保持技术语言一致
4. 方便追踪官方 Codex 源码改动
5. 后续适合扫描大量 Codex JSONL 日志
6. 后续可以扩展本地 Token / Cost 统计
7. 桌面端无需 JVM
8. Provider 层容易扩展

官方 `openai/codex` 本身就是 Rust 项目，目前已经包含 rate limit、usage、reset credit 等相关客户端实现。

---

# 4. 当前可用的 Codex 数据源

核心额度接口为：

```http
GET https://chatgpt.com/backend-api/wham/usage
Authorization: Bearer <access_token>
```

OpenAI 官方 Codex 源码中也存在对应路径：

```text
/api/codex/usage
/wham/usage
```



需要特别注意：

该接口虽然被 OpenAI 官方 Codex 客户端使用、实现代码也已经开源，但目前不应视为面向第三方开发者提供稳定兼容承诺的公开 API。

因此项目必须将其视为：

```text
Undocumented / Internal-but-officially-used API
```

Provider 层必须具备兼容和容错能力。

---

# 5. Quota 数据结构

官方 Codex 当前额度窗口至少包含：

```text
used_percent
limit_window_seconds
reset_after_seconds
reset_at
```

官方 Rust Model：

```rust
pub struct RateLimitWindowSnapshot {
    pub used_percent: i32,
    pub limit_window_seconds: i32,
    pub reset_after_seconds: i32,
    pub reset_at: i32,
}
```



不要将 UI 或数据库写死为：

```text
5 小时额度
+
Weekly 额度
```

因为额度结构可能变化。

应抽象为：

```rust
pub struct QuotaWindow {
    pub id: String,
    pub title: String,
    pub used_percent: f64,
    pub reset_at: i64,
    pub window_seconds: i64,
}
```

完整快照：

```rust
pub struct UsageSnapshot {
    pub account: AccountInfo,
    pub windows: Vec<QuotaWindow>,
    pub reset_credits_available: Option<i64>,
    pub fetched_at: i64,
}
```

UI 永远遍历 `windows`。

---

# 6. Primary / Secondary / Additional Limits

Codex 当前返回结构可能包括：

```text
rate_limit.primary_window
rate_limit.secondary_window
additional_rate_limits[]
```

社区成熟项目 CodexBar 已经基于这一结构处理：

- Session / 5-hour window
- Weekly window
- 模型独立额度
- Codex Spark 等新增 quota



因此：

```text
不要依赖 primary == 5h
不要依赖 secondary == weekly
```

应该主要根据：

```text
limit_window_seconds
```

以及接口提供的名称/metadata 标准化显示。

---

# 7. Reset Credits

Codex 官方代码当前还包含：

```http
GET /api/codex/rate-limit-reset-credits
GET /wham/rate-limit-reset-credits
```

并存在消耗 Reset Credit 的接口。

MVP 只实现：

```text
查看 Reset Credit 数量
查看有效期（若接口提供）
```

不实现：

```text
Consume / Redeem Reset Credit
```

原因：

额度监看属于只读功能；

消耗 Reset Credit 会改变用户账户状态，应在以后单独设计交互和安全确认。

---

# 8. Thread Usage

OpenAI Codex 官方代码还有：

```http
POST /api/codex/usage/thread_usage/query
POST /wham/usage/thread_usage/query
```

可返回：

```text
estimated_usage_credits_micros
estimated_usage_usd_micros
model
reasoning_effort
speed
input_tokens
cached_input_tokens
output_tokens
total_tokens
```



但该功能：

```text
不属于 MVP
```

只在代码架构中预留扩展位置。

---

# 9. OAuth 与账号

不要要求普通用户手动从：

```text
~/.codex/auth.json
```

复制 Token。应用提供 Device Code 作为推荐登录方式，并允许高级用户通过系统文件选择器主动导入完整 `auth.json`；不会自动扫描文件，也不支持 API Key-only 登录。

理想用户体验：

```text
添加账号
↓
OpenAI Codex OAuth
↓
浏览器授权
↓
App 获取 Token
↓
安全存储
↓
读取 Usage
```

实现时应优先研究并复用当前官方：

```text
openai/codex
```

所使用的 OAuth / Device Authorization 流程。

不要凭第三方项目 README 猜 OAuth 参数。

CodexBar、QuotaDog 和 Android 社区实现均已证明直接使用 Codex OAuth + `/wham/usage` 获取跨设备 quota 是可行方案。QuotaDog 同时明确提醒这些 endpoint 并不是已文档化 public API。

---

# 10. 凭据安全

禁止：

```text
SharedPreferences 明文 Token
NSUserDefaults 明文 Token
普通 JSON 文件
SQLite 明文 Token
自己写一个固定 AES key
```

应优先使用：

```text
Android
→ Android Keystore

iOS
→ Keychain

macOS
→ Keychain

Windows
→ Windows Credential Manager / DPAPI

Linux
→ Secret Service / libsecret
```

Flutter 可以提供统一 CredentialStore interface。

Rust Core 不应该知道底层凭据具体存在哪里。

例如：

```text
Rust Core
    ↓
CredentialStore abstraction
    ↓
Flutter / Platform
    ├ Android Keystore
    ├ Apple Keychain
    ├ Windows secure storage
    └ Linux Secret Service
```

---

# 11. 页面设计

MVP 只需要四个核心页面。

## Dashboard

显示：

```text
Codex
账号邮箱
套餐类型

████████░░  72%
5-hour
2h 14m 后重置

████░░░░░░  41%
Weekly
4天 8小时后重置

Reset Credits
2 available

最后更新：15:21
```

支持：

```text
下拉刷新 / Refresh
```

---

## Account

显示：

- 邮箱
- Plan
- Account ID 的安全缩略值
- 登录状态
- Token 状态
- 最后成功刷新时间

操作：

- Refresh
- Logout
- Remove Account

---

## History

SQLite 保存：

```text
timestamp
account_id_hash
window_id
used_percent
reset_at
```

MVP 展示：

```text
最近 24h
最近 7d
```

简单折线图即可。

不要为了 MVP 开发复杂数据分析。

---

## Settings

包含：

```text
刷新间隔
主题
是否显示百分比
是否显示 Reset Credits
通知阈值
账号管理
关于
```

---

# 12. 多账号

数据层从第一天就支持：

```text
Vec<Account>
```

即使 MVP UI 第一版只重点优化单账号体验。

每个账号独立拥有：

```text
credential
usage snapshot
history
last refresh
error state
```

严禁多个账号共享 Token 或缓存。

---

# 13. Desktop 特性

Windows / macOS / Linux 支持系统 Tray。

示例：

```text
Codex 38%
Weekly 61%
```

Tray 点击：

```text
打开主窗口
Refresh
Quit
```

桌面后台可以按照：

```text
5 min
15 min
30 min
Manual
```

刷新。

不要默认设置过高刷新频率。

---

# 14. Android

实现：

- App 主界面
- 安全凭据存储
- WorkManager best-effort refresh
- 通知
- App foreground 时立即刷新

Android Widget：

```text
不是第一阶段必须项
```

但架构必须允许以后加入。

---

# 15. iOS

iOS 不保证固定周期后台任务。

因此设计必须是：

```text
打开 App
→ 刷新

返回前台
→ 刷新

手动操作
→ 刷新

系统给予后台执行机会
→ best-effort refresh
```

不能承诺：

```text
每 5 分钟一定刷新
```

---

# 16. 网络策略

Rust 网络层：

```text
reqwest
+
tokio
```

实现：

```text
timeout
retry
exponential backoff
HTTP status mapping
JSON decode error
token expired handling
refresh token
```

但：

```text
401
```

必须优先尝试合法 Token Refresh，而不是无限重试。

429 必须尊重服务器 rate limit。

---

# 17. API Compatibility Layer

建议目录：

```text
rust/
└── src/
    ├── auth/
    ├── api/
    │   └── codex/
    ├── models/
    ├── normalize/
    ├── storage/
    ├── history/
    └── bridge/
```

不要让 Flutter UI 直接解析 `/wham/usage`。

正确流程：

```text
OpenAI
↓
RawWhamUsage
↓
Rust Parser
↓
Normalizer
↓
UsageSnapshot
↓
flutter_rust_bridge
↓
Flutter
```

这样以后 OpenAI 改接口，只改 Rust。

---

# 18. 缓存与错误

最后一次成功结果需要缓存。

如果刷新失败：

不要直接把 Dashboard 清空。

应该显示：

```text
⚠ 数据可能已过期

Last successful refresh:
15:20

当前显示：
上一次成功获取的数据
```

状态定义建议：

```rust
Fresh
Stale
AuthExpired
Offline
RateLimited
ServerError
ParseError
```

---

# 19. MVP 明确不做

为了控制范围，第一版不要开发：

- Web
- Claude
- Gemini
- Cursor
- Grok
- 云同步
- 用户账号服务器
- 社交功能
- Reset Credit 消耗
- Codex Thread 详情
- Session JSONL 全量扫描
- Token 成本计算
- AI API Platform Billing
- 团队管理
- Enterprise Admin API
- Push Server
- 复杂 Widget
- 自动更新器

---

# 20. MVP 验收条件

## 通用

五个平台项目结构可以正常构建。

至少完成并实际验证：

```text
Android
Windows / Linux / macOS 至少一个桌面系统
```

Apple 平台若当前开发环境无法签名，可保证代码和工程结构完整。

---

## 登录

用户可以通过 Codex/OpenAI OAuth 添加账号。

Token 安全保存。

Token 过期可以刷新。

Logout 会删除本地凭据。

---

## Usage

成功获取：

```text
GET /wham/usage
```

显示：

```text
used_percent
remaining_percent
reset_at
countdown
window duration
```

支持任意数量 quota windows。

---

## Reset Credits

能够只读显示：

```text
available_count
```

存在时显示，不存在时自动隐藏。

---

## 缓存

离线后仍可查看最后成功结果。

必须明确标注 Stale。

---

## History

至少保存 7 天额度快照。

应用重启后仍存在。

---

## Desktop

Tray 可查看主要额度。

可手动 Refresh。

---

## Quality

必须：

```text
flutter analyze
cargo fmt --check
cargo clippy
cargo test
```

尽量无 warning。

关键 parser 使用 fixture/unit tests。

---

# 21. 产品定位

不要将项目定位为：

> Android CodexBar

而应定位为：

> Cross-platform Codex quota monitor

第一阶段：

```text
Codex
```

未来可以通过 Provider Architecture 扩展：

```text
Claude
Gemini
Cursor
Grok
OpenCode
```

最终可以发展为：

```text
AI Coding Quota Center
```

但这些全部属于 MVP 之后。
