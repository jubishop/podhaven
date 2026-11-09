#!/bin/bash
# Shared scaffolding for bin/check-sentry-feedback and bin/check-sentry-issues.
# A checker sets LABEL, COMMENT_MARKER, ANALYSIS_SKILL, TRIAGE_COMMAND, and
# SENTRY_DETAILS, then calls intake_start before matching its Sentry items.

# shellcheck source=.agents/scripts/sentry-cli/lib.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/.agents/scripts/sentry-cli/lib.sh"

GH_REPO="${GH_REPO:-jubishop/podhaven}"
DRY_RUN="${DRY_RUN:-false}"
TRACKED=0
COMMENTS_ADDED=0

# intake_start <sentry-query> <item-kind> <plural-item-kind>
# Writes the complete Sentry list to SENTRY_JSON and every GitHub issue, without
# pull requests, to ISSUES_JSON.
intake_start() {
  local query="$1" kind="$2" plural="$3"

  case "$DRY_RUN" in
    true | false) ;;
    *)
      echo "Error: DRY_RUN must be true or false" >&2
      exit 1
      ;;
  esac

  for command_name in gh jq; do
    if ! command -v "$command_name" >/dev/null 2>&1; then
      echo "Error: required command not found: $command_name" >&2
      exit 1
    fi
  done

  require_sentry_auth

  WORK_DIR="$(mktemp -d "${RUNNER_TEMP:-/tmp}/podhaven-$LABEL.XXXXXX")"
  trap 'rm -rf "$WORK_DIR"' EXIT
  SENTRY_JSON="$WORK_DIR/sentry.json"
  ISSUES_JSON="$WORK_DIR/issues.json"

  sentry_cmd issue list "$SENTRY_TARGET" \
    --query "$query" \
    --period 365d \
    --limit 1000 \
    --sort new \
    --fresh \
    --json \
    --fields id,shortId,permalink \
    > "$SENTRY_JSON"

  if ! jq -e '
    .data | type == "array" and all(.[];
      (.id | type == "string" and test("^[0-9]+$"))
      and (.shortId | type == "string" and test("^[A-Z0-9-]+$"))
      and (.permalink | type == "string" and test("^https://[^/]+\\.sentry\\.io/"))
    )
  ' "$SENTRY_JSON" >/dev/null; then
    echo "Error: Sentry returned an unexpected $kind response" >&2
    exit 1
  fi
  if [[ "$(jq '.hasMore // false' "$SENTRY_JSON")" != false ]]; then
    echo "Error: Sentry has more than 1000 unresolved $plural; refusing to check a partial list" >&2
    exit 1
  fi

  gh api --paginate --slurp \
    "repos/$GH_REPO/issues?state=all&per_page=100" \
    > "$WORK_DIR/all-issues.json"
  jq '[.[][] | select(has("pull_request") | not) | {number, state, body, labels: [.labels[]?.name]}]' \
    "$WORK_DIR/all-issues.json" \
    > "$ISSUES_JSON"

  # shellcheck disable=SC2034
  TOTAL="$(jq '.data | length' "$SENTRY_JSON")"
}

intake_items() {
  jq -c '.data | sort_by(.id | tonumber)[]' "$SENTRY_JSON"
}

# intake_comment <issue-reference> <triage-argument> <link-text> <permalink>
intake_comment() {
  local issue_reference="$1" argument="$2" link_text="$3" permalink="$4"
  local comment_path="$WORK_DIR/comment.md"

  {
    printf '<!-- %s:%s -->\n' "$COMMENT_MARKER" "$argument"
    printf '<!-- fix-issue-prerequisite: %s %s -->\n' "$ANALYSIS_SKILL" "$argument"
    printf 'This issue is intake only and must be analyzed before implementation.\n\n'
    printf -- "- Run \`%s %s\` from a PodHaven checkout to analyze it directly.\n" "$TRIAGE_COMMAND" "$argument"
    printf -- "- If passed to \`fix-issue\`, it will run the same analysis prerequisite, refresh this issue, and then continue from the findings.\n\n"
    printf '%s remain in Sentry: [%s](%s).\n' "$SENTRY_DETAILS" "$link_text" "$permalink"
  } > "$comment_path"

  if [[ "$DRY_RUN" == "true" ]]; then
    echo "Would add agent instructions to $issue_reference"
    return
  fi

  gh issue comment "$issue_reference" \
    --repo "$GH_REPO" \
    --body-file "$comment_path" \
    >/dev/null
  COMMENTS_ADDED=$((COMMENTS_ADDED + 1))
}

# intake_track <match-json> <triage-argument> <link-text> <permalink>
# The match is an ISSUES_JSON entry with an added boolean `analyzed`.
intake_track() {
  local match="$1" argument="$2" link_text="$3" permalink="$4"
  local number comments_path

  TRACKED=$((TRACKED + 1))
  number="$(jq -r '.number' <<< "$match")"
  if ! jq -e --arg label "$LABEL" 'any(.labels[]; . == $label)' <<< "$match" >/dev/null; then
    if [[ "$DRY_RUN" == "true" ]]; then
      echo "Would add the $LABEL label to issue #$number"
    else
      gh issue edit "$number" --repo "$GH_REPO" --add-label "$LABEL" >/dev/null
    fi
  fi
  if jq -e '.analyzed' <<< "$match" >/dev/null; then
    echo "Already analyzed: $link_text in issue #$number"
    return
  fi

  comments_path="$WORK_DIR/comments-$number.json"
  gh api --paginate --slurp \
    "repos/$GH_REPO/issues/$number/comments?per_page=100" \
    > "$comments_path"
  if ! jq -e --arg marker "<!-- $COMMENT_MARKER:$argument -->" \
    'any(.[][]; (.body // "") | contains($marker))' \
    "$comments_path" >/dev/null; then
    intake_comment "$number" "$argument" "$link_text" "$permalink"
  fi
  echo "Already tracked: $link_text in issue #$number"
}

# intake_create <counter-variable> <title> <dry-run-note> <body-path> <triage-argument> <link-text> <permalink>
intake_create() {
  local counter="$1" title="$2" note="$3" body_path="$4" argument="$5" link_text="$6" permalink="$7"
  local issue_url

  if [[ "$DRY_RUN" == "true" ]]; then
    echo "Would create issue: $title$note"
    intake_comment "the new issue for $link_text" "$argument" "$link_text" "$permalink"
    return
  fi

  issue_url="$(gh issue create \
    --repo "$GH_REPO" \
    --title "$title" \
    --label "$LABEL" \
    --body-file "$body_path")"
  printf -v "$counter" '%s' "$((${!counter} + 1))"
  intake_comment "$issue_url" "$argument" "$link_text" "$permalink"
  echo "Created: $issue_url"
}

# intake_finish <step-summary-heading> <summary>
intake_finish() {
  echo "$2"
  if [[ -n "${GITHUB_STEP_SUMMARY:-}" ]]; then
    {
      echo "## $1"
      echo ""
      echo "$2"
    } >> "$GITHUB_STEP_SUMMARY"
  fi
}
