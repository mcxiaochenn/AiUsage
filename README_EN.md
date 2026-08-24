# AiUsage

[![CI](https://github.com/mcxiaochenn/AiUsage/actions/workflows/ci.yml/badge.svg)](https://github.com/mcxiaochenn/AiUsage/actions/workflows/ci.yml)
[![Release](https://img.shields.io/github/v/release/mcxiaochenn/AiUsage)](https://github.com/mcxiaochenn/AiUsage/releases/latest)
[![License](https://img.shields.io/github/license/mcxiaochenn/AiUsage)](LICENSE)

[简体中文](README.md) | English

AiUsage is a mobile-first, local-first monitor for AI service usage and balances. It currently supports OpenAI Codex, DeepSeek, and Xiaomi MiMo.

> [!IMPORTANT]
> Android is the primary supported platform. iOS is an active target and is compiled in CI, but it has not been tested on a physical device. Some Codex and MiMo integrations rely on internal APIs that may change without notice. Do not use AiUsage as the only source for critical balance alerts.

## Features

- Manage multiple Codex, DeepSeek, and MiMo accounts in one app.
- View Codex quotas, Credits, Reset Credits, and token usage statistics.
- View multi-currency DeepSeek balances and MiMo balances and Token Plans.
- Sign in with Codex Device Code, `auth.json`, or provider-specific methods.
- Keep credentials in platform secure storage; SQLite stores only redacted caches and diagnostics.
- Use English or Simplified Chinese, dynamic colors, demo mode, and offline cache.
- Background refresh is off by default; the last successful snapshot remains available after failures.

## Download and installation

Download AiUsage from [GitHub Releases](https://github.com/mcxiaochenn/AiUsage/releases/latest). There are currently no plans to publish it on Google Play, the App Store, or another app store.

### Android

| Package | Choose this for |
| --- | --- |
| `arm64-v8a` | Most modern Android phones; recommended |
| `universal` | Unknown device architecture; larger download |
| `armeabi-v7a` | Older 32-bit ARM devices |
| `x86_64` | 64-bit x86 emulators or rare devices |

The current published release still uses the old arm64 asset names. Four stable filenames will be available from the next release. Select an asset on the Release page and read the [installation guide](docs/installation.md) before upgrading.

### iOS

Future releases will include `AiUsage-ios-release-unsigned.ipa`. It cannot be installed like an App Store app: you must sign it yourself. Installation on jailbroken devices depends on the device and tooling. See the [installation guide](docs/installation.md) for signing constraints.

iOS is currently compiled only in macOS CI and has not been validated on a physical device. Please [open an issue](https://github.com/mcxiaochenn/AiUsage/issues/new/choose) if you encounter a problem.

## Providers

| Provider | Authentication | Data | Stability |
| --- | --- | --- | --- |
| OpenAI Codex | Device Code / `auth.json` | Quotas, Credits, Reset Credits, token statistics | Some internal APIs |
| DeepSeek | API Key | CNY/USD balance details | Official balance API |
| Xiaomi MiMo | Xiaomi account sign-in | Pay-as-you-go balance, Token Plan | Internal console API |

## Platform status

| Platform | Status |
| --- | --- |
| Android | Primary support; validated on a physical arm64 device |
| iOS | Active target; compiled in CI, not tested on a physical device |
| Windows / macOS / Linux | Later adaptation; no current release artifacts |
| Web | Not supported |

See [platform support](docs/platforms.md) for limitations and plans.

## Security and privacy

- OAuth tokens, API keys, MiMo sessions, and cookies are stored only in the system secure storage (Android Keystore / Apple Keychain).
- Raw passwords are never persisted; tokens, cookies, and raw account IDs are not written to SQLite or ordinary logs.
- The app has no telemetry, cloud sync, or account backend by default.
- Local diagnostics remove credentials and are size-limited, but may still contain non-secret profile data such as email addresses or plan names.

Read the full [security notes](docs/security.md), including internal API risks.

## Documentation and support

- [Documentation index](docs/README.md)
- [Installation](docs/installation.md)
- [Development and releases](docs/development.md)
- [Architecture](docs/architecture.md)
- [Roadmap](docs/roadmap.md)
- [Issue tracker](https://github.com/mcxiaochenn/AiUsage/issues)

## Unofficial project notice

AiUsage is an unofficial open-source project and is not affiliated with, endorsed by, sponsored by, or partnered with OpenAI, DeepSeek, or Xiaomi. Users are responsible for complying with provider terms and for risks related to credentials, data accuracy, and internal API changes.

## License

[MIT](LICENSE)
