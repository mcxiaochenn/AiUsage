# 平台支持

AiUsage 当前采用移动端优先策略：Android 是主要支持平台，iOS 是重点适配平台；桌面工程保留，但进入后期适配流程。

| 平台 | 工程状态 | 验证与发布状态 |
| --- | --- | --- |
| Android | Keystore、安全存储、文件选择、前台刷新和 WorkManager 已集成 | arm64 真机已验证；下一版本发布 universal 与三种分 ABI APK |
| iOS | Keychain、文件选择、前台刷新和 BGTaskScheduler 已集成 | macOS CI 无签名编译；没有物理设备验收，发布 unsigned IPA |
| Windows | 桌面窗口、托盘和安全存储工程保留 | 后期适配，不提供 Release 产物 |
| macOS | 桌面窗口、托盘和 Keychain 工程保留 | 后期适配，不提供桌面 Release 产物 |
| Linux | GTK、托盘和 Secret Service 工程保留 | 后期适配，不提供 Release 产物 |
| Web | 未集成 | 不在支持范围 |

“工程已集成”不等于“已正式支持”。Android 也尚未覆盖所有厂商的自启动/电池限制和所有 Provider 套餐形态。

## iOS 未实测说明

CI 只能证明 Xcode 编译、Rust 链接和 IPA 封装成功，不能替代物理设备上的 Keychain、系统浏览器回调、文件选择、通知和后台调度测试。项目目前没有可用 iOS 设备，因此不会宣称真机可用。欢迎通过 [Issue](https://github.com/mcxiaochenn/AiUsage/issues) 提供可复现反馈。

## 后台执行

Android WorkManager 与 iOS BGTaskScheduler 都由操作系统调度，不能保证固定周期。后台刷新默认关闭；Android 启用时会提示检查电池优化和后台活动设置。不同厂商的“自启动”状态目前没有统一可靠的读取方式。

## 桌面路线

Windows、macOS 和 Linux 将在移动端核心流程稳定后逐个平台恢复构建、安装、托盘和安全存储验收。当前源码工程用于保持可移植性，不构成安装支持承诺。
