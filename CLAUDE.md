# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Build & Run

```bash
# Xcode (preferred)
open JiraBar.xcodeproj   # then run the JiraBar scheme

# Release build to .build/xcode/Build/Products/Release/JiraBar.app
./Scripts/package_app.sh

# SPM fallback
swift build
swift test --filter JiraBarTests   # single test file
```

## Architecture

**JiraBar** is a macOS 14+ SwiftUI menu bar app (Swift 6, strict concurrency). No external Swift dependencies — only Apple frameworks and runtime CLI tools (`acli`, `jq`).

### Component Map

| File | Role |
|---|---|
| `JiraBarApp.swift` | `@main` entry, wires `JiraBarModel` into `MenuBarExtra` |
| `AppDelegate.swift` | Forces accessory mode (no Dock icon) on launch |
| `JiraBarModel.swift` | `@MainActor ObservableObject` — all state, refresh loop, UserDefaults |
| `JiraCLI.swift` | Wraps `acli jira …` commands; all shell strings prefixed with `shellPreamble` |
| `ShellCommandRunner.swift` | async/await `Process` wrappers: `run`, `runInteractive`, `launch` |
| `JiraModels.swift` | Codable structs: `JiraSnapshot`, `JiraTicket`, `JiraAuthState` |
| `Resources/jira_snapshot.zsh` | Bundled script; sources `~/.zshrc`, calls `acli`, emits JSON |
| `AppResources.swift` | Bundle resource loader with Xcode/SPM fallback paths |

### Data Flow

```
MenuBarContentView / SettingsView
        ↓ @ObservedObject
    JiraBarModel  ←→  UserDefaults (interval, max items, preferred site)
        ↓
    JiraCLI  →  ShellCommandRunner  →  Process (acli / jira_snapshot.zsh)
        ↓
    JiraModels (decoded JSON)
```

- `JiraBarModel` drives a `Task`-based periodic refresh loop (manual / 30s / 1m / 2m / 5m).
- All state mutations are `@MainActor`; async work happens in `Task` blocks.
- Shell arguments are escaped via the private `escape(_:)` in `JiraCLI`.
- ANSI/control characters are stripped from process output before display.

### Key Patterns

- **No singletons** — `JiraBarModel` is created once in `JiraBarApp` and passed as `@StateObject`.
- **Shell preamble** — every `acli` command in `JiraCLI` is built as `shellPreamble + command`; `shellPreamble` sources `~/.zshrc` so `acli` is on PATH.
- **Interactive login** — `login()` uses `ShellCommandRunner.runInteractive` with an `autoRespond` closure that detects acli's post-browser site-selection prompt and writes the matching site number to stdin automatically.
- **Auth polling** — after login, `startAuthPolling` calls `refresh(force: true)` every 2 seconds (up to 45×) until `snapshot.auth.authorized` is true.
- **Logout is immediate** — `logout()` is synchronous; it resets `snapshot = .empty` on the main actor before firing `acli auth logout` in a background `Task`.
- **Settings window** — opened via a custom `NSWindow` + `NSHostingController` managed as a static on `MenuBarContentView`. Switches activation policy to `.regular` while open, restores `.accessory` on close.
- **Resource loading** — `AppResources` tries bundle path first, falls back to SPM `.build` paths.

## Runtime Requirements

`acli` and `jq` must be installed and reachable via the user's `~/.zshrc` PATH (the snapshot script sources it).
