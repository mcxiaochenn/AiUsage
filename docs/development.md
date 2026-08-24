# 开发与发布

## 环境

- Flutter 3.47.1 / Dart 3.13.1
- Rust stable，包含 `rustfmt` 与 `clippy`
- Android SDK、JDK 17
- iOS 构建需要 macOS、Xcode 和 CocoaPods

Windows 开发 Flutter plugin 时需要开启 Developer Mode，以允许创建 symlink。仓库应位于纯英文路径，避免 Android/Kotlin 工具链跨盘符缓存问题。

## 常用验证

```powershell
cd rust
cargo fmt --check
cargo clippy --all-targets --all-features -- -D warnings
cargo test

cd ../app
flutter pub get
flutter gen-l10n
dart format --output=none --set-exit-if-changed lib test
flutter analyze --no-pub
flutter test --no-pub
```

修改 Rust FFI 公共函数或模型后重新生成 bridge：

```powershell
flutter_rust_bridge_codegen generate --config-file flutter_rust_bridge.yaml
```

## 唯一版本入口

人工维护的应用版本只写在 `app/pubspec.yaml`：

```yaml
version: 0.2.0
```

不要添加 `+buildNumber`。Android `versionCode` 与 iOS `CFBundleVersion` 均由构建脚本执行 `git rev-list --count HEAD` 生成；Android `versionName` 与 iOS `CFBundleShortVersionString` 读取同一个 SemVer。Rust crate 是内部组件，`Cargo.toml` 版本不参与 Release Tag 校验。

构建必须使用完整 Git 历史。浅克隆会直接失败；GitHub Actions 的构建 Job 使用 `fetch-depth: 0`。历史重写可能让 commit 数下降，导致系统拒绝覆盖安装，因此发布后不得随意重写主分支历史。

## Android Release

签名构建需要设置现有 `AIUSAGE_ANDROID_*` 环境变量，并确保 `FLUTTER_ROOT` 可用：

```powershell
./scripts/build_android_release.ps1 -Target all -RequireSignature
```

`-Target` 支持 `all`、`universal`、`arm64-v8a`、`armeabi-v7a`、`x86_64`。脚本会校验包名、版本、commit build number、ABI、`libai_usage_core.so`、禁用的 Debug 资源与签名证书。分 ABI 构建必须使用 `force-version-code-ignoring-abi=true`，禁止 Flutter 给不同 ABI 自动添加 versionCode 偏移。

## main 测试候选构建

每次推送到 `main`，`Main Test Builds` 工作流都会使用正式发布证书构建同一套 Android APK 与 unsigned iOS IPA，但只上传为保留 14 天的 GitHub Actions Artifact，不创建 Release。Android 的 universal、arm64-v8a、armeabi-v7a、x86_64 四种 APK 会并行构建，优先缩短单个测试包的可下载等待时间；正式 Release 仍保留单 Job 的完整构建流程。产物文件名包含对应 commit SHA，适合直接下载后进行覆盖安装测试；它们不是正式发布版本。

该工作流只响应受信任的 `main` push，绝不在 PR 或 fork 中读取 Android 签名 Secrets。

## iOS unsigned IPA

macOS 上运行：

```bash
./scripts/build_ios_release.sh
```

脚本执行无签名 Release 构建，校验 Bundle ID、SemVer、commit build number、主程序和 Rust 链接，再将 `Runner.app` 封装为 `Payload/Runner.app`。产物明确命名为 `unsigned`；仓库不接收 Apple 私钥、证书或 Provisioning Profile。

## 发布规则

Tag 使用 `vX.Y.Z`，必须与 `app/pubspec.yaml` 完全一致。Release 工作流先通过 Rust、Flutter、Android 和 iOS 门禁，再并行生成四个 Android APK 与一个 unsigned IPA，最后统一生成 `AiUsage-SHA256SUMS.txt`。

v0.2.0 Release 保持旧资产矩阵；新规则从 v0.2.1 开始生效。
