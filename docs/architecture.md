# 架构

AiUsage 使用 Flutter 构建界面和平台集成，Rust 负责认证边界、Provider 请求、数据标准化与 SQLite。两侧通过 `flutter_rust_bridge` 传递稳定模型，Flutter 不解析 Provider 原始响应。

```text
Flutter UI / Controller
  ├─ 导航、i18n、主题与演示模式
  ├─ 平台安全存储
  ├─ 前台/后台调度与通知
  └─ flutter_rust_bridge
          ↓
Rust Core
  ├─ Codex OAuth / DeepSeek API Key / MiMo Session
  ├─ Provider API compatibility layers
  ├─ raw response normalization
  └─ SQLite cache / history / diagnostics
```

## 凭据边界

Flutter 的平台安全存储是持久化凭据的唯一所有者。Rust 只在一次调用的内存边界中接收类型化凭据，完成请求或刷新后返回需要原子更新的凭据。MiMo 原始密码只参与当次登录，不进入持久层。

## Provider 标准化

每个账户记录 `ProviderKind`、别名、认证来源和带 Provider 前缀的 identity hash。Rust 将不同响应转换为稳定的余额、额度、Profile 和账户详情模型；Provider schema 变化只应影响对应 compatibility layer。

## 缓存与失败

SQLite 按账户隔离保存标准化快照、Codex Profile、账户资料和诊断。刷新失败不会清空最后一次成功结果，UI 会标记缓存采集时间与陈旧状态。删除账户时同步清理其缓存和诊断。

Codex 额度快照保留七天，用于概览离线显示；Profile Token 统计来自账号侧数据，不用本地额度百分比推算。DeepSeek 与 MiMo 暂不把余额快照伪装成 Token 历史。

## 诊断数据流

HTTP 边界记录 Provider、固定 endpoint、耗时、状态和脱敏后的有限响应。最多保留 200 条，每条原始正文最多 64 KiB。认证交换只记录结果类型，不保存原始响应。
