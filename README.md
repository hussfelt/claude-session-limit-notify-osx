# Claude Session Monitor

A tiny macOS menu bar app that shows your current Claude Code 5-hour session usage as `XX%` and posts notifications as you approach the cap.

It's a thin native (Swift / AppKit) wrapper around [`ccusage`](https://github.com/ryoppippi/ccusage), which reads your local `~/.claude/projects/*.jsonl` transcripts. The percentage is an estimate based on your historical max session — it won't match `claude.ai/settings/usage` exactly, but it tracks the same 5-hour rolling window and only counts CLI usage.

## What you see

- **Menu bar:** `XX%` — color-coded (white < 60, yellow 60–80, orange 80–95, red 95+).
- **Dropdown:** current %, projected % at current burn rate, tokens used / limit, burn rate (tok/min), window reset time, current cost.
- **Notifications:** at 80%, 90%, 95%, 100%, and on session reset (when a new 5-hour window starts).

## Download

Prebuilt universal binaries (Apple Silicon + Intel) are published on the [Releases page](https://github.com/hussfelt/claude-session-limit-notify-osx/releases).

1. Download the `ClaudeSessionMonitor-vX.Y.Z.zip` from the latest release and unzip it.
2. Move `ClaudeSessionMonitor.app` to `/Applications`.
3. **First launch:** right-click the app → *Open* → *Open*. The build is ad-hoc signed (not notarized), so Gatekeeper will block a normal double-click on first run. After the first allow, future launches work normally.
4. Grant the notification permission prompt.
5. Optional: add it to *System Settings → General → Login Items* so it starts at login.

You can verify the download against the published checksum:

```bash
shasum -a 256 -c ClaudeSessionMonitor-vX.Y.Z.zip.sha256
```

## Requirements

| | |
|---|---|
| **OS** | macOS 13 (Ventura) or newer |
| **Swift toolchain** | Swift 5.9+ — install via Xcode, or run `xcode-select --install` for the Command Line Tools |
| **Node.js** | Any recent LTS — needed because the app shells out to [`ccusage`](https://github.com/ryoppippi/ccusage). Install Node from [nodejs.org](https://nodejs.org), Homebrew (`brew install node`), `nvm`, `volta`, or `bun` — all are auto-detected. |
| **`ccusage`** | Auto-fetched on demand via `npx ccusage@latest`. To skip the npx warm-up on every poll, install it globally: `npm i -g ccusage`. |
| **Claude Code usage history** | At least one prior session in `~/.claude/projects/` so `ccusage --token-limit max` can derive a sensible cap. Brand-new installs will report 0% until the first session completes. |

The app searches common Node install paths (`/opt/homebrew/bin`, `/usr/local/bin`, the latest `~/.nvm/versions/node/*/bin`, `~/.bun/bin`, `~/.volta/bin`, `~/.npm-global/bin`) so it works when launched from Finder, not just from a terminal that already has `node` on `PATH`.

## Build

```bash
git clone https://github.com/<your-fork>/claude-session-limit-notify-osx
cd claude-session-limit-notify-osx
./build.sh
```

`build.sh` does three things:

1. `swift build -c release` — produces the binary in `.build/release/`.
2. Assembles a `ClaudeSessionMonitor.app` bundle with the right `Info.plist` (`LSUIElement=true` so it lives only in the menu bar — no Dock icon).
3. Ad-hoc code-signs the bundle. This is required for `UNUserNotificationCenter` notifications to actually appear on macOS.

The result is `ClaudeSessionMonitor.app` next to `build.sh`.

## Run

```bash
open ClaudeSessionMonitor.app
```

The first launch prompts for notification permission — grant it, otherwise the threshold alerts will be silent.

## Install permanently

1. Move the bundle: `mv ClaudeSessionMonitor.app /Applications/`
2. Add to login items: **System Settings → General → Login Items → `+` → select `Claude Session Monitor`**.

## Dev loop

```bash
swift run                  # runs without bundling — note: notifications won't fire from an unbundled binary
./build.sh && open ClaudeSessionMonitor.app
```

## How the % is computed

`ccusage blocks --active --token-limit max --json` returns the current 5-hour block plus a `tokenLimitStatus.limit` derived from your historical max session.

- Menu bar % = `totalTokens / limit * 100` (current usage).
- Dropdown "Projected" = `tokenLimitStatus.percentUsed` (where you'd land at the current burn rate by window end).

## Project layout

```
Package.swift
Resources/Info.plist                       # LSUIElement=true → menu bar only
Sources/ClaudeSessionMonitor/
    main.swift                             # NSApplication entry
    AppDelegate.swift                      # wires the pieces together
    CCUsage.swift                          # process spawn + JSON model
    SessionMonitor.swift                   # polling loop (60s active / 5min idle)
    StatusBarController.swift              # NSStatusItem + dropdown
    NotificationManager.swift              # UNUserNotificationCenter + thresholds
build.sh                                   # produces ClaudeSessionMonitor.app
```

## License

MIT.

## Credits

- Initial scaffolding by **Claude Opus 4.7** ([Anthropic](https://www.anthropic.com)) inside [Claude Code](https://claude.com/claude-code).
- Idea, direction, and maintainer: **Henrik Hussfelt** — [@hussfelt](https://github.com/hussfelt).
- Co-conspirator and reviewer: **Anton Johansson** — [@johanssonanton](https://github.com/johanssonanton).

Built on top of [`ccusage`](https://github.com/ryoppippi/ccusage) by [@ryoppippi](https://github.com/ryoppippi) — without which we'd have nothing to read. Go star their repo.
