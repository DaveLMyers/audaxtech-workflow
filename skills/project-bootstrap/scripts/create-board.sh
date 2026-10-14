#!/usr/bin/env bash
# Creates a GitHub Projects v2 board with the standard columns, links it to a
# repo, creates the standard labels, and prints every id a project needs (in the shape .claude/workflow.json expects) for
# scripting it as a JSON `board` block on stdout (progress goes to stderr).
#
# Usage: create-board.sh <owner> <repo> <board-title> "<area1,area2,...>"
#
# Only call this AFTER the user has confirmed the board name/owner (see
# SKILL.md step 1) - it creates things on their GitHub account. Idempotent
# for labels (existing ones are kept); NOT idempotent for the board itself, so if it fails
# partway, check `gh project list --owner <owner>` for a half-made board
# before re-running rather than creating a duplicate.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OWNER="$1"; REPO="$2"; TITLE="$3"; AREAS="${4:-}"

command -v gh >/dev/null || { echo "gh CLI not found" >&2; exit 1; }
gh auth status 2>&1 | grep -q "'project'" || {
  echo "gh token lacks the 'project' scope - run: gh auth refresh -s project" >&2; exit 1; }

echo "Creating board '$TITLE' under $OWNER..." >&2
PROJ_JSON="$(gh project create --owner "$OWNER" --title "$TITLE" --format json)"
NUM="$(printf '%s' "$PROJ_JSON" | python -c 'import sys,json;print(json.load(sys.stdin)["number"])')"
PID="$(printf '%s' "$PROJ_JSON" | python -c 'import sys,json;print(json.load(sys.stdin)["id"])')"

gh project link "$NUM" --owner "$OWNER" --repo "$OWNER/$REPO" >&2

# A new board ships with a Status field (Todo / In Progress / Done). Replace
# its options with the five standard columns via the GraphQL update mutation
# (the gh CLI has no command for editing an existing field's options).
FIELDS="$(gh project field-list "$NUM" --owner "$OWNER" --format json)"
STATUS_ID="$(printf '%s' "$FIELDS" | python -c '
import sys,json
for f in json.load(sys.stdin)["fields"]:
    if f["name"]=="Status": print(f["id"])')"

gh api graphql -f query='
mutation($f:ID!){
  updateProjectV2Field(input:{fieldId:$f, singleSelectOptions:[
    {name:"Backlog",     color:GRAY,   description:"Captured, not yet refined"},
    {name:"Ready",       color:BLUE,   description:"Scoped enough to start now"},
    {name:"In Progress", color:YELLOW, description:"Actively being worked on"},
    {name:"In Review",   color:ORANGE, description:"PR open, awaiting review/merge"},
    {name:"Done",        color:GREEN,  description:"Merged to main"}
  ]}){ projectV2Field{ ... on ProjectV2SingleSelectField{ id } } }
}' -f f="$STATUS_ID" >&2; echo >&2

# Priority field.
gh project field-create "$NUM" --owner "$OWNER" --name "Priority" \
  --data-type SINGLE_SELECT --single-select-options "P1,P2,P3" >&2

# Labels: type:*, priority:*, area:*. Existing labels are left untouched (no
# --force) so bootstrapping into a repo that already has some never clobbers
# their colors/descriptions; "already exists" is expected, not an error.
mk() { gh label create "$1" --repo "$OWNER/$REPO" --color "$2" --description "$3" >&2 2>/dev/null || echo "label $1 already exists, kept" >&2; }
mk type:feature  1d76db "New functionality"
mk type:bug      d73a4a "Something is broken"
mk type:chore    cfd3d7 "Tooling, cleanup, non-feature work"
mk type:docs     0075ca "Documentation only"
mk type:research 5319e7 "Investigation or spike; the output is knowledge, not a feature"
mk priority:p1   b60205 "Now"
mk priority:p2   fbca04 "Soon"
mk priority:p3   c2e0c6 "Later"
IFS=',' read -ra AREA_ARR <<< "$AREAS"
for a in "${AREA_ARR[@]}"; do
  a="$(echo "$a" | xargs)"; [ -n "$a" ] && mk "area:$a" 5319e7 "System area: $a"
done

# Re-read fields (option ids only exist after the update above) and print the
# `board` block for .claude/workflow.json: keyed by role, in the shape that the
# work-issue skill's board_status.py reads. Merge it into workflow.json as "board".
gh project field-list "$NUM" --owner "$OWNER" --format json | python "$SCRIPT_DIR/board_json.py" "$OWNER" "$NUM" "$PID"
