# JiraBar

Minimal macOS menu bar app for Jira current-sprint work.

Shows parent stories and your not-done sprint tickets. Per-ticket hover menus for assign / next / previous / explicit workflow status changes. Login / logout / switch account from the menu or Settings window.

## Requirements

- macOS 14+
- [`acli`](https://acli.atlassian.com) installed (`brew install atlassian/tap/acli`)
- `jq` installed (`brew install jq`)

## Install the app

**Build from source (Xcode):**

```bash
open JiraBar.xcodeproj
# Run the JiraBar scheme
```

**Build from source (CLI):**

```bash
./Scripts/package_app.sh
# Output: .build/xcode/Build/Products/Release/JiraBar.app
```

Copy `JiraBar.app` to `/Applications`, then launch it.

On first launch, open Settings (menu bar → Settings…), set your Jira site (`your-team.atlassian.net`), then click Login.

---

## Shell helpers (optional)

`Scripts/jira.zsh` provides `jv`, `jm`, `jforward`, `jmine`, `jstories`, and ~40 other shorthand commands for managing Jira issues from the terminal.

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
| `jstories` | Parent stories for my sprint tickets |
| `jib / jreviewb / jdoneb` | Move current git branch ticket |
| `jc TICKET "comment"` | Add comment |
| `jd TICKET file.md` | Replace description from file |
| `jalogin / jalogout` | Auth management |

TICKET accepts: bare number (`3642`), project key (`PROJECT-3642`), or full Jira URL.

---

## Claude Code skill (optional)

If you use [Claude Code](https://claude.ai/code), the skill at `.claude/skills/jira-acli.md` teaches Claude to use the `jhelp` functions above.

**Install globally** (available in all projects):

```bash
mkdir -p ~/.claude/skills
cp .claude/skills/jira-acli.md ~/.claude/skills/
```

**Install locally** (this project only — already included in the repo):

The file is already at `.claude/skills/jira-acli.md` and will be picked up automatically.

---

## Swift Package fallback

```bash
swift build
swift test
```
