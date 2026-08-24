# 安装与升级

AiUsage 暂无 Google Play、App Store 或其他应用商店上架计划。请只从本仓库的 [GitHub Releases](https://github.com/mcxiaochenn/AiUsage/releases) 下载，并用同一 Release 的 `AiUsage-SHA256SUMS.txt` 校验文件。

## Android

下一版本开始提供以下 APK：

| 文件 | 适用场景 |
| --- | --- |
| `AiUsage-android-release-arm64-v8a.apk` | 大多数近年的 Android 手机，优先选择 |
| `AiUsage-android-release-armeabi-v7a.apk` | 只支持 32 位 ARM 的旧设备 |
| `AiUsage-android-release-x86_64.apk` | 64 位 x86 模拟器或少量设备 |
| `AiUsage-android-release-universal.apk` | 不确定架构时选择，包含上述三种 ABI，体积更大 |

Flutter 已不再支持 Android 32 位 x86，因此不会提供 `x86` APK。当前 v0.2.0 Release 仍是旧的 arm64 APK/AAB 资产矩阵；固定文件名从下一版本开始生效。

下载 APK 后，在系统设置中允许当前文件管理器或浏览器“安装未知应用”，再打开文件完成安装。升级安装必须使用相同包名和发布证书；若系统提示签名不一致，只能卸载旧应用后重装，这会删除本机凭据、设置和 SQLite 缓存。

## iOS

后续 Release 提供 `AiUsage-ios-release-unsigned.ipa`。该文件由 macOS CI 无签名构建，不含 Apple Developer 证书或 Provisioning Profile，不能直接作为 App Store 或 Ad Hoc 安装包使用。

用户需要使用自己的 Apple 身份与工具重新签名。免费或开发者签名的有效期、设备数量和权限取决于 Apple 账号及所用工具；项目不提供证书、UDID 注册或签名服务。越狱设备是否能安装未签名/重签 IPA 取决于系统版本和安装工具，项目不承诺可用。

iOS 目前没有物理设备验收条件。遇到启动、Keychain、文件选择、后台刷新或界面问题，请附系统版本和复现步骤[提交 Issue](https://github.com/mcxiaochenn/AiUsage/issues/new/choose)。

## 校验下载

在可信环境中计算文件 SHA-256，并与 Release 中的 `AiUsage-SHA256SUMS.txt` 对比。校验只能确认文件与发布附件一致，不能替代对 Provider 凭据风险和内部 API 稳定性的判断。
