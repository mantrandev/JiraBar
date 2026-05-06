# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Build & Run

```bash
# Xcode (preferred)
open JiraBar.xcodeproj   # then run the JiraBar scheme

# Release build + DMG
./Scripts/package_app.sh
# Output: JiraBar.dmg

# SPM fallback
swift build
swift test --filter JiraBarTests
```

When adding a new resource file (`.zsh`, `.svg`, etc.) it must be added in three places:
1. `Sources/Resources/` — picked up automatically by SPM
2. `PBXFileReference` section in `project.pbxproj`
3. `PBXBuildFile` section + `PBXResourcesBuildPhase` files list in `project.pbxproj`

## Architecture

**JiraBar** is a macOS 14+ SwiftUI menu bar app (Swift 6, strict concurrency). No external Swift dependencies — only Apple frameworks and runtime CLI tools (`acli`, `jq`).

### Component Map

| File | Role |
|---|---|
| `JiraBarApp.swift` | `@main` entry, wires `JiraBarModel` into `MenuBarExtra` |
| `AppDelegate.swift` | Forces accessory mode (no Dock icon) on launch |
| `JiraBarModel.swift` | `@MainActor ObservableObject` — all state, refresh loop, UserDefaults |
| `JiraCLI.swift` | Wraps `acli jira …` commands; all shell strings prefixed with `shellPreamble` |
| `ShellCommandRunner.swift` | async/await `Process` wrappers: `run`, `runInteractive`, `runWithPTY`, `launch` |
| `JiraModels.swift` | Codable structs: `JiraSnapshot`, `JiraTicket`, `JiraAuthState`, `RefreshInterval` |
| `MenuBarContentView.swift` | Menu content + `TicketRowMenu`; owns the `NSWindow` for Settings |
| `SettingsView.swift` | Settings form: workspace, refresh, commands, CLI tools, shell helpers |
| `AppResources.swift` | Bundle resource loader — `jiraSnapshotScriptURL`, `menuBarIconURL`, `jiraHelperScriptURL` |
| `Resources/jira_snapshot.zsh` | Bundled script; sources `~/.zshrc`, runs 3 JQL queries, emits JSON |
| `Resources/jira.zsh` | Bundled shell helper script installed to `~/.jira.zsh` via Settings |

### Data Flow

```
MenuBarContentView / SettingsView
        ↓ @ObservedObject
    JiraBarModel  ←→  UserDefaults (interval, maxItems, preferredSite, projectStatuses)
        ↓
    JiraCLI  →  ShellCommandRunner  →  Process (acli / jira_snapshot.zsh)
        ↓
    JiraModels (decoded JSON)
```

### Key Patterns

- **No singletons** — `JiraBarModel` is created once in `JiraBarApp` and passed as `@StateObject`.
- **Shell preamble** — every `acli` command in `JiraCLI` is built as `shellPreamble + command`; `shellPreamble` sources `~/.zshrc` so `acli` is on PATH.
- **Snapshot script** — `jira_snapshot.zsh` runs three direct JQL queries (Stories / Bugs / Tasks+Subtasks) and emits a single JSON object with `stories`, `bugs`, `tasks` arrays.
- **Project statuses** — `projectStatuses: [String]` is a flat ordered list fetched once at login via `acli workitem search --fields 'status'`, parsed by `JiraCLI.parseStatusesFromIssues`, and cached in UserDefaults. Used for Move submenu and Next/Previous Status.
- **Per-ticket action lock** — `actingOnTicketKey: String?` (not a global bool) disables only the ticket being acted on. `runAction` unlocks it immediately after the `acli` command completes; the post-action `refresh` fires as a background `Task` so the UI unblocks instantly.
- **Interactive login** — `login()` uses `ShellCommandRunner.runWithPTY` with an `autoRespond` closure that detects acli's post-browser site-selection prompt and writes `\r` to stdin automatically.
- **Logout is immediate** — `logout()` resets `snapshot = .empty` on the main actor before firing `acli auth logout` in a background `Task`.
- **Settings window** — `NSWindow` + `NSHostingController` managed as a static on `MenuBarContentView`. Opens off-screen at `(-10000, -10000)`, then `DispatchQueue.main.async` repositions to top-right of `NSScreen.main.visibleFrame` after layout completes. Uses `.floating` window level. Switches activation policy to `.regular` while open, restores `.accessory` on close.
- **CLI Tools check** — `SettingsView` runs `command -v acli/jq` via shell preamble on `.task`; shows version string or "Not installed" with Homebrew install button (opens Terminal via `NSAppleScript`).
- **Shell Helpers install** — copies bundled `jira.zsh` to `~/.jira.zsh` and appends `source ~/.jira.zsh` to `~/.zshrc` if not already present.
- **Resource loading** — `AppResources` uses `Bundle.module` (SPM) or `Bundle.main` (Xcode) with no fallback path needed for Xcode builds.

## Runtime Requirements

`acli` and `jq` must be installed and reachable via the user's `~/.zshrc` PATH — the snapshot script sources it on every refresh. Settings → CLI Tools shows their status and can install them via Homebrew.
