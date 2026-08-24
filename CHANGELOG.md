# Changelog

本项目遵循语义化版本。用户可见变更记录如下。

## [0.2.0] - 2026-08-24

### Added

- 将账户与用量模型升级为 Provider 中立结构，统一支持 OpenAI Codex、DeepSeek 和 Xiaomi MiMo。
- 使用 DeepSeek 官方余额 API 展示多币种总余额、赠送余额与充值余额。
- 支持 MiMo 小米账号登录、官方网页安全验证、余额、Token Plan、会话续签与本地缓存。
- 为新增 Provider 补充中英文界面、演示数据、账户详情和脱敏同步诊断。

### Fixed

- 兼容 MiMo `genLoginUrl` 当前的 HTTP 302 跳转与 Xiaomi Passport `_json=true` 协议。
- 将没有 Token Plan 的合法空响应识别为空状态，不再误报 schema 错误。
- 区分 MiMo“透支额度”与“剩余透支额度”，避免概览重复标签。

### Security

- DeepSeek API Key、MiMo `userId + passToken` 与平台 Cookie 仅写入系统安全存储。
- MiMo 原始密码仅参与当次认证并主动清零；安全验证仅允许受信任的小米 HTTPS 域名。
- Provider 诊断继续脱敏 Authorization、Token、Cookie、API Key 与原始账户标识。

## [0.1.0] - 2026-08-22

### Added

- Device Code 浏览器授权与 `auth.json` OAuth 凭据导入。
- 多账户额度概览、额外额度、Reset Credits 和账户详情缓存。
- Codex Profile Token 每日、每周、累计统计与延迟日历热力图。
- English、简体中文、动态取色、完整演示模式和本地通知。
- 最多 200 条脱敏同步诊断，以及默认关闭的 Android 后台刷新。

### Fixed

- 修复移动端 AppBar 溢出、二级页面返回、Android 双返回退出和概览卡片布局。
- 修复 Profile 当前响应中 `stats.daily_usage_buckets` 的嵌套解析，避免有效统计被缓存为空。
- 修复 Android Release 单 ABI 打包和 Debug snapshot 导致的异常体积。

### Security

- OAuth Token 仅保存在平台安全存储中；`auth.json` 仅在内存解析。
- 诊断响应限制为 64 KiB，并脱敏 Authorization、Token、API Key 和账户标识。
- Android v0.1.0 使用独立发布密钥签名，Release 同时提供 SHA-256 校验文件。

[0.2.0]: https://github.com/mcxiaochenn/AiUsage/releases/tag/v0.2.0
[0.1.0]: https://github.com/mcxiaochenn/AiUsage/releases/tag/v0.1.0
