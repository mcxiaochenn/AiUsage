# Changelog

本项目遵循语义化版本。用户可见变更记录如下。

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

[0.1.0]: https://github.com/mcxiaochenn/AiUsage/releases/tag/v0.1.0
