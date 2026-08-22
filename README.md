# AiUsage

![CI](https://github.com/mcxiaochenn/AiUsage/actions/workflows/ci.yml/badge.svg)
![Release](https://img.shields.io/github/v/release/mcxiaochenn/AiUsage)
![Status](https://img.shields.io/badge/Android-stable-brightgreen)
![Version](https://img.shields.io/badge/version-v0.1.0-blue)
![License](https://img.shields.io/badge/license-MIT-green)

> [!IMPORTANT]
> **v0.1.0 Android Stable**：这是 AiUsage 首个正式签名的 Android 稳定版本。Windows、macOS、Linux 和 iOS 仍处于源码级实验支持；OpenAI 内部接口可能随时变化，请勿将本应用作为关键额度告警的唯一来源。

AiUsage 是一个本地优先的 OpenAI Codex 套餐额度监看应用 MVP。项目使用 Flutter 提供 Android、iOS、Windows、macOS 和 Linux 的统一界面，由 Rust 负责 OAuth、Usage API 兼容、数据标准化及 SQLite 历史。

**English summary:** AiUsage is a local-first Android monitor for OpenAI Codex usage limits. Version 0.1.0 is the first stable, signed Android release; other platform projects remain experimental. Credentials stay in platform secure storage, while the Rust core normalizes quota data and keeps history locally. This unofficial project relies on undocumented endpoints used by the official Codex client.

## 已实现功能

- 支持浏览器 Device Code OAuth，以及由用户通过系统文件选择器主动导入 Codex OAuth `auth.json`。
- 支持多个账号；重复导入同一账号时更新已有安全凭据。
- 支持 English、简体中文和跟随系统语言。
- access token 临近过期或 Usage 请求返回 401 时，最多刷新并重试一次。
- 动态处理零个、一个或任意多个 quota window，包括 `additional_rate_limits`。
- 展示已用/剩余百分比、额外额度余额/无限状态、重置倒计时、绝对时间、缓存状态和只读 Reset Credits 到期详情。
- 通过 Codex Profile 数据展示累计 Token、单日峰值、任务时长、连续使用统计和每日热力图；账号侧统计可能延迟。
- 账户详情按需读取注册时间并计算已注册天数；接口不可用时明确显示未知，不使用其他时间猜测。
- 保存 7 天标准化额度快照，并缓存最近一次 Profile 与账户资料；同步诊断最多保留 200 条脱敏记录。
- 支持 System/Light/Dark、默认关闭的系统动态取色、完整合成演示态、前台 Manual/5/15/30 分钟刷新和本地阈值通知。
- 移动端后台自动刷新与前台间隔分离且默认关闭；启用前提示耗电并引导用户检查系统设置。
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
        ├─ Codex Usage / Profile / account details compatibility layer
        ├─ raw response normalization
        └─ SQLite cache, seven-day quota history and redacted diagnostics
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

Flutter 不解析 OpenAI 原始 JSON。跨 FFI 只传递稳定模型，例如 `UsageSnapshot`、`CreditsSnapshot`、`ProfileUsage`、`AccountDetails` 和 `SyncLogEntry`。

## 安全与隐私

- OAuth `access_token`、`refresh_token` 和 `id_token` 仅通过 `flutter_secure_storage` 持久化。
- `auth.json` 只在用户主动选择文件后读取，限制为 1 MiB；仅在内存中解析，不复制原文件、不写 SQLite、不记录 Token。
- API Key-only、缺少身份信息或格式异常的文件会被拒绝；应用不会自动扫描 `~/.codex/auth.json`。
- Android 使用 Keystore；iOS/macOS 使用 Keychain；Windows 使用系统保护存储；Linux 使用 Secret Service。
- Rust 只在单次调用的内存边界中接收凭据；`Authorization`、OAuth Token、原始账户 ID 和安全存储内容不会写入 SQLite 或诊断。
- 诊断最多保存 200 条，每条原始响应正文上限 64 KiB；JSON 中的 Token 与 ID 字段会脱敏，非 JSON 响应检测到凭据特征时整段丢弃。原始响应仍可能包含邮箱、套餐等账户资料，UI 默认折叠。
- SQLite 保存 identity hash、非机密账号信息、标准化 quota、Profile 缓存、账户资料和诊断；额度快照启动时清理七天前记录，删除账户时清理其关联数据。
- 429 尊重 `Retry-After`，5xx 只做有限指数退避，错误时保留陈旧缓存。
- 默认不包含 analytics、telemetry、crash report 上传、后端服务、账号同步或 cloud sync。

## OpenAI 兼容层

实现依据是上游 `openai/codex` 的当前源码研究，详见 [OpenAI Codex 兼容性研究](docs/openai-codex-research.md)。当前兼容以下路径风格：

- ChatGPT backend：`/backend-api/wham/usage`、`/backend-api/wham/rate-limit-reset-credits` 与 `/backend-api/wham/profiles/me`
- Codex API：`/api/codex/usage` 与 `/api/codex/rate-limit-reset-credits`
- OpenAI account details：`https://api.openai.com/v1/me`

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
./scripts/build_android_release.ps1 -Format apk

# 商店候选优先使用 AAB
./scripts/build_android_release.ps1 -Format appbundle
```

Android 构建必须提供有效 `FLUTTER_ROOT` 和 `AIUSAGE_ANDROID_*` 签名环境变量。产物检查要求包含 `libai_usage_core.so`，且不得包含 `kernel_blob.bin`、Vulkan validation layer 或非目标 Flutter engine；正式产物还必须匹配固定证书 SHA-256。本轮 Rust 格式、Clippy、35 个单元测试、Flutter analyze、16 个 Widget tests、Android arm64 APK/AAB 构建及签名检查均已通过。

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
| v0.1.0 arm64 Release APK 候选 | 25,320,930 bytes（24.15 MiB） | 含 `libai_usage_core.so`，通过 ABI、体积和签名检查 |
| v0.1.0 arm64 Release AAB 候选 | 25,569,773 bytes（24.39 MiB） | 供后续商店提交，使用同一发布证书 |
| 当前 Release 应用数据 | 999,424 bytes（约 976 KiB） | 已登录真机完成演示态、详情页与历史页验收后的 PackageManager 统计 |

GitHub Release 提供正式签名的 arm64 APK 和 AAB；直接安装使用 APK，AAB 仅作为后续商店提交候选。下载后可使用同版本 `SHA256SUMS` 文件校验完整性。

## 已知限制

- 当前没有自动更新器或应用商店发布；用户需要从 GitHub Release 手动下载安装包。
- 完整重命名后的包 ID 为 `dev.chendusk.aiusage`；不迁移旧包 `dev.codexusage.monitor` 的凭据、设置或历史，两者可暂时共存。
- OpenAI 调整内部接口后，登录或额度查询可能失效，需要更新 compatibility layer。
- 第三方浏览器可能禁止向验证码输入框粘贴；应用提供复制、重新打开和重新申请验证码，但不会使用 WebView、无障碍或自动填充绕过限制。
- iOS 和 Android 后台调度默认关闭且属于 best effort，不能保证固定刷新周期；各厂商自启动/电池限制当前只能由用户在系统设置中确认。
- Profile Token 统计由账号侧异步生成，可能缺失当天 bucket 或明显滞后，不能作为实时计费依据。
- `/backend-api/wham/profiles/me` 与 `/v1/me` 均未被本项目视为面向第三方的稳定兼容承诺。
- Linux 托盘是否显示取决于桌面环境和 AppIndicator 支持。
- Android Release 已完成新安装与入口检查，但尚未在真实账号登录后连续运行 5 分钟复测数据增长。
- 不实现 Web、API Key 登录、其他 AI Provider、云同步、reset credit consume、Thread Usage、费用计算或企业 Admin API。

## 路线图

- 完成真实账号登录后的 Android 长时间运行与存储复测。
- 在真实 macOS、iOS 和 Linux 环境完成平台验收。
- 补充关键 Flutter controller/widget 测试和应用截图。
- OpenAI 上游发生变化时，更新兼容研究、fixture 和 provider 层。
- 在首个稳定候选版本前明确升级与本地数据库迁移策略。

### PLAN：Android 后台权限检测

- 调研不同 Android 厂商对自启动、后台活动和电池“无限制”状态的可读接口，优先使用公开系统 API，不依赖无障碍服务。
- 能可靠检测时，在用户启用后台刷新后回读状态并显示逐项结果；无法检测时继续明确标注“需要手动确认”，不伪造已授权状态。
- 为主流厂商设置页增加经过真机验证的定向入口，并保留标准应用详情/电池优化页面作为回退。
- 后台刷新成功率和最近执行时间只保存在本机诊断中，不增加遥测或远程上报。

## 非官方声明

This project is unofficial and is not affiliated with, endorsed by, or sponsored by OpenAI. “OpenAI” and “Codex” are trademarks of their respective owners.

使用本项目不会绕过 OpenAI 的认证、套餐或速率限制。用户应自行遵守 OpenAI 的服务条款，并承担使用未公开接口可能发生兼容中断的风险。

## License

[MIT](LICENSE)
