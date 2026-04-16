#!/bin/zsh
set -euo pipefail

export PATH="/opt/homebrew/bin:/opt/homebrew/sbin:/usr/local/bin:/usr/local/sbin:/usr/bin:/bin:/usr/sbin:/sbin:${PATH:-}"
source ~/.zshrc 2>/dev/null || true
export PATH="/opt/homebrew/bin:/opt/homebrew/sbin:/usr/local/bin:/usr/local/sbin:/usr/bin:/bin:/usr/sbin:/sbin:${PATH:-}"

site=""
account_email=""
board_name=""
acli_bin="$(command -v acli 2>/dev/null || true)"
jq_bin="$(command -v jq 2>/dev/null || true)"

if [[ -z "$acli_bin" && -x "/opt/homebrew/bin/acli" ]]; then
  acli_bin="/opt/homebrew/bin/acli"
fi

if [[ -z "$acli_bin" && -x "/usr/local/bin/acli" ]]; then
  acli_bin="/usr/local/bin/acli"
fi

if [[ -z "$jq_bin" && -x "/opt/homebrew/bin/jq" ]]; then
  jq_bin="/opt/homebrew/bin/jq"
fi

if [[ -z "$jq_bin" && -x "/usr/local/bin/jq" ]]; then
  jq_bin="/usr/local/bin/jq"
fi

if [[ -z "$acli_bin" ]]; then
  if [[ -n "$jq_bin" ]]; then
    "$jq_bin" -n \
      --arg boardName "" \
      --arg accountEmail "" \
      --arg site "$site" \
      --arg fetchedAt "$(date -u +"%Y-%m-%dT%H:%M:%SZ")" \
      '{
        boardName: ($boardName | if length > 0 then . else null end),
        accountEmail: ($accountEmail | if length > 0 then . else null end),
        site: $site,
        auth: {
          authorized: false,
          description: "acli was not found in PATH."
        },
        stories: [],
        tickets: [],
        errorMessage: "Install Atlassian CLI before using JiraBar.",
        fetchedAt: $fetchedAt
      }'
  else
    printf '{"boardName":null,"accountEmail":null,"site":"%s","auth":{"authorized":false,"description":"acli was not found in PATH."},"stories":[],"tickets":[],"errorMessage":"Install Atlassian CLI before using JiraBar.","fetchedAt":"%s"}\n' \
      "$site" \
      "$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
  fi
  exit 0
fi

if [[ -z "$jq_bin" ]]; then
  printf '{"boardName":null,"accountEmail":null,"site":"%s","auth":{"authorized":false,"description":"jq was not found in PATH."},"stories":[],"tickets":[],"errorMessage":"Install jq before using JiraBar.","fetchedAt":"%s"}\n' \
    "$site" \
    "$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
  exit 0
fi

normalize_search_json() {
  "$jq_bin" -c '
    def items:
      if type == "array" then .
      elif .issues? then .issues
      elif .data?.issues? then .data.issues
      elif .items? then .items
      elif .data?.items? then .data.items
      elif .results? then .results
      elif .data?.results? then .data.results
      elif .key? then [.]
      else []
      end;

    items
    | map({
        issueType: (
          .fields.issuetype.name
          // .fields.issueType.name
          // .issuetype.name
          // .issueType.name
          // .fields.issuetype
          // .fields.issueType
          // .issuetype
          // .issueType
          // ""
        ),
        key: (.key // ""),
        status: (
          .fields.status.name
          // .status.name
          // .fields.status
          // .status
          // ""
        ),
        summary: (.fields.summary // .summary // "")
      })
    | map(select(.key | type == "string" and test("^[A-Z][A-Z0-9_]*-[0-9]+$")))
  '
}

extract_parent_key() {
  "$jq_bin" -r '
    [
      .fields.parent.key?,
      .parent.key?,
      .issue.fields.parent.key?,
      .data.fields.parent.key?
    ]
    | map(select(type == "string" and test("^[A-Z][A-Z0-9_]*-[0-9]+$")))
    | .[0] // ""
  '
}

extract_issue_type() {
  "$jq_bin" -r '
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
    | .[0] // ""
  '
}

auth_output="$("$acli_bin" jira auth status 2>&1)" || true
auth_description="$(printf '%s' "$auth_output" | tr '\n' ' ' | sed 's/[[:space:]]\+/ /g' | sed 's/^ //; s/ $//')"
site="$(printf '%s' "$auth_output" | grep -Eo '[A-Za-z0-9.-]+\.atlassian\.net' | head -n 1 || true)"
account_email="$(printf '%s' "$auth_output" | grep -Eo '[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}' | head -n 1 || true)"

if [[ "$auth_output" == *"unauthorized"* || "$auth_output" == *"not logged in"* ]]; then
  "$jq_bin" -n \
    --arg boardName "$board_name" \
    --arg accountEmail "$account_email" \
    --arg site "$site" \
    --arg description "${auth_description:-Not authenticated.}" \
    --arg fetchedAt "$(date -u +"%Y-%m-%dT%H:%M:%SZ")" \
    '{
      boardName: ($boardName | if length > 0 then . else null end),
      accountEmail: ($accountEmail | if length > 0 then . else null end),
      site: $site,
      auth: {
        authorized: false,
        description: $description
      },
      stories: [],
      tickets: [],
      errorMessage: null,
      fetchedAt: $fetchedAt
    }'
  exit 0
fi

board_raw="$("$acli_bin" jira board search --json --limit 50 2>/dev/null || printf '[]')"
board_context="$(printf '%s' "$board_raw" | "$jq_bin" -c '
  def items:
    if type == "array" then .
    elif .values? then .values
    elif .boards? then .boards
    elif .data?.boards? then .data.boards
    elif .results? then .results
    elif .data?.results? then .data.results
    elif .id? then [.]
    else []
    end;

  items
  | map(
      if type == "string" then
        { name: . }
      elif type == "object" then
        {
          name: (
            .name
            // .board.name
            // .location.name
            // ""
          )
        }
      else
        {}
      end
    )
  | map(select(.name | type == "string" and length > 0))
  | .[0] // {}
')"
board_name="$(printf '%s' "$board_context" | "$jq_bin" -r '.name // ""')"

tickets_jql="assignee = currentUser() AND sprint in openSprints() AND statusCategory != Done ORDER BY Rank ASC"
stories_child_jql="assignee = currentUser() AND sprint in openSprints() ORDER BY Rank ASC"

tickets_raw="$("$acli_bin" jira workitem search --jql "$tickets_jql" --fields "issuetype,key,status,summary" --paginate --json 2>/dev/null || printf '[]')"
tickets_json="$(printf '%s' "$tickets_raw" | normalize_search_json)"

stories_child_raw="$("$acli_bin" jira workitem search --jql "$stories_child_jql" --fields "key" --paginate --json 2>/dev/null || printf '[]')"
stories_child_keys=("${(@f)$(printf '%s' "$stories_child_raw" | "$jq_bin" -r '
  def items:
    if type == "array" then .
    elif .issues? then .issues
    elif .data?.issues? then .data.issues
    elif .items? then .items
    elif .data?.items? then .data.items
    elif .results? then .results
    elif .data?.results? then .data.results
    elif .key? then [.]
    else []
    end;

  items
  | map(.key // "")
  | map(select(type == "string" and test("^[A-Z][A-Z0-9_]*-[0-9]+$")))
  | .[]
')}")

typeset -a parent_keys
typeset -A seen_parents

for key in "${stories_child_keys[@]}"; do
  [[ -z "$key" ]] && continue
  child_raw="$("$acli_bin" jira workitem view "$key" --fields "parent,issuetype" --json 2>/dev/null || printf '{}')"
  parent_key="$(printf '%s' "$child_raw" | extract_parent_key)"
  issue_type="$(printf '%s' "$child_raw" | extract_issue_type)"

  if [[ -z "$parent_key" && "$issue_type" == "Story" ]]; then
    parent_key="$key"
  fi

  [[ -z "$parent_key" ]] && continue
  if [[ -z "${seen_parents[$parent_key]-}" ]]; then
    parent_keys+=("$parent_key")
    seen_parents[$parent_key]=1
  fi
done

if (( ${#parent_keys[@]} > 0 )); then
  joined_parent_keys="${(j:,:)parent_keys}"
  stories_raw="$("$acli_bin" jira workitem search --jql "key in (${joined_parent_keys}) ORDER BY key" --fields "issuetype,key,status,summary" --paginate --json 2>/dev/null || printf '[]')"
  stories_json="$(printf '%s' "$stories_raw" | normalize_search_json)"
else
  stories_json='[]'
fi

"$jq_bin" -n \
  --arg boardName "$board_name" \
  --arg accountEmail "$account_email" \
  --arg site "$site" \
  --arg description "${auth_description:-Authenticated.}" \
  --arg fetchedAt "$(date -u +"%Y-%m-%dT%H:%M:%SZ")" \
  --argjson tickets "$tickets_json" \
  --argjson stories "$stories_json" \
  '{
    boardName: ($boardName | if length > 0 then . else null end),
    accountEmail: ($accountEmail | if length > 0 then . else null end),
    site: $site,
    auth: {
      authorized: true,
      description: $description
    },
    stories: $stories,
    tickets: $tickets,
    errorMessage: null,
    fetchedAt: $fetchedAt
  }'
