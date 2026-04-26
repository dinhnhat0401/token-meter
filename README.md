# Meter

Native macOS menu bar app that shows real-time Claude Code usage limits.

```
brew install --cask dinhnhat0401/tap/meter
```

Meter sits in your menu bar and tells you exactly how much of your Claude Code 5-hour and 7-day usage windows you have left, with **zero backend** and **zero telemetry**.

> Status: v1 supports Claude Code. Codex support arrives in v2.

## Screenshots

> _Add screenshots here once the binary is signed and running._
>
> - `docs/screenshot-menubar.png` — the menu bar icon and percentage badge
> - `docs/screenshot-popover.png` — the dropdown with both windows

## Why no backend

Meter is built on a single privacy invariant: **your token never leaves your machine except to talk to Anthropic directly.**

- **Keychain only.** Meter reads the OAuth access token that the official `claude` CLI already stores in your macOS Keychain (`Claude Code-credentials`). It never persists, copies, or transmits the token.
- **One outbound destination.** The only network calls Meter makes go to `api.anthropic.com`. No analytics, no Sentry, no third-party crash reporting, no SDKs. Audit the source — there is one HTTP client and one base URL.
- **No log of secrets.** Optional debug logs (`defaults write com.dinhnhat0401.meter EnableDebugLogs -bool YES`) redact the token before writing.
- **Local fallback.** If the Anthropic API is unreachable, Meter falls back to estimating from your local `~/.claude/projects/*.jsonl` files. Still no network calls.

## How it works

1. On launch, Meter reads `Claude Code-credentials` from the Keychain (you'll see the standard macOS Keychain permission prompt the first time).
2. It calls `GET https://api.anthropic.com/api/oauth/usage` with the access token.
3. It displays the 5-hour and 7-day window utilization in your menu bar and a click-to-open popover.
4. It refreshes every 60s while the popover is open, every 5 minutes in the background, and pauses while your Mac is asleep.

## Install

The packaged release is the recommended path:

```bash
brew install --cask dinhnhat0401/tap/meter
```

You'll need to sign in to Claude Code first if you haven't already:

```bash
claude  # follow the OAuth prompt
```

After install, launch **Meter** from Spotlight or Applications. The first launch will trigger the standard macOS Keychain access prompt.

## Build from source

```bash
git clone https://github.com/dinhnhat0401/meter.git
cd meter
brew install xcodegen
xcodegen generate
open Meter.xcodeproj
```

Or from the command line:

```bash
xcodegen generate
xcodebuild -scheme Meter -configuration Debug build
xcodebuild -scheme Meter test
```

### Requirements

- macOS 13 Ventura or newer
- Xcode 15 or newer (Swift 5.9+)
- `xcodegen` for project generation

## Privacy & security guarantees

| Guarantee | Where it's enforced |
|-----------|---------------------|
| No backend | There is none. No URL other than `api.anthropic.com` appears in source. |
| No analytics SDKs | Zero external Swift package dependencies. Inspect `project.yml`. |
| Token never persisted by Meter | Read on demand via `SecItemCopyMatching`. No write paths. |
| Logs redact secrets | `KeychainService` never logs token; debug log is opt-in. |
| File writes scoped | Only `~/Library/Application Support/Meter/` and `~/Library/Caches/Meter/`. |

## Disclaimer

Meter is **not affiliated with Anthropic**. The `oauth/usage` endpoint is reverse-engineered from the official `claude` CLI and may change without notice; if it does, Meter falls back to local estimates from `~/.claude/projects/*.jsonl` and shows an "(estimated)" badge in the popover.

## Roadmap (v2 and beyond)

- Codex / OpenAI integration
- Sparkle auto-updates
- Threshold notifications (80%, 95%)
- Per-project breakdown
- Historical charts
- Settings window
- Dollar-cost calculations

## License

MIT — see [LICENSE](LICENSE).

---

Built by **Nhat Dinh** ([@dinhnhat0401](https://github.com/dinhnhat0401)) in Tokyo. Part of the **OpenClaw** ecosystem.
