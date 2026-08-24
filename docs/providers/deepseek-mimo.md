# DeepSeek 与 Xiaomi MiMo 集成

AiUsage 将账户索引、认证凭据和标准化快照分离：Provider、别名、状态和 identity hash 可进入安全账户索引；OAuth Token、API Key、密码、Cookie 与原始用户 ID 不进入 SQLite、诊断或普通日志。

## DeepSeek

- 固定请求 `GET https://api.deepseek.com/user/balance`，使用 Bearer API Key。
- 保存前必须成功完成一次余额校验。
- `total_balance`、`granted_balance`、`topped_up_balance` 始终按上游十进制字符串展示；CNY 与 USD 不合并、不换算。
- 401 表示 Key 无效，429 保留 `Retry-After`，网络或服务端错误优先展示本地缓存。

该接口是 DeepSeek 的公开 API，响应结构见[官方余额文档](https://api-docs.deepseek.com/zh-cn/api/get-user-balance/)。

## Xiaomi MiMo

MiMo 当前没有公开的余额 API。AiUsage 使用 `platform.xiaomimimo.com/api/v1` 下的控制台接口读取余额、Token Plan 详情与使用量，因此兼容性低于 DeepSeek。

普通路径中，密码仅用于一次小米 SSO 登录，随后立即从 Rust 内存中清零。持久化内容仅包括 `userId`、`passToken` 及 `api-platform_serviceToken` 等必要会话字段，统一写入系统安全存储。若登录要求 CAPTCHA、短信或 MFA，应用只加载小米官方 HTTPS 域名并由用户完成验证，不注入密码、不忽略证书错误、不绕过风控。

平台 Cookie 失效后使用 `userId + passToken` 续签。续签在进程内串行执行，同一轮刷新最多重试原请求一次；`passToken` 撤销或再次需要交互验证时停止后台重试并保留旧缓存。`passToken` 具有接近长期登录会话的权限，设备失陷仍可能导致账号风险。

当前固定读取：

- `/api/v1/balance`
- `/api/v1/tokenPlan/detail`
- `/api/v1/tokenPlan/usage`

MiMo endpoint、Cookie 名或 JSON schema 都可能在没有公告的情况下变化。AiUsage 不支持用户自定义 API URL，也不会从已安装浏览器自动抓取 Cookie。

## 诊断边界

DeepSeek 和 MiMo 的业务响应可按现有 64 KiB 上限脱敏记录，认证交换只记录结果类型，不保存原始正文。任何响应进入诊断前都会清除常见 Token、Key、Cookie 和账户 ID 字段；无法安全解析且疑似包含凭据的非 JSON 正文会整段丢弃。
