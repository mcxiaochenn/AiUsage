# 安全与隐私

AiUsage 是本地优先客户端，没有自建账号服务器、云同步、遥测或崩溃日志上传。开源不代表凭据没有风险：设备失陷、恶意系统组件或上游登录会话泄露仍可能影响账号安全。

## 凭据保存

- Codex OAuth Token、DeepSeek API Key、MiMo `userId + passToken` 和必要 Cookie 只写入 `flutter_secure_storage` 对应的平台安全存储。
- Android 使用 Keystore；iOS/macOS 使用 Keychain；桌面平台实现仍待后期验收。
- `auth.json` 仅在用户主动选择后读取，限制为 1 MiB，只在内存中解析，不复制原文件。
- MiMo 密码和一次性派生值只参与当前登录并主动清理；持久化的 `passToken` 权限接近长期登录会话，应像密码一样保护。
- 应用不会从浏览器自动抓取 Cookie，也不允许自定义 Provider URL。

## SQLite 与诊断

SQLite 可以保存 identity hash、非机密账户资料、标准化余额/额度、缓存时间和诊断，但不会保存 Authorization、API Key、OAuth Token、Cookie、原始密码或原始小米用户 ID。

诊断最多保留 200 条，每条响应正文最多 64 KiB。JSON 的常见 Token、Key、Cookie 和 ID 字段会被脱敏；疑似包含凭据且无法安全解析的非 JSON 正文会被丢弃。脱敏响应仍可能包含邮箱、套餐和余额等账户资料，因此 UI 默认折叠原始内容。

## Provider 风险

- DeepSeek 余额使用官方公开 API。
- Codex Usage、Profile、账户资料及 OAuth 兼容依赖官方客户端当前行为，但不等于 OpenAI 对第三方承诺稳定的公开 API。
- MiMo 余额、Token Plan 与 SSO 续签使用内部控制台接口，路径、Cookie 和 schema 可能无公告变化。

上游接口失效时，应用应保留缓存、显示明确错误并停止无意义重试，不能绕过 CAPTCHA、短信、MFA、套餐或速率限制。

## 用户责任

只从可信 Release 下载并校验 SHA-256；不要向 Issue、截图或诊断文本中粘贴 Token、API Key、Cookie、密码或完整 `auth.json`。怀疑凭据泄露时，应立即在对应 Provider 撤销或轮换凭据。
