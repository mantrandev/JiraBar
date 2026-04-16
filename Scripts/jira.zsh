# Atlassian CLI helpers — generic Jira shell functions
# Source this file in .zshrc after setting JIRA_SITE and JIRA_PROJECT:
#
#   export JIRA_SITE="your-team.atlassian.net"
#   export JIRA_PROJECT="MYPROJECT"
#   source /path/to/jira.zsh
#
# Optional overrides (shown with defaults):
#   export JIRA_TODO_STATUS="TO DO"
#   export JIRA_CACHE_DIR="$HOME/.cache/jira-helper"

: "${JIRA_TODO_STATUS:=TO DO}"
: "${JIRA_CACHE_DIR:=${XDG_CACHE_HOME:-$HOME/.cache}/jira-helper}"
: "${JIRA_STORIES_CACHE_FILE:=${JIRA_CACHE_DIR}/stories.json}"
: "${JIRA_STORIES_CACHE_VERSION:=2}"
export JIRA_SITE JIRA_PROJECT

typeset -ga JIRA_WORKFLOW_STATUSES
if (( ${#JIRA_WORKFLOW_STATUSES[@]} == 0 )); then
  JIRA_WORKFLOW_STATUSES=(
    "${JIRA_TODO_STATUS}"
    "In Progress"
    "Testing"
    "Block"
    "Review"
    "Wait to build PROD"
    "DONE"
  )
fi

# ---------------------------------------------------------------------------
# Internal helpers
# ---------------------------------------------------------------------------

# Normalize issue input:
#   3642                            -> PROJECT-3642
#   PROJECT-3642                    -> PROJECT-3642
#   https://team.atlassian.net/...  -> PROJECT-3642
_jira_key() {
  local input="$1"

  if [[ -z "$input" ]]; then
    echo "Missing issue input" >&2
    return 1
  fi

  if [[ "$input" =~ ^https?://[^/]+/browse/([A-Z][A-Z0-9_]*-[0-9]+)$ ]]; then
    echo "${match[1]}"
    return 0
  fi

  if [[ "$input" =~ ^[0-9]+$ ]]; then
    echo "${JIRA_PROJECT}-${input}"
    return 0
  fi

  if [[ "$input" =~ ^[A-Z][A-Z0-9_]*-[0-9]+$ ]]; then
    echo "$input"
    return 0
  fi

  echo "Invalid issue input: $input" >&2
  return 1
}

jira() {
  acli jira "$@"
}

_jira_current_status() {
  local key="$(_jira_key "$1")" || return 1
  local output current_status

  output="$(acli jira workitem view "$key" --fields status --json 2>/dev/null)" || {
    echo "Failed to fetch current status for ${key}" >&2
    return 1
  }

  if (( $+commands[jq] )); then
    current_status="$(
      print -r -- "$output" | jq -r '
        [
          .fields.status.name?,
          .status.name?,
          .status?,
          .fields.status?,
          (.. | objects | .fields?.status?.name?),
          (.. | objects | .status?.name?),
          (.. | objects | .status? | select(type == "string"))
        ]
        | map(select(type == "string" and length > 0))
        | .[0] // empty
      ' 2>/dev/null
    )"
  fi

  if [[ -z "$current_status" ]]; then
    output="$(acli jira workitem view "$key" --fields status 2>/dev/null)" || {
      echo "Failed to fetch current status for ${key}" >&2
      return 1
    }

    current_status="$(
      print -r -- "$output" \
        | sed -nE 's/^[[:space:]]*[Ss]tatus[[:space:]]*[:|][[:space:]]*(.+)$/\1/p' \
        | head -n1
    )"
  fi

  if [[ -z "$current_status" ]]; then
    echo "Unable to determine current status for ${key}" >&2
    return 1
  fi

  echo "$current_status"
}

_jira_workflow_index() {
  local wanted_status="$1"
  local i=1
  local workflow_status

  for workflow_status in "${JIRA_WORKFLOW_STATUSES[@]}"; do
    if [[ "$workflow_status" == "$wanted_status" ]]; then
      echo "$i"
      return 0
    fi
    ((i++))
  done

  return 1
}

_jira_collect_keys() {
  reply=()
  local input raw trimmed key
  local -A seen

  for input in "$@"; do
    for raw in ${(s:,:)input}; do
      trimmed="${${raw##[[:space:]]#}%%[[:space:]]#}"
      [[ -z "$trimmed" ]] && continue

      key="$(_jira_key "$trimmed")" || return 1
      if [[ -z "${seen[$key]}" ]]; then
        reply+=("$key")
        seen[$key]=1
      fi
    done
  done

  if (( ${#reply[@]} == 0 )); then
    echo "Missing issue input" >&2
    return 1
  fi
}

_jira_search_keys() {
  local jql="$1"
  local output
  local keys_text

  output="$(acli jira workitem search --jql "$jql" --fields key --paginate 2>/dev/null)" || {
    echo "Failed to search Jira work items" >&2
    return 1
  }

  keys_text="$(print -r -- "$output" | grep -oE '[A-Z][A-Z0-9_]*-[0-9]+' | awk '!seen[$0]++')"
  if [[ -n "$keys_text" ]]; then
    reply=("${(@f)keys_text}")
  else
    reply=()
  fi
}

_jira_transition_keys() {
  local target_status="$1"
  shift

  local key current_status
  local failures=0

  for key in "$@"; do
    [[ -z "$key" ]] && continue

    current_status="$(_jira_current_status "$key" 2>/dev/null)"
    if [[ "$current_status" == "$target_status" ]]; then
      echo "Skipping ${key}: already in ${target_status}" >&2
      continue
    fi

    echo "Moving ${key} -> ${target_status}" >&2
    if ! acli jira workitem transition --key "$key" --status "$target_status" --yes; then
      ((failures++))
    fi
  done

  (( failures == 0 ))
}

_jira_view_json() {
  local key="$(_jira_key "$1")" || return 1
  local fields="$2"

  acli jira workitem view "$key" --fields "$fields" --json 2>/dev/null || {
    echo "Failed to fetch work item details for ${key}" >&2
    return 1
  }
}

_jira_json_first_string() {
  local output="$1"
  local filter="$2"

  print -r -- "$output" | jq -r "$filter" 2>/dev/null | sed -n '/./{p;q;}'
}

_jira_json_issue_type() {
  local output="$1"

  _jira_json_first_string "$output" '
    [
      .fields.issuetype.name?,
      .fields.issueType.name?,
      .issuetype.name?,
      .issueType.name?,
      .fields.issuetype?,
      .fields.issueType?,
      .issuetype?,
      .issueType?
    ]
    | map(select(type == "string" and length > 0))
    | .[]
  '
}

_jira_json_parent_key() {
  local output="$1"

  _jira_json_first_string "$output" '
    [
      .fields.parent.key?,
      .parent.key?,
      .issue.fields.parent.key?,
      .data.fields.parent.key?
    ]
    | map(select(type == "string" and test("^[A-Z][A-Z0-9_]*-[0-9]+$")))
    | .[]
  '
}

_jira_cache_mkdir() {
  mkdir -p "$JIRA_CACHE_DIR" 2>/dev/null || {
    echo "Failed to create cache dir: ${JIRA_CACHE_DIR}" >&2
    return 1
  }
}

_jira_story_cache_signature() {
  local -a keys
  keys=("${(@on)@}")
  print -r -- "${(j:,:)keys}"
}

_jira_story_cache_clear() {
  [[ -f "$JIRA_STORIES_CACHE_FILE" ]] || return 0
  rm -f "$JIRA_STORIES_CACHE_FILE" 2>/dev/null
}

_jira_story_cache_read() {
  local expected_signature="$1"

  [[ -f "$JIRA_STORIES_CACHE_FILE" ]] || return 1

  jq -e \
    --arg site "$JIRA_SITE" \
    --arg project "$JIRA_PROJECT" \
    --arg signature "$expected_signature" \
    --arg version "$JIRA_STORIES_CACHE_VERSION" \
    '
      .site == $site
      and .project == $project
      and ((.version | tostring) == $version)
      and .child_signature == $signature
      and (.output | type == "string" and length > 0)
    ' \
    "$JIRA_STORIES_CACHE_FILE" >/dev/null 2>&1 || {
      _jira_story_cache_clear
      return 1
    }

  jq -r '.output' "$JIRA_STORIES_CACHE_FILE" 2>/dev/null
}

_jira_story_cache_write() {
  local signature="$1"
  local output="$2"
  local tmp_file

  _jira_cache_mkdir || return 1
  tmp_file="${JIRA_STORIES_CACHE_FILE}.tmp.$$"

  jq -n \
    --arg site "$JIRA_SITE" \
    --arg project "$JIRA_PROJECT" \
    --arg version "$JIRA_STORIES_CACHE_VERSION" \
    --arg signature "$signature" \
    --arg generated_at "$(date -u +"%Y-%m-%dT%H:%M:%SZ")" \
    --arg output "$output" \
    '
      {
        site: $site,
        project: $project,
        version: $version,
        child_signature: $signature,
        generated_at: $generated_at,
        output: $output
      }
    ' >| "$tmp_file" 2>/dev/null || {
      rm -f "$tmp_file" 2>/dev/null
      return 1
    }

  mv "$tmp_file" "$JIRA_STORIES_CACHE_FILE" 2>/dev/null || {
    rm -f "$tmp_file" 2>/dev/null
    return 1
  }
}

# ---------------------------------------------------------------------------
# Public commands
# ---------------------------------------------------------------------------

jo() {
  local key="$(_jira_key "$1")" || return 1
  open "https://${JIRA_SITE}/browse/${key}"
}

jv() {
  local key="$(_jira_key "$1")" || return 1
  acli jira workitem view "$key"
}

jm() {
  local target_status="${argv[-1]}"
  local -a issue_args keys

  if (( $# < 2 )) || [[ -z "$target_status" ]]; then
    echo 'Usage: jm <issue|number|url>... "<status>"' >&2
    return 1
  fi

  issue_args=("${(@)argv[1,-2]}")
  _jira_collect_keys "${issue_args[@]}" || return 1
  keys=("${reply[@]}")

  _jira_transition_keys "$target_status" "${keys[@]}"
}

jmove() { jm "$@"; }

jd() {
  local key="$(_jira_key "$1")" || return 1
  local file="$2"

  if [[ -z "$file" ]]; then
    echo "Usage: jd <issue|number|url> <description-file>" >&2
    return 1
  fi

  if [[ ! -f "$file" ]]; then
    echo "File not found: $file" >&2
    return 1
  fi

  acli jira workitem edit --key "$key" --description-file "$file" --yes
}

jdi() {
  local key="$(_jira_key "$1")" || return 1
  shift

  local text="$*"
  if [[ -z "$text" ]]; then
    echo 'Usage: jdi <issue|number|url> "<description text>"' >&2
    return 1
  fi

  acli jira workitem edit --key "$key" --description "$text" --yes
}

jc() {
  local key="$(_jira_key "$1")" || return 1
  shift

  local text="$*"
  if [[ -z "$text" ]]; then
    echo 'Usage: jc <issue|number|url> "<comment>"' >&2
    return 1
  fi

  acli jira workitem comment create --key "$key" --body "$text"
}

jcf() {
  local key="$(_jira_key "$1")" || return 1
  local file="$2"

  if [[ -z "$file" ]]; then
    echo "Usage: jcf <issue|number|url> <comment-file>" >&2
    return 1
  fi

  if [[ ! -f "$file" ]]; then
    echo "File not found: $file" >&2
    return 1
  fi

  acli jira workitem comment create --key "$key" --body-file "$file"
}

ja() {
  local key="$(_jira_key "$1")" || return 1
  acli jira workitem edit --key "$key" --assignee "@me" --yes
}

js() {
  local parent="$(_jira_key "$1")" || return 1
  shift

  local summary="$*"
  if [[ -z "$summary" ]]; then
    echo 'Usage: js <parent-issue|number|url> "<summary>"' >&2
    return 1
  fi

  acli jira workitem create \
    --type "Sub-task" \
    --parent "$parent" \
    --summary "$summary" \
    --yes
}

jsd() {
  local parent="$(_jira_key "$1")" || return 1
  local summary="$2"
  local file="$3"

  if [[ -z "$summary" || -z "$file" ]]; then
    echo 'Usage: jsd <parent-issue|number|url> "<summary>" <description-file>' >&2
    return 1
  fi

  if [[ ! -f "$file" ]]; then
    echo "File not found: $file" >&2
    return 1
  fi

  acli jira workitem create \
    --type "Sub-task" \
    --parent "$parent" \
    --summary "$summary" \
    --description-file "$file" \
    --yes
}

jqw() {
  if [[ -z "$*" ]]; then
    echo 'Usage: jqw "<jql>"' >&2
    return 1
  fi

  acli jira workitem search --jql "$*"
}

jmine() {
  local jql="project = ${JIRA_PROJECT} AND assignee = currentUser() AND sprint in openSprints()"

  while (( $# > 0 )); do
    case "$1" in
      -d|--undone)
        jql+=" AND statusCategory != Done"
        ;;
      -h|--help)
        echo 'Usage: jmine [-d|--undone]' >&2
        return 0
        ;;
      *)
        echo 'Usage: jmine [-d|--undone]' >&2
        return 1
        ;;
    esac
    shift
  done

  jql+=" ORDER BY Rank ASC"
  acli jira workitem search \
    --jql "$jql" \
    --fields "issuetype,key,status,summary" \
    --paginate
}

jstories() {
  local child_jql child_json parent_key issue_type child_signature cached_output story_output
  local -a child_keys parent_keys
  local key
  local -A seen_parents

  child_jql="project = ${JIRA_PROJECT} AND assignee = currentUser() AND sprint in openSprints()"
  _jira_search_keys "$child_jql" || return 1
  child_keys=("${reply[@]}")

  if (( ${#child_keys[@]} == 0 )); then
    _jira_story_cache_clear
    echo "No open ${JIRA_PROJECT} tickets assigned to you in the current sprint" >&2
    return 0
  fi

  child_signature="$(_jira_story_cache_signature "${child_keys[@]}")"
  cached_output="$(_jira_story_cache_read "$child_signature" 2>/dev/null)"
  if [[ -n "$cached_output" ]]; then
    print -r -- "$cached_output"
    return 0
  fi

  for key in "${child_keys[@]}"; do
    child_json="$(_jira_view_json "$key" "parent,issuetype")" || return 1
    parent_key="$(_jira_json_parent_key "$child_json")"
    issue_type="$(_jira_json_issue_type "$child_json")"

    if [[ -z "$parent_key" && "$issue_type" == "Story" ]]; then
      parent_key="$key"
    fi

    [[ -z "$parent_key" ]] && continue
    if [[ -z "${seen_parents[$parent_key]}" ]]; then
      parent_keys+=("$parent_key")
      seen_parents[$parent_key]=1
    fi
  done

  if (( ${#parent_keys[@]} == 0 )); then
    _jira_story_cache_clear
    echo "No parent stories found for your open ${JIRA_PROJECT} tickets in the current sprint" >&2
    return 0
  fi

  story_output="$(
    acli jira workitem search \
    --jql "key in (${(j:,:)parent_keys}) ORDER BY key" \
    --fields "issuetype,key,status,summary" \
    --paginate 2>/dev/null
  )" || {
    echo "Failed to fetch your parent stories" >&2
    return 1
  }

  print -r -- "$story_output"
  _jira_story_cache_write "$child_signature" "$story_output" >/dev/null 2>&1 || true
}

jstoriesclear() {
  _jira_story_cache_clear
  echo "Cleared jstories cache: ${JIRA_STORIES_CACHE_FILE}"
}

jmsubtasks() {
  local parent="$(_jira_key "$1")" || return 1
  local target_status="$2"
  local jql
  local -a keys

  if [[ -z "$target_status" ]]; then
    echo 'Usage: jmsubtasks <story-issue|number|url> "<status>"' >&2
    return 1
  fi

  jql="parent = ${parent} AND assignee = currentUser()"
  _jira_search_keys "$jql" || return 1
  keys=("${reply[@]}")

  if (( ${#keys[@]} == 0 )); then
    echo "No sub-tasks assigned to you under ${parent}" >&2
    return 0
  fi

  _jira_transition_keys "$target_status" "${keys[@]}"
}

jtodo()   { jm "$@" "${JIRA_TODO_STATUS}"; }
jip()     { jm "$@" "In Progress"; }
jtest()   { jm "$@" "Testing"; }
jblock()  { jm "$@" "Block"; }
jreview() { jm "$@" "Review"; }
jir()     { jreview "$@"; }
jprod()   { jm "$@" "Wait to build PROD"; }
jdone()   { jm "$@" "DONE"; }

jforward() {
  local key="$(_jira_key "$1")" || return 1
  local current_status current_index next_status

  current_status="$(_jira_current_status "$key")" || return 1
  current_index="$(_jira_workflow_index "$current_status")" || {
    echo "Status '${current_status}' is not in workflow: ${JIRA_WORKFLOW_STATUSES[*]}" >&2
    return 1
  }

  if (( current_index >= ${#JIRA_WORKFLOW_STATUSES[@]} )); then
    echo "${key} is already at the last workflow status: ${current_status}" >&2
    return 1
  fi

  next_status="${JIRA_WORKFLOW_STATUSES[current_index + 1]}"
  jm "$key" "$next_status"
}

jbackward() {
  local key="$(_jira_key "$1")" || return 1
  local current_status current_index previous_status

  current_status="$(_jira_current_status "$key")" || return 1
  current_index="$(_jira_workflow_index "$current_status")" || {
    echo "Status '${current_status}' is not in workflow: ${JIRA_WORKFLOW_STATUSES[*]}" >&2
    return 1
  }

  if (( current_index <= 1 )); then
    echo "${key} is already at the first workflow status: ${current_status}" >&2
    return 1
  fi

  previous_status="${JIRA_WORKFLOW_STATUSES[current_index - 1]}"
  jm "$key" "$previous_status"
}

jdm() {
  local key="$(_jira_key "$1")" || return 1
  local file="$2"
  local target_status="$3"

  if [[ -z "$file" || -z "$target_status" ]]; then
    echo 'Usage: jdm <issue|number|url> <description-file> "<status>"' >&2
    return 1
  fi

  jd "$key" "$file" && jm "$key" "$target_status"
}

jcm() {
  local key="$(_jira_key "$1")" || return 1
  local target_status="$2"
  shift 2

  local comment="$*"
  if [[ -z "$target_status" || -z "$comment" ]]; then
    echo 'Usage: jcm <issue|number|url> "<status>" "<comment>"' >&2
    return 1
  fi

  jc "$key" "$comment" && jm "$key" "$target_status"
}

jdoneflow() {
  local key="$(_jira_key "$1")" || return 1
  local desc_file="$2"
  local target_status="$3"
  local comment_file="$4"

  if [[ -z "$desc_file" || -z "$target_status" ]]; then
    echo 'Usage: jdoneflow <issue|number|url> <description-file> "<status>" [comment-file]' >&2
    return 1
  fi

  jd "$key" "$desc_file" || return 1

  if [[ -n "$comment_file" ]]; then
    jcf "$key" "$comment_file" || return 1
  fi

  jm "$key" "$target_status"
}

jkey() {
  local branch
  branch="$(git branch --show-current 2>/dev/null)" || return 1

  if [[ "$branch" =~ (${JIRA_PROJECT}-[0-9]+) ]]; then
    echo "${match[1]}"
  else
    echo "No ${JIRA_PROJECT}-XXXX found in current branch: $branch" >&2
    return 1
  fi
}

jvb()       { jv "$(jkey)"; }
jforwardb() { jforward "$(jkey)"; }
jbackwardb() { jbackward "$(jkey)"; }
jtodob()    { jtodo "$(jkey)"; }
jib()       { jip "$(jkey)"; }
jtestb()    { jtest "$(jkey)"; }
jblockb()   { jblock "$(jkey)"; }
jreviewb()  { jreview "$(jkey)"; }
jirb()      { jir "$(jkey)"; }
jprodb()    { jprod "$(jkey)"; }
jdoneb()    { jdone "$(jkey)"; }
jdb()       { jd "$(jkey)" "$1"; }
jcb()       { jc "$(jkey)" "$*"; }

jalogin()  { acli jira auth login --web --site "$JIRA_SITE"; }
jalogout() { acli jira auth logout; }
jaswitch() { acli jira auth switch --site "$JIRA_SITE"; }
jastatus() { acli jira auth status; }

# ---------------------------------------------------------------------------
# Help
# ---------------------------------------------------------------------------

_jhelp_heading()  { printf '\n%s\n' "$1"; }
_jhelp_meta()     { printf '  %-8s %s\n' "$1" "$2"; }
_jhelp_cmd()      { printf '  %-52s %s\n' "$1" "$2"; }
_jhelp_cmd_wrap() { printf '  %s\n' "$1"; printf '  %-52s %s\n' "" "$2"; }

jhelp() {
  printf 'Jira helpers for %s\n' "$JIRA_PROJECT"
  _jhelp_meta "Site:" "$JIRA_SITE"
  _jhelp_meta "Inputs:" "[TICKET] accepts a bare issue number, ${JIRA_PROJECT}-1234, or a full Jira URL"

  _jhelp_heading "Open / inspect"
  _jhelp_cmd "jv [TICKET]" "View issue in terminal"
  _jhelp_cmd "jo [TICKET]" "Open issue in browser"
  _jhelp_cmd "ja [TICKET]" "Assign issue to me"

  _jhelp_heading "Move status"
  _jhelp_cmd "jm [TICKET]... \"[STATUS]\"" "Move one or many tickets to any status"
  _jhelp_cmd "jmove [TICKET]... \"[STATUS]\"" "Alias of jm"
  _jhelp_cmd "jmsubtasks [STORY] \"[STATUS]\"" "Move all my sub-tasks under a story"
  _jhelp_cmd "jtodo [TICKET]..." "Move one or many tickets to ${JIRA_TODO_STATUS}"
  _jhelp_cmd "jip [TICKET]..." "Move one or many tickets to In Progress"
  _jhelp_cmd "jtest [TICKET]..." "Move one or many tickets to Testing"
  _jhelp_cmd "jblock [TICKET]..." "Move one or many tickets to Block"
  _jhelp_cmd "jreview [TICKET]..." "Move one or many tickets to Review"
  _jhelp_cmd "jir [TICKET]" "Alias of jreview"
  _jhelp_cmd "jprod [TICKET]..." "Move one or many tickets to Wait to build PROD"
  _jhelp_cmd "jdone [TICKET]..." "Move one or many tickets to DONE"
  _jhelp_cmd "jforward [TICKET]" "Move to next workflow status"
  _jhelp_cmd "jbackward [TICKET]" "Move to previous workflow status"

  _jhelp_heading "Description / comments"
  _jhelp_cmd "jd [TICKET] [DESCRIPTION_FILE]" "Replace description from file"
  _jhelp_cmd "jdi [TICKET] \"[DESCRIPTION_TEXT]\"" "Replace description inline"
  _jhelp_cmd "jc [TICKET] \"[COMMENT]\"" "Add comment"
  _jhelp_cmd "jcf [TICKET] [COMMENT_FILE]" "Add comment from file"

  _jhelp_heading "Create / search"
  _jhelp_cmd "js [PARENT_TICKET] \"[SUMMARY]\"" "Create sub-task"
  _jhelp_cmd "jsd [PARENT_TICKET] \"[SUMMARY]\" [DESCRIPTION_FILE]" "Create sub-task with description file"
  _jhelp_cmd "jqw \"[JQL]\"" "Search issues with JQL"
  _jhelp_cmd "jmine [-d]" "All my current-sprint tickets; -d shows only not-done"
  _jhelp_cmd "jstories" "Stories for all my current-sprint tickets"
  _jhelp_cmd "jstoriesclear" "Clear local cache for jstories"

  _jhelp_heading "Combined flows"
  _jhelp_cmd "jdm [TICKET] [DESCRIPTION_FILE] \"[STATUS]\"" "Update description, then move status"
  _jhelp_cmd "jcm [TICKET] \"[STATUS]\" \"[COMMENT]\"" "Add comment, then move status"
  _jhelp_cmd_wrap "jdoneflow [TICKET] [DESCRIPTION_FILE] \"[STATUS]\" [COMMENT_FILE]" "Update description, optionally add a comment file, then move status"

  _jhelp_heading "Current branch"
  _jhelp_cmd "jkey" "Extract ${JIRA_PROJECT}-xxxx from current git branch"
  _jhelp_cmd "jvb" "View current branch issue"
  _jhelp_cmd "jforwardb" "Move current branch issue to next status"
  _jhelp_cmd "jbackwardb" "Move current branch issue to previous status"
  _jhelp_cmd "jtodob" "Move current branch issue to ${JIRA_TODO_STATUS}"
  _jhelp_cmd "jib" "Move current branch issue to In Progress"
  _jhelp_cmd "jtestb" "Move current branch issue to Testing"
  _jhelp_cmd "jblockb" "Move current branch issue to Block"
  _jhelp_cmd "jreviewb" "Move current branch issue to Review"
  _jhelp_cmd "jirb" "Alias of jreviewb"
  _jhelp_cmd "jprodb" "Move current branch issue to Wait to build PROD"
  _jhelp_cmd "jdoneb" "Move current branch issue to DONE"
  _jhelp_cmd "jdb [DESCRIPTION_FILE]" "Update description for current branch issue"
  _jhelp_cmd "jcb \"[COMMENT]\"" "Add comment to current branch issue"

  _jhelp_heading "Auth / raw CLI"
  _jhelp_cmd "jalogin" "Login to Jira in browser"
  _jhelp_cmd "jalogout" "Logout current Jira session"
  _jhelp_cmd "jaswitch" "Switch Jira auth to ${JIRA_SITE}"
  _jhelp_cmd "jastatus" "Show Jira auth status"
  _jhelp_cmd "jira <acli jira args...>" "Pass through to acli jira"
  _jhelp_cmd "jhelp" "Show this help"
}
