---
name: jira-acli
description: Manage Jira issues through jhelp shell functions (jv, jm, jd, jc, jforward, etc.). Use when the user wants to view, transition, assign, comment on, edit, search, or create Jira work items; when they provide a bare issue number, Jira issue key, or Jira URL; or when the task involves the current git branch ticket.
---

# Jira ACLI

Use `jhelp` shell functions as the primary interface. They wrap `acli jira` with key normalization and workflow logic already built in.

## Shell requirement

Always prefix Bash commands with `source ~/.zshrc 2>/dev/null;` — the tool runs a non-interactive shell that does not load `.zshrc` by default. Without this, `jhelp` functions and `JIRA_*` env vars will be missing.

```bash
source ~/.zshrc 2>/dev/null; jv PROJECT-3682
```

## Input formats accepted by all jhelp functions

- bare number: `3642` → resolves to `$JIRA_PROJECT-3642`
- explicit key: `PROJECT-3642`
- full Jira URL: `https://your-team.atlassian.net/browse/PROJECT-3642`

## Commands

### View / open

```bash
source ~/.zshrc 2>/dev/null; jv [TICKET]          # view in terminal
source ~/.zshrc 2>/dev/null; jo [TICKET]          # open in browser
source ~/.zshrc 2>/dev/null; jvb                  # view current branch ticket
```

### Move status

```bash
source ~/.zshrc 2>/dev/null; jm [TICKET]... "[STATUS]"   # move to any status
source ~/.zshrc 2>/dev/null; jip [TICKET]...             # → In Progress
source ~/.zshrc 2>/dev/null; jtest [TICKET]...           # → Testing
source ~/.zshrc 2>/dev/null; jblock [TICKET]...          # → Block
source ~/.zshrc 2>/dev/null; jreview [TICKET]...         # → Review
source ~/.zshrc 2>/dev/null; jir [TICKET]...             # alias of jreview
source ~/.zshrc 2>/dev/null; jprod [TICKET]...           # → Wait to build PROD
source ~/.zshrc 2>/dev/null; jdone [TICKET]...           # → DONE
source ~/.zshrc 2>/dev/null; jforward [TICKET]           # next workflow step
source ~/.zshrc 2>/dev/null; jbackward [TICKET]          # previous workflow step
source ~/.zshrc 2>/dev/null; jforwardb                   # forward current branch ticket
source ~/.zshrc 2>/dev/null; jbackwardb                  # backward current branch ticket
```

### Description

```bash
source ~/.zshrc 2>/dev/null; jdi [TICKET] "[TEXT]"       # replace description inline
source ~/.zshrc 2>/dev/null; jd [TICKET] [FILE]          # replace description from file
source ~/.zshrc 2>/dev/null; jdb [FILE]                  # update description for current branch ticket
```

### Comments

```bash
source ~/.zshrc 2>/dev/null; jc [TICKET] "[TEXT]"        # add comment inline
source ~/.zshrc 2>/dev/null; jcf [TICKET] [FILE]         # add comment from file
source ~/.zshrc 2>/dev/null; jcb "[TEXT]"                # comment on current branch ticket
```

### Assign

```bash
source ~/.zshrc 2>/dev/null; ja [TICKET]                 # assign to me
```

### Create

```bash
source ~/.zshrc 2>/dev/null; js [PARENT] "[SUMMARY]"             # create sub-task
source ~/.zshrc 2>/dev/null; jsd [PARENT] "[SUMMARY]" [FILE]     # create sub-task with description file
```

### Search / list

```bash
source ~/.zshrc 2>/dev/null; jmine                       # my current-sprint tickets
source ~/.zshrc 2>/dev/null; jmine -d                    # only not-done
source ~/.zshrc 2>/dev/null; jstories                    # stories for my sprint tickets
source ~/.zshrc 2>/dev/null; jqw "[JQL]"                 # search with JQL
```

### Current branch

```bash
source ~/.zshrc 2>/dev/null; jkey                        # extract PROJECT-xxxx from branch name
source ~/.zshrc 2>/dev/null; jvb                         # view current branch ticket
source ~/.zshrc 2>/dev/null; jib                         # move current branch → In Progress
source ~/.zshrc 2>/dev/null; jreviewb                    # move current branch → Review
source ~/.zshrc 2>/dev/null; jdoneb                      # move current branch → DONE
```

### Combined flows

```bash
source ~/.zshrc 2>/dev/null; jdm [TICKET] [FILE] "[STATUS]"                   # update description + move
source ~/.zshrc 2>/dev/null; jcm [TICKET] "[STATUS]" "[COMMENT]"              # comment + move
source ~/.zshrc 2>/dev/null; jdoneflow [TICKET] [FILE] "[STATUS]" [COMMENT_FILE]  # description + comment + move
```

## Auth

```bash
source ~/.zshrc 2>/dev/null; jastatus       # check auth
source ~/.zshrc 2>/dev/null; jalogin        # login in browser
source ~/.zshrc 2>/dev/null; jaswitch       # switch to $JIRA_SITE
```

## Workflow order

`TO DO` → `In Progress` → `Testing` → `Block` → `Review` → `Wait to build PROD` → `DONE`

Customise by setting `JIRA_WORKFLOW_STATUSES` in `.zshrc` before sourcing `jira.zsh`.

## Error handling

Stop with a clear explanation when:
- issue input is invalid or missing
- current branch has no Jira key
- referenced file does not exist
- auth is missing or expired — suggest `jalogin`
