# AiUsage

![Status](https://img.shields.io/badge/status-early%20development-orange)
![Version](https://img.shields.io/badge/version-0.1.0--alpha-blue)
![License](https://img.shields.io/badge/license-MIT-green)

> [!WARNING]
> **Early Development / Alpha**：项目仍处于早期开发阶段，尚未提供稳定版本、正式安装包、平台兼容保证或数据迁移承诺。请勿将其作为关键额度告警的唯一来源。

AiUsage 是一个本地优先的 OpenAI Codex 套餐额度监看应用 MVP。项目使用 Flutter 提供 Android、iOS、Windows、macOS 和 Linux 的统一界面，由 Rust 负责 OAuth、Usage API 兼容、数据标准化及 SQLite 历史。

**English summary:** AiUsage is an early-development, local-first cross-platform monitor for OpenAI Codex usage limits. It keeps credentials in platform secure storage, normalizes quota windows in a Rust core, and stores only local usage history. This project is unofficial and currently relies on undocumented endpoints used by the official Codex client.

## 已实现功能

- 支持浏览器 Device Code OAuth，以及由用户通过系统文件选择器主动导入 Codex OAuth `auth.json`。
- 支持多个账号；重复导入同一账号时更新已有安全凭据。
- 支持 English、简体中文和跟随系统语言。
- access token 临近过期或 Usage 请求返回 401 时，最多刷新并重试一次。
- 动态处理零个、一个或任意多个 quota window，包括 `additional_rate_limits`。
- 展示已用/剩余百分比、重置倒计时、绝对时间、缓存状态和只读 Reset Credits。
- 保存 7 天 SQLite 历史，并提供最近 24 小时或 7 天折线图。
- 支持 System/Light/Dark、Manual/5/15/30 分钟刷新和本地阈值通知。
- 桌面端提供托盘摘要、Open、Refresh、Quit 以及关闭窗口后隐藏。
- 网络或 schema 错误时保留最后一次成功快照，并明确标记陈旧状态。

## 平台状态

工程结构已经集成五个平台，但“工程存在”不代表完成发布验证：

| 平台 | 已集成能力 | 当前验证状态 |
| --- | --- | --- |
| Android | Keystore、安全存储、文件选择、前台刷新、WorkManager best effort 后台刷新 | arm64 Release APK 已在 Android 真机安装并启动；登录后的长期运行仍需验证 |
| iOS | Keychain、文件选择、前台刷新、BGTaskScheduler best effort 后台刷新 | 需在 macOS/Xcode 环境验证 |
| Windows | 系统安全存储、文件选择、托盘、窗口隐藏 | Release 构建与安装体验待验证 |
| macOS | Keychain、只读文件选择、托盘、窗口隐藏 | 需在 macOS/Xcode 环境验证 |
| Linux | Secret Service、文件选择、托盘、窗口隐藏 | 需在目标发行版验证依赖与 AppIndicator |
| Web | 不支持 | 不在构建目标中 |

## 截图

截图将在 UI 稳定并完成首轮平台构建验证后补充。当前 Dashboard 已实现账号切换、动态 quota 卡片、倒计时、缓存状态和 Reset Credits；桌面宽屏使用 `NavigationRail`，手机使用底部导航。

## 架构

```text
Flutter UI / AppController
        ↓ flutter_rust_bridge
Rust application bridge
        ├─ Device Code OAuth / auth.json import / token refresh
        ├─ Codex Usage API compatibility layer
        ├─ raw response normalization
        └─ SQLite cache and seven-day history
```

```text
app/                         Flutter UI、生命周期与平台能力
  lib/src/app.dart           Material 3 页面与导航
  lib/src/app_controller.dart 多账号状态与刷新编排
  lib/src/services/          安全存储、通知、后台调度、桌面托盘
  rust_builder/              flutter_rust_bridge Cargokit 集成
rust/                        Rust domain core
  src/auth/                  Device Code OAuth 与 token refresh
  src/api/codex/             未公开 Usage API 的兼容层
  src/normalize/             Raw response -> 稳定 UsageSnapshot
  src/history/               SQLite 缓存、历史与清理
  src/bridge/                暴露给 Flutter 的应用服务
```

Flutter 不解析 OpenAI 原始 JSON。跨 FFI 只传递稳定模型，例如 `UsageSnapshot`、`QuotaWindow`、`AccountInfo`、`UsageState` 和 `HistoryPoint`。

## 安全与隐私

- OAuth `access_token`、`refresh_token` 和 `id_token` 仅通过 `flutter_secure_storage` 持久化。
- `auth.json` 只在用户主动选择文件后读取，限制为 1 MiB；仅在内存中解析，不复制原文件、不写 SQLite、不记录 Token。
- API Key-only、缺少身份信息或格式异常的文件会被拒绝；应用不会自动扫描 `~/.codex/auth.json`。
- Android 使用 Keystore；iOS/macOS 使用 Keychain；Windows 使用系统保护存储；Linux 使用 Secret Service。
- Rust 只在单次调用的内存边界中接收凭据，不将凭据或原始 OpenAI JSON 写入 SQLite 或日志。
- SQLite 仅保存 identity hash、非机密账号信息、标准化 quota 和时间戳；启动时清理七天前记录。
- 429 尊重 `Retry-After`，5xx 只做有限指数退避，错误时保留陈旧缓存。
- 默认不包含 analytics、telemetry、crash report 上传、后端服务、账号同步或 cloud sync。

## OpenAI 兼容层

实现依据是上游 `openai/codex` 的当前源码研究，详见 [OpenAI Codex 兼容性研究](docs/openai-codex-research.md)。当前兼容以下路径风格：

- ChatGPT backend：`/backend-api/wham/usage` 与 `/backend-api/wham/rate-limit-reset-credits`
- Codex API：`/api/codex/usage` 与 `/api/codex/rate-limit-reset-credits`

这些接口是官方客户端当前使用的实现，**不是 OpenAI 面向第三方承诺稳定的公开 API**。端点、请求头、OAuth 参数或响应结构可能随时变化。

## 开发环境

- Flutter 3.47+ / Dart 3.13+
- Rust stable，包含 `rustfmt` 和 `clippy`
- Android SDK、JDK 17
- Windows 桌面构建需要 Visual Studio C++ Desktop 工具链
- Apple 平台需要 macOS、Xcode、CocoaPods；真机分发需要有效签名
- Linux 需要 GTK3；托盘通常还需要 AppIndicator 支持

Windows 开发 Flutter plugin 时需开启 Developer Mode，以允许创建 symlink：

```powershell
start ms-settings:developers
```

## 构建与验证

```powershell
cd app
flutter pub get

cd ../rust
cargo fmt --check
cargo clippy --all-targets --all-features -- -D warnings
cargo test

cd ../app
flutter pub get
flutter gen-l10n
flutter analyze --no-pub
flutter test --no-pub

# arm64 Release APK，并验证 ABI、Rust 动态库、调试资源和 30 MiB 上限
cd ..
./scripts/build_android_release.ps1 -Artifact apk

# 商店候选优先使用 AAB
./scripts/build_android_release.ps1 -Artifact appbundle
```

Android 构建必须提供有效 `FLUTTER_ROOT`。产物检查要求包含 `libai_usage_core.so`，且不得包含 `kernel_blob.bin`、Vulkan validation layer 或非目标 Flutter engine；失败时脚本中止。本轮 Rust 格式、Clippy、23 个单元测试、Flutter analyze、3 个 Widget tests 和 Android arm64 Release 真机启动均已通过。

修改 Rust FFI 公共函数或模型后，需要重新生成 bridge：

```powershell
flutter_rust_bridge_codegen generate --config-file flutter_rust_bridge.yaml
```

## Android 体积说明

不要把 Debug 通用 APK 当作用户安装包。当前测量结果：

| 产物/数据 | 测量值 | 说明 |
| --- | ---: | --- |
| 旧 Debug 通用 APK | 193,327,790 bytes（约 184.37 MiB） | 包含多 ABI、Flutter Debug engine、kernel snapshot 和调试资源 |
| Debug 登录约 5 分钟后的主要用户数据 | 约 92 MB | 主要是 `kernel_blob.bin` 与快照复制；SQLite 仅约 32 KB |
| 旧功能基线 arm64 Release APK | 24,385,257 bytes（23.26 MiB） | 不含 `kernel_blob.bin`，包含 Rust 核心 |
| 当前 AiUsage arm64 Release APK | 25,511,245 bytes（24.33 MiB） | 含 `libai_usage_core.so`，通过发布产物检查 |
| 当前 Release 新安装数据 | 659,456 bytes（约 644 KiB） | 真机启动后的 PackageManager 统计，未完成账号登录 |

公开分发应优先使用 AAB，由应用商店按 ABI 下发。当前 Release 仅用于本机验证，仍使用开发签名，不是正式发布包。

## 已知限制

- 项目当前没有稳定 Release、自动更新器、正式签名安装包或商店发布。
- 完整重命名后的包 ID 为 `dev.chendusk.aiusage`；Alpha 阶段不迁移旧包 `dev.codexusage.monitor` 的凭据、设置或历史，两者可暂时共存。
- OpenAI 调整内部接口后，登录或额度查询可能失效，需要更新 compatibility layer。
- 第三方浏览器可能禁止向验证码输入框粘贴；应用提供复制、重新打开和重新申请验证码，但不会使用 WebView、无障碍或自动填充绕过限制。
- iOS 和 Android 后台调度都属于 best effort，不能保证固定刷新周期。
- Linux 托盘是否显示取决于桌面环境和 AppIndicator 支持。
- Android Release 已完成新安装与入口检查，但尚未在真实账号登录后连续运行 5 分钟复测数据增长。
- 不实现 Web、API Key 登录、其他 AI Provider、云同步、reset credit consume、Thread Usage、费用计算或企业 Admin API。

## 路线图

- 完成真实账号登录后的 Android 长时间运行与存储复测。
- 在真实 macOS、iOS 和 Linux 环境完成平台验收。
- 补充关键 Flutter controller/widget 测试和应用截图。
- OpenAI 上游发生变化时，更新兼容研究、fixture 和 provider 层。
- 在首个稳定候选版本前明确升级与本地数据库迁移策略。

## 非官方声明

This project is unofficial and is not affiliated with, endorsed by, or sponsored by OpenAI. “OpenAI” and “Codex” are trademarks of their respective owners.

使用本项目不会绕过 OpenAI 的认证、套餐或速率限制。用户应自行遵守 OpenAI 的服务条款，并承担使用未公开接口可能发生兼容中断的风险。

## License

[MIT](LICENSE)
