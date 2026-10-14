#!/usr/bin/env bash
# Tests for project-bootstrap's upgrade check (scripts/upgrade_check.py): given
# an existing repo, it must report exactly which pieces of the standard process
# are missing, and must never modify anything. Self-contained: builds throwaway
# repos in a temp dir.
#
# Usage: bash tests/run-bootstrap-tests.sh      (exit 0 = all passed)
set -u

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CHECK="$HERE/../skills/project-bootstrap/scripts/upgrade_check.py"
W="$(mktemp -d)"; trap 'rm -rf "$W"' EXIT
PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); echo "ok    $1"; }
bad() { FAIL=$((FAIL+1)); echo "FAIL  $1  (${2:0:300})"; }
chk() { [ "$2" -eq 0 ] && ok "$1" || bad "$1" "$3"; }

# missing_paths <repo> [extra args] -> sorted "path|type" lines of what is missing
missing() {
  python "$CHECK" "$@" --json | python -c '
import sys, json
r = json.load(sys.stdin)
for m in sorted(r["missing"], key=lambda m: (m["path"], m["type"])):
    print(m["path"] + "|" + m["type"])' | tr -d '\015'
}
# put a file in place, creating folders
put() { mkdir -p "$(dirname "$1")"; printf '%s\n' "${2:-x}" > "$1"; }
# a repo with every piece the standard process gives a game
full_game() {
  local d="$1"; mkdir -p "$d"
  put "$d/CONTRIBUTING.md" "# C
## Game-specific process"
  put "$d/CLAUDE.md" "- stray ideas go in docs/design-ideas.md"
  for f in DECISIONS VISION DESIGN GAMEPLAY HOW_TO_PLAY design-ideas; do put "$d/docs/$f.md"; done
  put "$d/.github/PULL_REQUEST_TEMPLATE.md"
  for f in feature bug_report chore research; do put "$d/.github/ISSUE_TEMPLATE/$f.yml"; done
  put "$d/.github/workflows/ci.yml"
  put "$d/.claude/workflow.json" '{"version":1,"kind":"game"}'
}
snapshot() { (cd "$1" && find . -type f -print0 | sort -z | xargs -0 sha1sum | sha1sum | cut -d' ' -f1); }

echo "== the older layout from issue #3 (docs/ with only DECISIONS, DESIGN, GAMEPLAY, HOW_TO_PLAY)"
OLD="$W/old"; full_game "$OLD"
rm "$OLD/docs/VISION.md" "$OLD/docs/design-ideas.md"
put "$OLD/CONTRIBUTING.md" "# C
## Branching"
put "$OLD/CLAUDE.md" "- be careful"
got="$(missing "$OLD")"
exp="CLAUDE.md|line
CONTRIBUTING.md|section
docs/VISION.md|file
docs/design-ideas.md|file"
[ "$got" = "$exp" ]; chk "reports exactly the missing doc files, the CONTRIBUTING section and the CLAUDE.md pointer" $? "$got"
before="$(snapshot "$OLD")"; python "$CHECK" "$OLD" >/dev/null; python "$CHECK" "$OLD" --json >/dev/null
[ "$before" = "$(snapshot "$OLD")" ]; chk "never modifies the repo" $? "snapshot changed"
python "$CHECK" "$OLD" | grep -q "Already present"; chk "text report says what is left untouched" $? ""

echo "== a complete repo"
FULL="$W/full"; full_game "$FULL"
[ -z "$(missing "$FULL")" ]; chk "a repo with every piece reports nothing missing" $? "$(missing "$FULL")"
python "$CHECK" "$FULL" | grep -q "Nothing missing"; chk "and says so in words" $? ""

echo "== an empty repo"
EMPTY="$W/empty"; mkdir -p "$EMPTY"
got="$(missing "$EMPTY" | wc -l | tr -d ' ')"
[ "$got" -ge 12 ]; chk "an empty game repo is missing the whole process (>= 12 pieces)" $? "$got"
python "$CHECK" "$EMPTY" | grep -q "assumed"; chk "kind is flagged as assumed when nothing says" $? ""
python "$CHECK" "$EMPTY" --kind tool --json | python -c 'import sys,json;r=json.load(sys.stdin);sys.exit(0 if r["kind"]=="tool" and r["kind_source"] == "--kind" else 1)'
chk "--kind is honoured and reported" $? ""

echo "== kinds and components"
TOOL="$W/tool"; full_game "$TOOL"
python -c '
import json,sys; p=sys.argv[1]+"/.claude/workflow.json"
json.dump({"version":1,"kind":"tool","components":{"game_docs":False}}, open(p,"w"))' "$TOOL"
rm -rf "$TOOL/docs/VISION.md" "$TOOL/docs/DESIGN.md" "$TOOL/docs/GAMEPLAY.md" "$TOOL/docs/HOW_TO_PLAY.md" "$TOOL/docs/design-ideas.md"
put "$TOOL/CONTRIBUTING.md" "# C"; put "$TOOL/CLAUDE.md" "- x"
[ -z "$(missing "$TOOL")" ]; chk "a tool repo is not asked for game docs, the game section or the ideas pointer" $? "$(missing "$TOOL")"
TK="$W/tk"; full_game "$TK"
python -c '
import json,sys; p=sys.argv[1]+"/.claude/workflow.json"
json.dump({"version":1,"kind":"tool"}, open(p,"w"))' "$TK"
rm -rf "$TK/docs"; put "$TK/docs/DECISIONS.md"; put "$TK/CONTRIBUTING.md" "# C"; put "$TK/CLAUDE.md" "- x"
[ -z "$(missing "$TK")" ]; chk "kind alone keeps game docs out of a tool repo (no component override needed)" $? "$(missing "$TK")"
G="$W/gd"; full_game "$G"
python -c '
import json,sys; p=sys.argv[1]+"/.claude/workflow.json"
json.dump({"version":1,"kind":"game","components":{"game_docs":False,"ci":False,"decisions_log":False,"issue_and_pr_templates":False}}, open(p,"w"))' "$G"
rm -rf "$G/docs" "$G/.github"; put "$G/CONTRIBUTING.md" "# C"; put "$G/CLAUDE.md" "- x"
[ -z "$(missing "$G")" ]; chk "components switched off in workflow.json are not reported" $? "$(missing "$G")"

echo "== things that must not trip it"
CR="$W/crlf"; full_game "$CR"
printf '# C\r\n## Game-specific process\r\n' > "$CR/CONTRIBUTING.md"
[ -z "$(missing "$CR")" ]; chk "CRLF files are read correctly" $? "$(missing "$CR")"
BAD="$W/bad"; full_game "$BAD"; printf '{ not json' > "$BAD/.claude/workflow.json"
python "$CHECK" "$BAD" | grep -q "cannot be read"; chk "a malformed workflow.json is reported, not a crash" $? ""
python "$CHECK" "$BAD" --json | python -c 'import sys,json;r=json.load(sys.stdin);sys.exit(0 if any(m["path"]==".claude/workflow.json" for m in r["missing"]) is False else 1)'
chk "...and the broken marker is not double-reported as missing" $? ""
python "$CHECK" "$W/does-not-exist" >/dev/null 2>&1; [ $? -eq 2 ]; chk "a missing directory is a usage error (exit 2)" $? ""
IDEAS="$W/ideas"; full_game "$IDEAS"; put "$IDEAS/CLAUDE.md" "- stray ideas go in docs/design-ideas.md, in the owner's words"
[ -z "$(missing "$IDEAS")" ]; chk "the CLAUDE.md pointer is recognised wherever the line sits" $? "$(missing "$IDEAS")"

echo; echo "passed: $PASS   failed: $FAIL"
[ "$FAIL" -eq 0 ]
