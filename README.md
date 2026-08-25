# AiUsage

[![CI](https://github.com/mcxiaochenn/AiUsage/actions/workflows/ci.yml/badge.svg)](https://github.com/mcxiaochenn/AiUsage/actions/workflows/ci.yml)
[![Release](https://img.shields.io/github/v/release/mcxiaochenn/AiUsage)](https://github.com/mcxiaochenn/AiUsage/releases/latest)
[![License](https://img.shields.io/github/license/mcxiaochenn/AiUsage)](LICENSE)

简体中文 | [English](README_EN.md)

AiUsage 是一个移动优先、本地优先的 AI 服务用量与余额监看应用，目前支持 ChatGPT、DeepSeek 和 Xiaomi MiMo。

> [!IMPORTANT]
> Android 是当前主要支持平台。iOS 正在重点适配，CI 会验证编译，但因缺少物理设备尚未完成真机测试。Codex 与 MiMo 使用的部分内部接口可能随上游变化，请勿将 AiUsage 作为关键余额告警的唯一来源。

## 功能

- 在一个应用中管理 Codex、DeepSeek 和 MiMo 多个账户。
- 查看 Codex 配额、Credits、Reset Credits 与 Token 使用统计。
- 查看 DeepSeek 多币种余额，以及 MiMo 余额与 Token Plan。
- 支持 Codex Device Code、`auth.json` 导入和 Provider 专属登录方式。
- 使用平台安全存储保存凭据，SQLite 仅保存脱敏缓存和诊断。
- 提供中英文界面、动态取色、演示模式和离线缓存。
- 后台刷新默认关闭；网络失败时继续显示最近一次成功结果。

## 下载与安装

从 [GitHub Releases](https://github.com/mcxiaochenn/AiUsage/releases/latest) 下载。项目目前没有上架 Google Play、App Store 或其他应用商店的计划。

### Android

| 安装包 | 适用设备 |
| --- | --- |
| `arm64-v8a` | 绝大多数现代 Android 手机，推荐 |
| `universal` | 不确定架构时选择；体积较大 |
| `armeabi-v7a` | 较旧的 32 位 ARM 设备 |
| `x86_64` | 64 位 x86 模拟器或少量设备 |

从 v0.2.1 起，Release 使用以上四种固定文件名。请在 Release 资产列表中选择，升级前可查看[安装指南](docs/installation.md)。

### iOS

Release 提供 `AiUsage-ios-release-unsigned.ipa`。它没有 Apple 签名，不能像 App Store 应用一样直接安装，需要用户自行签名；越狱设备能否安装取决于设备和所用工具。签名限制见[安装指南](docs/installation.md)。

iOS 目前仅在 macOS CI 编译，尚未完成真机验收。如遇问题，欢迎[提交 Issue](https://github.com/mcxiaochenn/AiUsage/issues/new/choose)。

## Provider

| Provider | 认证 | 可查看内容 | 稳定性 |
| --- | --- | --- | --- |
| ChatGPT | Device Code / `auth.json` | Codex 配额、Credits、Reset Credits、Token 统计 | 部分内部接口 |
| DeepSeek | API Key | CNY/USD 余额明细 | 官方余额 API |
| Xiaomi MiMo | 小米账号登录 | 按量余额、Token Plan | 内部控制台 API |

## 平台状态

| 平台 | 状态 |
| --- | --- |
| Android | 主要支持；已有 arm64 真机验证 |
| iOS | 重点适配；CI 编译，尚无物理设备测试 |
| Windows / macOS / Linux | 后期适配；当前不提供安装产物 |
| Web | 不支持 |

平台限制和后续计划见[平台支持](docs/platforms.md)。

## 安全与隐私

- OAuth Token、API Key、MiMo 会话和 Cookie 只写入系统安全存储（Android Keystore / Apple Keychain）。
- 原始密码不持久化；Token、Cookie 和原始账户 ID 不写入 SQLite 或普通日志。
- 应用默认不包含遥测、云同步或自建账号服务器。
- 本地诊断会移除凭据并限制保留数量与响应大小，但仍可能包含邮箱、套餐等非机密账户资料。

完整边界与内部 API 风险见[安全说明](docs/security.md)。

## 文档与反馈

- [文档索引](docs/README.md)
- [安装指南](docs/installation.md)
- [开发与发布](docs/development.md)
- [架构](docs/architecture.md)
- [路线图](docs/roadmap.md)
- [问题反馈](https://github.com/mcxiaochenn/AiUsage/issues)

## 非官方声明

AiUsage 是非官方开源项目，与 OpenAI、DeepSeek、小米没有隶属、合作、认可或赞助关系。使用者应遵守各 Provider 的服务条款，并自行承担内部接口变化、凭据保管和数据准确性风险。

## License

[MIT](LICENSE)
