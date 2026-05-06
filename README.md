<img width="12" height="22" alt="menubar_icon" src="https://github.com/user-attachments/assets/f201c089-701b-481c-90e2-48ef0583586f" /><?xml version="1.0" encoding="UTF-8"?>
<svg width="12" height="22" viewBox="5 10 44 92" xmlns="http://www.w3.org/2000/svg">
  <path d="M 30 15 v 60 A 20 20 0 0 1 10 95" fill="none" stroke="black" stroke-width="5" stroke-linecap="round"/>
  <circle cx="30" cy="75" r="2.5" fill="black"/>
  <circle cx="28.4" cy="82.6" r="2.5" fill="black"/>
  <circle cx="24.2" cy="89.2" r="2.5" fill="black"/>
  <circle cx="17.6" cy="93.4" r="2.5" fill="black"/>
  <circle cx="10" cy="95" r="2.5" fill="black"/>
  <circle cx="42" cy="95" r="4.5" fill="black"/>
</svg>


# JiraBar 🎟️ — Zero context switch. Full Jira control in menu bar and CLI.

Tiny macOS 14+ menu bar app that keeps your current-sprint Jira work visible without leaving the menu bar. Shows your stories, bugs, and tasks in separate sections, with per-ticket menus for assign / workflow transitions / browser open. Login, logout, and switch account straight from the menu. No Dock icon, minimal UI, live ticket count in the menu bar.

<img width="608" height="592" alt="jirabar_v1 1 0" src="https://github.com/user-attachments/assets/7eac515c-e42d-4ff1-ae1d-e17c682650fc" />

## Requirements

- macOS 14+ (Sonoma)
- [`acli`](https://acli.atlassian.com) installed (`brew install atlassian/tap/acli`)
- `jq` installed (`brew install jq`)

## Install

**Download DMG (recommended):**

[⬇️ Download JiraBar.dmg](https://github.com/mantrandev/JiraBar/releases/latest/download/JiraBar.dmg)

Open `JiraBar.dmg`, drag `JiraBar.app` to `/Applications`, and launch.

**Build from source (Xcode):**
```bash
open JiraBar.xcodeproj   # run the JiraBar scheme
```

**Build from source (CLI):**
```bash
./Scripts/package_app.sh
# Output: JiraBar.dmg (drag app → /Applications)
```

### First run
1. Launch `JiraBar.app` — the menu bar icon appears immediately.
2. Open **Settings** (menu bar → Settings…).
3. Under **CLI Tools**, confirm `acli` and `jq` show as installed. If not, click **Install with Homebrew** for each.
4. Set your Jira site (`your-team.atlassian.net`) under **Workspace → Preferred Site**.
5. Click **Save Site**, then click **Login**.
6. Complete authentication in your browser; JiraBar polls until it detects success.
7. *(Optional)* Under **Shell Helpers**, click **Install** to add `jira.zsh` terminal commands to your shell.

> **Gatekeeper note:** App is not code-signed. First launch: right-click → Open → Open.

---

## Features

- **Stories** section — your assigned stories in the active sprint.
- **Bugs** section — open bugs assigned to you (not Done).
- **Task + Subtask** section — open tasks and subtasks assigned to you (not Done).
- Per-ticket submenu:
  - Open in Jira (browser)
  - Assign to Me
  - Next Status / Previous Status (workflow order)
  - Move → full status list for your project, current status marked ✓
- Workflow statuses fetched once at login from your project, cached locally — no hardcoding.
- Settings window (opens top-right):
  - Preferred site, refresh interval (Manual / 30s / 1m / 2m / 5m), max items per section (3–20).
  - **CLI Tools** — shows `acli` and `jq` install status; Install with Homebrew button for each.
  - **Shell Helpers** — one-click install of `jira.zsh` to `~/.jira.zsh` with auto `source` in `~/.zshrc`.
- Switch Account and Logout from the menu or Settings.
- Menu bar title shows live bug+task count (`Jira 5`) or `Jira …` while loading.

---

## Shell helpers (optional)

`Scripts/jira.zsh` provides `jv`, `jm`, `jforward`, `jmine`, `jstories`, and ~40 other shorthand commands for managing Jira issues from the terminal.

**Install from the app (recommended):** Open **Settings → Shell Helpers** and click **Install**. This copies the script to `~/.jira.zsh` and adds `source ~/.jira.zsh` to your `~/.zshrc` automatically.

**Manual install:**

### 1. Copy the script

```bash
cp Scripts/jira.zsh ~/.jira.zsh
```

### 2. Configure and source in `.zshrc`

Add this block to your `~/.zshrc` **before** any other Jira config:

```zsh
export JIRA_SITE="your-team.atlassian.net"   # required
export JIRA_PROJECT="MYPROJECT"               # required — your Jira project key

# Optional overrides
# export JIRA_TODO_STATUS="TO DO"
# export JIRA_WORKFLOW_STATUSES=("TO DO" "In Progress" "Review" "DONE")

source ~/.jira.zsh
```

### 3. Reload

```bash
source ~/.zshrc
```

### Verify

```bash
jhelp          # print all available commands
jastatus       # check Jira auth status
```

### Quick reference

| Command | What it does |
|---|---|
| `jv TICKET` | View issue in terminal |
| `jo TICKET` | Open issue in browser |
| `ja TICKET` | Assign to me |
| `jm TICKET... "STATUS"` | Move to any status |
| `jip / jtest / jreview / jdone TICKET...` | Move to common statuses |
| `jforward / jbackward TICKET` | Step through workflow |
| `jmine` | My current-sprint tickets |
| `jstories` | Sprint stories assigned to me |
| `jib / jreviewb / jdoneb` | Move current git branch ticket |
| `jc TICKET "comment"` | Add comment |
| `jd TICKET file.md` | Replace description from file |
| `jalogin / jalogout` | Auth management |

TICKET accepts: bare number (`3642`), project key (`PROJECT-3642`), or full Jira URL.

---

## Claude Code / Pi skill (optional)

If you use [Claude Code](https://claude.ai/code) or [Pi](https://github.com/mariozechner/pi), the skill at `.claude/skills/jira-acli.md` teaches the agent to use the `jhelp` functions above.

**Install globally** (available in all projects):

```bash
mkdir -p ~/.claude/skills
cp .claude/skills/jira-acli.md ~/.claude/skills/
```

**Install locally** (this project only — already included in the repo):

The file is already at `.claude/skills/jira-acli.md` and will be picked up automatically.

---

## Architecture

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

## Runtime requirements

`acli` and `jq` must be reachable via the user's `~/.zshrc` PATH — the snapshot script sources it on every refresh.

---

## License

MIT
