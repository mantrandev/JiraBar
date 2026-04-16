# JiraBar

Minimal macOS menu bar app for Jira current-sprint work.

It reads your Jira auth and ticket state with direct `acli jira ...` commands and shows:

- parent stories for your current sprint work
- your not-done sprint tickets
- login / logout / switch account actions
- per-ticket hover submenus for assign / next / previous / explicit workflow status changes

## Requirements

- macOS 14+
- `acli` installed
- `jq` installed

## Xcode

Open [JiraBar.xcodeproj](JiraBar.xcodeproj) in Xcode and run the `JiraBar` scheme.

## CLI Build

```bash
./Scripts/package_app.sh
```

## Swift Package Fallback

```bash
swift build
swift test
```

## Notes

- Data loading uses a bundled `zsh` snapshot script that sources `~/.zshrc` first, then calls `acli jira ...` directly.
- Ticket actions use direct `acli jira auth ...` and `acli jira workitem ...` commands.
- The app does not hardcode any company site or project in the repo; account, site, and board context are discovered after login.
