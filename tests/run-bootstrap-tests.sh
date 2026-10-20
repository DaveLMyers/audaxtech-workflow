#!/usr/bin/env bash
# Tests for project-bootstrap's upgrade check (scripts/upgrade_check.py): given
# an existing repo, it must report exactly which pieces of the standard process
# are missing, and must never modify anything. Self-contained: builds throwaway
# repos in a temp dir.
#
# Usage: bash tests/run-bootstrap-tests.sh      (exit 0 = all passed)
set -u

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$HERE/_safe_rm.sh"
CHECK="$HERE/../skills/project-bootstrap/scripts/upgrade_check.py"
W="$(mktemp -d)"; safe_rm_allow "$W"; trap 'safe_rm -r "$W"' EXIT
PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); echo "ok    $1"; }
bad() { FAIL=$((FAIL+1)); echo "FAIL  $1  (${2:0:300})"; }
chk() { [ "$2" -eq 0 ] && ok "$1" || bad "$1" "$3"; }

# missing_paths <repo> [extra args] -> sorted "path|type" lines of what is missing
missing() {
  local out rc
  out="$(python "$CHECK" "$@" --json)"; rc=$?
  # a crash prints a marker that no expected list equals, instead of an empty list that passes -z checks
  [ $rc -eq 0 ] || { echo "CRASH(rc=$rc)"; return 1; }
  printf '%s' "$out" | python -c '
import sys, json
r = json.load(sys.stdin)
for m in sorted(r["missing"], key=lambda m: (m["path"], m["type"])):
    print(m["path"] + "|" + m["type"])' | tr -d '\015'
}
# put a file in place, creating folders
put() { mkdir -p "$(dirname "$1")"; printf '%s\n' "${2:-x}" > "$1"; }
# the Game-specific process section with every subsection of the template
GSP="## Game-specific process
### Game docs
### Play-testing
### Engine conventions"
# a repo with every piece the standard process gives a game
full_game() {
  local d="$1"; mkdir -p "$d"
  put "$d/CONTRIBUTING.md" "# C
$GSP"
  put "$d/CLAUDE.md" "- stray ideas go in docs/design-ideas.md"
  for f in DECISIONS VISION DESIGN GAMEPLAY HOW_TO_PLAY design-ideas; do put "$d/docs/$f.md"; done
  put "$d/.github/PULL_REQUEST_TEMPLATE.md"
  for f in feature bug_report chore research; do put "$d/.github/ISSUE_TEMPLATE/$f.yml"; done
  put "$d/.github/workflows/ci.yml"
  put "$d/.gitattributes"; put "$d/.editorconfig"
  put "$d/.claude/workflow.json" '{"version":1,"kind":"game"}'
}
# a hash of every file name and content under a folder (portable: no sha1sum or sort -z)
snapshot() { python -c '
import hashlib, os, sys
h = hashlib.sha1()
for root, dirs, files in os.walk(sys.argv[1]):
    dirs.sort()
    for f in sorted(files):
        p = os.path.join(root, f)
        h.update(p.encode()); h.update(open(p, "rb").read())
print(h.hexdigest())' "$1"; }

echo "== the older layout from issue #3 (docs/ with only DECISIONS, DESIGN, GAMEPLAY, HOW_TO_PLAY)"
OLD="$W/old"; full_game "$OLD"
safe_rm "$OLD/docs/VISION.md" "$OLD/docs/design-ideas.md"
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
safe_rm -r "$TOOL/docs/VISION.md" "$TOOL/docs/DESIGN.md" "$TOOL/docs/GAMEPLAY.md" "$TOOL/docs/HOW_TO_PLAY.md" "$TOOL/docs/design-ideas.md"
put "$TOOL/CONTRIBUTING.md" "# C"; put "$TOOL/CLAUDE.md" "- x"
[ -z "$(missing "$TOOL")" ]; chk "a tool repo is not asked for game docs, the game section or the ideas pointer" $? "$(missing "$TOOL")"
TK="$W/tk"; full_game "$TK"
python -c '
import json,sys; p=sys.argv[1]+"/.claude/workflow.json"
json.dump({"version":1,"kind":"tool"}, open(p,"w"))' "$TK"
safe_rm -r "$TK/docs"; put "$TK/docs/DECISIONS.md"; put "$TK/CONTRIBUTING.md" "# C"; put "$TK/CLAUDE.md" "- x"
[ -z "$(missing "$TK")" ]; chk "kind alone keeps game docs out of a tool repo (no component override needed)" $? "$(missing "$TK")"
G="$W/gd"; full_game "$G"
python -c '
import json,sys; p=sys.argv[1]+"/.claude/workflow.json"
json.dump({"version":1,"kind":"game","components":{"game_docs":False,"ci":False,"decisions_log":False,"issue_and_pr_templates":False}}, open(p,"w"))' "$G"
safe_rm -r "$G/docs" "$G/.github"; put "$G/CONTRIBUTING.md" "# C"; put "$G/CLAUDE.md" "- x"
[ -z "$(missing "$G")" ]; chk "components switched off in workflow.json are not reported" $? "$(missing "$G")"

echo "== exact lists (what a wrong required-file list or kind order would change)"
ALL_FILES=".claude/workflow.json
.editorconfig
.gitattributes
.github/ISSUE_TEMPLATE/bug_report.yml
.github/ISSUE_TEMPLATE/chore.yml
.github/ISSUE_TEMPLATE/feature.yml
.github/ISSUE_TEMPLATE/research.yml
.github/PULL_REQUEST_TEMPLATE.md
.github/workflows/ci.yml
CLAUDE.md
CONTRIBUTING.md
docs/DECISIONS.md"
GAME_FILES="docs/DESIGN.md
docs/GAMEPLAY.md
docs/HOW_TO_PLAY.md
docs/VISION.md
docs/design-ideas.md"
files_only() { missing "$@" | sed 's/|file$//' | sort; }
sorted() { printf '%s
' "$1" | sort; }
[ "$(files_only "$EMPTY")" = "$(sorted "$ALL_FILES
$GAME_FILES")" ]; chk "an empty game repo is missing exactly the 17 files, with no section or line" $? "$(missing "$EMPTY")"
[ -z "$(missing "$EMPTY" | grep -v '|file$')" ]; chk "...and nothing of type section or line while their files are absent" $? ""
for k in web library other tool; do
  [ "$(files_only "$EMPTY" --kind $k)" = "$(sorted "$ALL_FILES")" ]; chk "kind $k: exactly the 12 standard files, no game docs" $? "$(missing "$EMPTY" --kind $k | tr '
' ' ')"
done
M="$W/m"; full_game "$M"; safe_rm "$M/docs/VISION.md"
[ "$(missing "$M" --kind tool)" = "docs/VISION.md|file" ]; chk "workflow.json's kind beats --kind" $? "$(missing "$M" --kind tool)"
python "$CHECK" "$M" --kind tool --json | python -c 'import sys,json;r=json.load(sys.stdin);sys.exit(0 if r["kind"]=="game" and r["kind_source"]=="workflow.json" else 1)'
chk "...and the report says the kind came from workflow.json" $? ""
for bad in '{ not json' '[]' '"game"' 'null' ''; do
  B2="$W/b2"; safe_rm -r "$B2"; full_game "$B2"; printf '%s' "$bad" > "$B2/.claude/workflow.json"; safe_rm "$B2/docs/VISION.md" "$B2/.github/workflows/ci.yml"
  [ "$(missing "$B2" | sort)" = "$(printf '.github/workflows/ci.yml|file
docs/VISION.md|file')" ]; chk "marker '${bad:-<empty>}': noted, treated as absent, and the rest still reported" $? "$(missing "$B2" | tr '
' ' ')"
done
BOM="$W/bom"; full_game "$BOM"; python -c 'import sys;open(sys.argv[1]+"/.claude/workflow.json","wb").write(bytes([239,187,191])+b"{\"version\":1,\"kind\":\"tool\"}")' "$BOM"; safe_rm "$BOM/docs/VISION.md"
[ -z "$(missing "$BOM")" ]; chk "a UTF-8 BOM in workflow.json is read (tool kind: VISION not asked for)" $? "$(missing "$BOM")"
python "$CHECK" "$FULL/CONTRIBUTING.md" >/dev/null 2>&1; [ $? -eq 2 ]; chk "a file given instead of a folder is a usage error" $? ""
# each component switches off only its own pieces
comp() { # component, files it owns, a file another component owns
  local C="$W/c_$1"; safe_rm -r "$C"; full_game "$C"
  python -c '
import json,sys; json.dump({"version":1,"kind":"game","components":{sys.argv[2]:False}}, open(sys.argv[1]+"/.claude/workflow.json","w"))' "$C" "$1"
  # remove inside the throwaway repo only: a failed cd must not fall through to deleting here
  cd "$C" || return 1; safe_rm -r $2 "$3"; cd "$W" || return 1
  [ "$(missing "$C")" = "$4" ]; chk "component $1 off: only its own pieces are excused" $? "$(missing "$C" | tr '
' ' ')"
}
comp ci ".github/workflows" "docs/DECISIONS.md" "docs/DECISIONS.md|file"
comp decisions_log "docs/DECISIONS.md" ".github/workflows/ci.yml" ".github/workflows/ci.yml|file"
comp issue_and_pr_templates ".github/ISSUE_TEMPLATE .github/PULL_REQUEST_TEMPLATE.md" "docs/DECISIONS.md" "docs/DECISIONS.md|file"
comp game_docs "docs/VISION.md docs/DESIGN.md docs/GAMEPLAY.md docs/HOW_TO_PLAY.md docs/design-ideas.md" ".github/workflows/ci.yml" ".github/workflows/ci.yml|file"

echo "== what counts as present"
H3="$W/h3"; full_game "$H3"; put "$H3/CONTRIBUTING.md" "# C
### Game-specific process"
[ "$(missing "$H3")" = "CONTRIBUTING.md|section" ]; chk "a ### subsection is not the Game-specific process section" $? "$(missing "$H3")"
FENCE="$W/hs"; full_game "$FENCE"; put "$FENCE/CONTRIBUTING.md" "# C
see the Game-specific process section"
[ "$(missing "$FENCE")" = "CONTRIBUTING.md|section" ]; chk "the phrase in prose is not the section" $? "$(missing "$FENCE")"
OC="$W/oc"; full_game "$OC"; safe_rm "$OC/.github/workflows/ci.yml"; put "$OC/.github/workflows/test.yaml"
[ -z "$(missing "$OC")" ]; chk "CI under another file name counts as CI" $? "$(missing "$OC")"
NC="$W/nc"; full_game "$NC"; safe_rm "$NC/.github/workflows/ci.yml"; put "$NC/.github/workflows/notes.txt"
[ "$(missing "$NC")" = ".github/workflows/ci.yml|file" ]; chk "a workflows folder with no workflow file is still missing CI" $? "$(missing "$NC")"

echo "== things that must not trip it"
CR="$W/crlf"; full_game "$CR"
printf '# C\r\n## Game-specific process\r\n### Game docs\r\n### Play-testing\r\n### Engine conventions\r\n' > "$CR/CONTRIBUTING.md"
[ -z "$(missing "$CR")" ]; chk "CRLF files are read correctly" $? "$(missing "$CR")"
BAD="$W/bad"; full_game "$BAD"; printf '{ not json' > "$BAD/.claude/workflow.json"
python "$CHECK" "$BAD" | grep -q "cannot be read"; chk "a malformed workflow.json is reported, not a crash" $? ""
python "$CHECK" "$BAD" --json | python -c 'import sys,json;r=json.load(sys.stdin);sys.exit(0 if any(m["path"]==".claude/workflow.json" for m in r["missing"]) is False else 1)'
chk "...and the broken marker is not double-reported as missing" $? ""
python "$CHECK" "$W/does-not-exist" >/dev/null 2>&1; [ $? -eq 2 ]; chk "a missing directory is a usage error (exit 2)" $? ""
IDEAS="$W/ideas"; full_game "$IDEAS"; put "$IDEAS/CLAUDE.md" "- stray ideas go in docs/design-ideas.md, in the owner's words"
[ -z "$(missing "$IDEAS")" ]; chk "the CLAUDE.md pointer is recognised wherever the line sits" $? "$(missing "$IDEAS")"

echo "== the line-ending templates (issue #6)"
TPL="$HERE/../skills/project-bootstrap/templates"
GA="$W/ga"; mkdir -p "$GA"; git -C "$GA" init -q; cp "$TPL/gitattributes.txt" "$GA/.gitattributes"
attr() { git -C "$GA" check-attr "$1" -- "$2" | sed 's/.*: //' | tr -d '\r'; }
[ "$(attr eol run.sh)" = "lf" ] && [ "$(attr eol notes.md)" = "lf" ] && [ "$(attr eol src/main.py)" = "lf" ]; chk ".gitattributes: scripts and text files are LF" $? "$(attr eol run.sh) $(attr eol notes.md)"
[ "$(attr eol setup.ps1)" = "crlf" ] && [ "$(attr eol go.bat)" = "crlf" ] && [ "$(attr eol go.cmd)" = "crlf" ]; chk ".gitattributes: Windows-only scripts are CRLF" $? "$(attr eol setup.ps1)"
[ "$(attr text pic.png)" = "unset" ] && [ "$(attr text sound.ogg)" = "unset" ]; chk ".gitattributes: binaries are never converted" $? "$(attr text pic.png)"
EC="$TPL/editorconfig.txt"
python - "$EC" <<'EOF2'
import sys, re
t = open(sys.argv[1], encoding="utf-8").read()
lines = [l.strip() for l in t.splitlines() if l.strip() and not l.strip().startswith("#")]
assert lines[0] == "root = true", lines[0]
star = lines[lines.index("[*]") + 1 : lines.index("[*.md]")]
assert "end_of_line = lf" in star and "charset = utf-8" in star and "insert_final_newline = true" in star, star
assert not any(l.startswith("indent_") for l in lines), "indentation must not be set here"
assert "[*.{ps1,bat,cmd}]" in lines and lines[lines.index("[*.{ps1,bat,cmd}]") + 1] == "end_of_line = crlf"
EOF2
chk ".editorconfig: root, utf-8, LF, final newline, CRLF only for Windows scripts, no indentation rules" $? ""
NO_EC="$W/noec"; full_game "$NO_EC"; safe_rm "$NO_EC/.editorconfig"
[ "$(missing "$NO_EC")" = ".editorconfig|file" ]; chk "upgrade check: a repo without .editorconfig is offered exactly that" $? "$(missing "$NO_EC")"
NO_GA="$W/noga"; full_game "$NO_GA"; safe_rm "$NO_GA/.gitattributes"
[ "$(missing "$NO_GA")" = ".gitattributes|file" ]; chk "upgrade check: a repo without .gitattributes is offered exactly that" $? "$(missing "$NO_GA")"
grep -q "^## Line endings" "$TPL/CONTRIBUTING.md.tmpl"; chk "the CONTRIBUTING template has a Line endings section" $? ""
grep -q "^## Writing docs" "$TPL/CONTRIBUTING.md.tmpl"; chk "the CONTRIBUTING template has a Writing docs section" $? ""

echo "== subsections of the Game-specific process section (Engine conventions is a placeholder)"
SS="$W/ss"; full_game "$SS"; put "$SS/CONTRIBUTING.md" "# C
## Game-specific process
### Game docs"
[ "$(missing "$SS" | tr '
' ' ')" = "CONTRIBUTING.md|subsection CONTRIBUTING.md|subsection " ]; chk "section present: the missing subsections are reported" $? "$(missing "$SS" | tr '
' ' ')"
python "$CHECK" "$SS" | grep -q "Play-testing"; chk "...by name" $? ""
python "$CHECK" "$SS" | grep -q "Engine conventions"; chk "...Engine conventions offered when the repo has no conventions of its own" $? ""
OWN="$W/own"; full_game "$OWN"; put "$OWN/CONTRIBUTING.md" "# C
## Game-specific process
### Game docs
### Play-testing
## Godot conventions
## Cross-platform habits
## Translatable text"
[ -z "$(missing "$OWN")" ]; chk "own conventions headings: the Engine conventions subsection is not offered" $? "$(missing "$OWN")"
python "$CHECK" "$OWN" --json | python -c 'import sys,json;r=json.load(sys.stdin);sys.exit(0 if [s["subsection"] for s in r["skipped"]]==["Engine conventions"] else 1)'
chk "...and is listed as skipped" $? ""
python "$CHECK" "$OWN" | grep -q "Not offered"; chk "...and the text report says so" $? ""
OWN2="$W/own2"; full_game "$OWN2"; put "$OWN2/CONTRIBUTING.md" "# C
## Cross-platform habits"
python "$CHECK" "$OWN2" --json | python -c 'import sys,json;r=json.load(sys.stdin);m=[x for x in r["missing"] if x["type"]=="section"];sys.exit(0 if m and m[0].get("omit_subsections")==["Engine conventions"] else 1)'
chk "no section yet but own conventions: the section is to be appended without Engine conventions" $? ""
python "$CHECK" "$EMPTY" --json | python -c 'import sys,json;r=json.load(sys.stdin);m=[x for x in r["missing"] if x["type"]=="section"];sys.exit(0 if not m else 1)'
chk "no CONTRIBUTING.md at all: no section entry (the whole file is the missing piece)" $? ""

echo "== old project hooks"
python "$CHECK" "$FULL" --json | python -c 'import sys,json;r=json.load(sys.stdin)["old_hooks"];sys.exit(0 if not (r["settings"] or r["files"] or r["doc_references"]) else 1)'
chk "a repo without old hooks reports none" $? ""
OH="$W/oh"; full_game "$OH"
put "$OH/tools/hooks/block-merge-if-ci-red.sh" "#!/bin/bash"; put "$OH/tools/hooks/guard-repo-cwd.sh" "#!/bin/bash"; put "$OH/tools/hooks/other-tool.sh" "#!/bin/bash"
put "$OH/.claude/settings.json" '{"hooks":{"PreToolUse":[{"matcher":"Bash","hooks":[{"type":"command","command":"bash tools/hooks/block-merge-if-ci-red.sh"},{"type":"command","command":"bash tools/hooks/lint.sh"},{"type":"command","command":"bash \"${CLAUDE_PLUGIN_ROOT}/hooks/guard-repo-cwd.sh\""}]}]}}'
put "$OH/CONTRIBUTING.md" "# C
$GSP
The merge gate is tools/hooks/block-merge-if-ci-red.sh.
nothing here"
python "$CHECK" "$OH" --json | python -c '
import sys,json
r=json.load(sys.stdin)["old_hooks"]
assert [s["hook"] for s in r["settings"]]==["merge-gate"], r["settings"]
assert sorted(f["path"] for f in r["files"])==["tools/hooks/block-merge-if-ci-red.sh","tools/hooks/guard-repo-cwd.sh"], r["files"]
assert [(d["file"],d["line"]) for d in r["doc_references"]]==[("CONTRIBUTING.md",6)], r["doc_references"]'
chk "old copies are found by name in settings.json and tools/hooks, the plugin's own entry and other hooks are not, doc lines are listed" $? ""
python "$CHECK" "$OH" | grep -q "Old project hooks"; chk "the text report has an old-hooks section" $? ""
[ -z "$(missing "$OH")" ]; chk "old hooks are reported apart from what is missing" $? "$(missing "$OH")"
before="$(snapshot "$OH")"; python "$CHECK" "$OH" >/dev/null
[ "$before" = "$(snapshot "$OH")" ]; chk "...and detecting them modifies nothing" $? ""

echo "== kind wording"
python "$CHECK" "$EMPTY" | grep -q "no usable .claude/workflow.json was found, so game was assumed"; chk "no workflow.json: says plainly that game was assumed" $? "$(python "$CHECK" "$EMPTY" | head -2)"
python "$CHECK" "$EMPTY" | grep -q "from assumed"; [ $? -ne 0 ]; chk "...and not the old 'from assumed (bootstrap default)'" $? ""

echo "== review follow-ups"
CV="$W/cv"; full_game "$CV"; put "$CV/CONTRIBUTING.md" "# C
## Game-specific process
### Game docs
### Play-testing
## Commit conventions"
[ "$(missing "$CV")" = "CONTRIBUTING.md|subsection" ]; chk "a 'Commit conventions' heading does not excuse Engine conventions" $? "$(missing "$CV")"
AL="$W/al"; full_game "$AL"; put "$AL/CONTRIBUTING.md" "# C
## Game-specific process
### Game documents
### Playtesting
### Engine conventions"
[ -z "$(missing "$AL")" ]; chk "'Game documents' and 'Playtesting' count as the template's subsections" $? "$(missing "$AL")"
BS="$W/bs"; full_game "$BS"; put "$BS/tools/hooks/block-merge-if-ci-red.sh"; put "$BS/tools/hooks/lint.sh"
put "$BS/.claude/settings.json" '{ // comment
"hooks": {} }'
put "$BS/CONTRIBUTING.md" "# C
$GSP
Run tools/hooks/lint.sh before pushing."
python "$CHECK" "$BS" --json | python -c '
import sys,json
r=json.load(sys.stdin)["old_hooks"]
assert r["doc_references"]==[], r["doc_references"]
assert r["notes"] and "could not be parsed" in r["notes"][0], r["notes"]'
chk "unrelated tools/hooks scripts are not doc hits, and an unparseable settings.json is noted" $? ""

echo "== PR #25 blind check: what the first tests let through"
# asrt <repo> <label> <python condition over r, the JSON report>: a crash or a parse failure fails the check
asrt() {
  local out; out="$(python "$CHECK" "$1" --json 2>&1)"
  printf '%s' "$out" | python -c '
import sys, json
r = json.load(sys.stdin)
sys.exit(0 if ('"$3"') else 1)' 2>/dev/null
  chk "$2" $? "$(printf '%s' "$out" | head -c 300)"
}
F3='```'
GSP2="## Game-specific process
### Game docs
### Play-testing"

n=0
for shape in '{"hooks":{"PreToolUse":[{"hooks":null}]}}' '{"hooks":[]}' '{"hooks":null}' '{"hooks":{"PreToolUse":{}}}' '{"hooks":{"PreToolUse":[5]}}' '{"hooks":{"PreToolUse":[{"hooks":[5,{"command":7}]}]}}' '[]' 'null' '"x"'; do
  n=$((n+1)); R="$W/shape$n"; full_game "$R"; put "$R/.claude/settings.json" "$shape"
  asrt "$R" "settings.json $shape: no crash, nothing reported, no note" 'r["old_hooks"]["settings"]==[] and r["old_hooks"]["notes"]==[]'
done
SK="$W/sk"; full_game "$SK"; put "$SK/CONTRIBUTING.md" "# C
## Game-specific process
### Game docs
## Godot conventions"
asrt "$SK" "own conventions excuse only Engine conventions: Play-testing is still missing" '[(m["type"],"Play-testing" in m["what"]) for m in r["missing"] if m["path"]=="CONTRIBUTING.md"]==[("subsection",True)] and [s["subsection"] for s in r["skipped"]]==["Engine conventions"]'
asrt "$OLD" "no conventions of its own: the section is offered whole, without omit_subsections" '[("omit_subsections" in m) for m in r["missing"] if m["type"]=="section"]==[False]'
SL="$W/sl"; full_game "$SL"; put "$SL/.claude/settings.local.json" '{"hooks":{"PreToolUse":[{"matcher":"Bash","hooks":[{"type":"command","command":"bash tools/hooks/guard-repo-cwd.sh"}]}]}}'
asrt "$SL" "settings.local.json is scanned, and the entry names file, event, matcher and hook" '[(s["file"],s["event"],s["matcher"],s["hook"]) for s in r["old_hooks"]["settings"]]==[(".claude/settings.local.json","PreToolUse","Bash","cwd-guard")]'
DS="$W/ds"; full_game "$DS"; put "$DS/tools/hooks/block-merge-if-ci-red.sh"
put "$DS/CLAUDE.md" "see block-merge-if-ci-red.sh"
put "$DS/README.md" "# R
the gate is block-merge-if-ci-red.sh"
put "$DS/docs/setup/hooks.md" "block-merge-if-ci-red.sh lives here"
put "$DS/docs/notes.txt" "block-merge-if-ci-red.sh"
asrt "$DS" "doc lines are found in CLAUDE.md, README.md and nested docs/*.md, and not in other file types" 'sorted((d["file"],d["line"]) for d in r["old_hooks"]["doc_references"])==[("CLAUDE.md",1),("README.md",2),("docs/setup/hooks.md",1)]'
NS="$W/ns"; full_game "$NS"
put "$NS/.claude/settings.json" '{"hooks":{"PreToolUse":[{"hooks":[{"type":"command","command":"bash tools/hooks/common.sh && bash .claude/hooks/block-merge-if-ci-red.sh"}]}]}}'
put "$NS/CONTRIBUTING.md" "# C
## Game-specific process
The gate is block-merge-if-ci-red.sh.
Shared helpers are in common.sh."
asrt "$NS" "a script named only in settings drives the doc search; a shared helper in the same command does not" '[(d["file"],d["line"]) for d in r["old_hooks"]["doc_references"]]==[("CONTRIBUTING.md",3)]'
PF="$W/pf"; full_game "$PF"
put "$PF/.claude/settings.json" '{"hooks":{"PreToolUse":[{"hooks":[{"type":"command","command":"bash \"${CLAUDE_PLUGIN_ROOT}/hooks/block-merge-if-ci-red.sh\""},{"type":"command","command":"bash tools/hooks/block-merge-if-ci-red.sh"}]}]}}'
asrt "$PF" "the plugin's own entry is skipped, and an old copy after it in the same group is still found" '[s["hook"] for s in r["old_hooks"]["settings"]]==["merge-gate"]'
HN="$W/hn"; full_game "$HN"; for f in block_merge.sh merge_gate.py ci-red.sh guard_repo_cwd.sh cwd-guard.ps1 repo-cwd.sh other.sh; do put "$HN/tools/hooks/$f"; done
asrt "$HN" "every spelling of the two hook names is recognised and tagged with the right hook" 'sorted((f["path"].split("/")[-1],f["hook"]) for f in r["old_hooks"]["files"])==[("block_merge.sh","merge-gate"),("ci-red.sh","merge-gate"),("cwd-guard.ps1","cwd-guard"),("guard_repo_cwd.sh","cwd-guard"),("merge_gate.py","merge-gate"),("repo-cwd.sh","cwd-guard")]'

for h in "## Coding conventions" "## Conventions for Godot" "## Translatable text" "## Engine convention" "## Conventions for code style" "## Conventions: coding" "## UNITY CONVENTIONS"; do
  C="$W/cvx"; safe_rm -r "$C"; full_game "$C"; put "$C/CONTRIBUTING.md" "# C
$GSP2
$h"
  asrt "$C" "'$h' counts as the repo's own conventions" '[m for m in r["missing"] if m["path"]=="CONTRIBUTING.md"]==[] and [s["subsection"] for s in r["skipped"]]==["Engine conventions"]'
done
for h in "## Codebase conventions" "## Branch naming conventions" "## PR conventions" "We follow Godot conventions loosely."; do
  C="$W/cvn"; safe_rm -r "$C"; full_game "$C"; put "$C/CONTRIBUTING.md" "# C
$GSP2
$h"
  asrt "$C" "'$h' does not excuse Engine conventions" '[m["type"] for m in r["missing"] if m["path"]=="CONTRIBUTING.md"]==["subsection"] and r["skipped"]==[]'
done

TU="$W/tu"; mkdir -p "$TU/scripts"; cp "$CHECK" "$TU/scripts/upgrade_check.py"
out="$(python "$TU/scripts/upgrade_check.py" "$SS" --json)"; rc=$?
[ $rc -eq 0 ] && printf '%s' "$out" | python -c 'import sys,json;r=json.load(sys.stdin);sys.exit(0 if "contributing-extra.md not found" in (r["note"] or "") and not [m for m in r["missing"] if m["type"]=="subsection"] else 1)'
chk "an unreadable template is a note, not a crash and not a list of subsections" $? "rc=$rc"

NH="$W/nh"; full_game "$NH"; put "$NH/CONTRIBUTING.md" "# C
## Game-specific process
#### Play-testing
## Game docs
# ENGINE CONVENTIONS"
asrt "$NH" "template subsections are found under any heading level" '[m for m in r["missing"] if m["path"]=="CONTRIBUTING.md"]==[]'
CS="$W/cs"; full_game "$CS"; put "$CS/CONTRIBUTING.md" "# C
## Game-Specific Process
### Game docs
### Play-testing
### Engine conventions"
[ -z "$(missing "$CS")" ]; chk "the section heading is matched case-insensitively" $? "$(missing "$CS")"
FN="$W/fn"; full_game "$FN"; put "$FN/CONTRIBUTING.md" "# C
## Game-specific process
### Game docs
$F3
### Play-testing
### Engine conventions
## Cross-platform habits
$F3"
asrt "$FN" "headings inside a fenced code block are ignored (so they neither count nor excuse anything)" 'sorted(m["type"] for m in r["missing"])==["subsection","subsection"] and r["skipped"]==[]'
FS="$W/fs"; full_game "$FS"; put "$FS/CONTRIBUTING.md" "# C
$F3
## Game-specific process
$F3"
asrt "$FS" "the section heading inside a code block is not the section" '[m["type"] for m in r["missing"]]==["section"]'

UN="$W/un"; full_game "$UN"; put "$UN/tools/hooks/block-merge-if-ci-red.sh"
put "$UN/CONTRIBUTING.md" "# C
## Game-specific process
Gate: block-merge-if-ci-red.sh → ✓ done — ok"
PYTHONIOENCODING=cp1252 python "$CHECK" "$UN" >/dev/null 2>&1; chk "a doc line the console cannot print does not crash the text report" $? ""

NK="$W/nk"; full_game "$NK"; put "$NK/.claude/workflow.json" '{"version":1}'
python "$CHECK" "$NK" | grep -q "workflow.json has no kind, so game was assumed"; chk "a workflow.json with no kind says so, instead of 'no usable file found'" $? "$(python "$CHECK" "$NK" | head -3)"
python "$CHECK" "$EMPTY" --kind game | grep -q "assumed"; [ $? -ne 0 ]; chk "--kind given: nothing is described as assumed" $? ""

echo "== shadowing skills (a project copy of a plugin skill)"
SS="$W/ss"; full_game "$SS"
asrt "$SS" "no .claude/skills: nothing shadows" 'r["shadowing_skills"]==[]'
put "$SS/.claude/skills/run/SKILL.md"
asrt "$SS" "a project's own skill (run) is not a shadow" 'r["shadowing_skills"]==[]'
put "$SS/.claude/skills/pr-check/SKILL.md"; put "$SS/.claude/skills/work-issue/SKILL.md"
put "$SS/.claude/skills/other/notes.md"; mkdir -p "$SS/.claude/skills/toolchain-run"
asrt "$SS" "pr-check and work-issue copies are listed with their paths; a folder without SKILL.md is not" '[(s["skill"],s["path"]) for s in r["shadowing_skills"]]==[("pr-check",".claude/skills/pr-check/SKILL.md"),("work-issue",".claude/skills/work-issue/SKILL.md")]'
SC="$W/sc"; full_game "$SC"; put "$SC/.claude/skills/Pr-Check/SKILL.md"
asrt "$SC" "the folder name is matched ignoring case, and the report keeps the real spelling" '[(s["skill"],s["path"]) for s in r["shadowing_skills"]]==[("pr-check",".claude/skills/Pr-Check/SKILL.md")]'
python "$CHECK" "$SS" | grep -q "pr-check/SKILL.md \[pr-check\]"; chk "the text report names the shadowing copy" $? "$(python "$CHECK" "$SS" | tail -5)"
BEFORE="$(snapshot "$SS")"; python "$CHECK" "$SS" >/dev/null; [ "$BEFORE" = "$(snapshot "$SS")" ]; chk "listing a shadowing skill changes nothing" $? ""

echo; echo "passed: $PASS   failed: $FAIL"
[ "$FAIL" -eq 0 ]
