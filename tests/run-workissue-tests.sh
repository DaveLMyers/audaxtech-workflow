#!/usr/bin/env bash
# Tests for the work-issue skill's helper scripts: branch naming (pure) and
# board status changes (against a FAKE `gh`, so nothing touches a real board).
#
# Usage: bash tests/run-workissue-tests.sh      (exit 0 = all passed)
set -u

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$HERE/_safe_rm.sh"
S="$HERE/../skills/work-issue/scripts"
W="$(mktemp -d)"; safe_rm_allow "$W"; trap 'safe_rm -r "$W"' EXIT
PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); echo "ok    $1"; }
bad() { FAIL=$((FAIL+1)); echo "FAIL  $1  (${2:0:240})"; }
eq()  { [ "$2" = "$3" ] && ok "$1" || bad "$1" "expected '$3' got '$2'"; }
chk() { [ "$2" -eq 0 ] && ok "$1" || bad "$1" "$3"; }

echo "== branch names"
bn() { python "$S/branch_name.py" "$@"; }
eq "feature, prefix + parenthesised aside + stop words dropped" \
   "$(bn --title 'feat(board): a swappable pop effect on every popped piece (first effect: target-color confetti)' --labels 'type:feature,area:board' --number 90)" \
   "feature/swappable-pop-effect-popped-piece"
eq "bug label becomes fix/" "$(bn --title 'fix(board): target color can become unreachable' --labels 'type:bug' --number 17)" "fix/target-color-can-become-unreachable"
eq "chore, plain prefix" "$(bn --title 'chore: add the type:research label' --labels 'type:chore' --number 87)" "chore/add-type-research-label"
eq "research label" "$(bn --title 'research: what would a Web export take?' --labels 'type:research' --number 88)" "research/what-would-web-export-take"
eq "no type label falls back to chore" "$(bn --title 'tidy things' --labels 'area:build' --number 5)" "chore/tidy-things"
eq "nothing usable left -> issue-N" "$(bn --title '???' --labels '' --number 12)" "chore/issue-12"
eq "custom pattern with the number" "$(bn --title 'docs: add design-ideas.md' --labels 'type:docs' --pattern '{type}/{number}-{slug}' --number 88)" "docs/88-add-design-ideas-md"
L="$(bn --title 'feat: one two three four five six seven eight' --labels 'type:feature' --number 1)"
eq "slug is capped at 5 words" "$L" "feature/one-two-three-four-five"
LONG="$(bn --title 'feat: extraordinarily-long-hyphenated-compound words everywhere' --labels 'type:feature' --number 2)"
[ "${#LONG}" -le 50 ] && ok "slug length is capped (${#LONG} chars)" || bad "slug length capped" "$LONG"

echo "== docs-only classification (pr-check's docs_only.py, issue #7)"
DO="$HERE/../skills/pr-check/scripts/docs_only.py"
dox() { python "$DO" "$@" 2>&1; }
is_docs()  { out="$(dox "$@")"; rc=$?; [ $rc -eq 0 ] && [ "$out" = "docs-only" ] && ok "docs-only: $*" || bad "docs-only: $*" "rc=$rc $out"; }
not_docs() { out="$(dox "$@")"; rc=$?; [ $rc -eq 1 ] && echo "$out" | grep -q "^not docs-only" && ok "NOT docs-only: $*" || bad "NOT docs-only: $*" "rc=$rc $out"; }
each_not_docs() { local a; for a in "$@"; do not_docs "$a"; done; }
is_docs docs/DECISIONS.md
is_docs README.md docs/design.md docs/img/shot.png
is_docs CONTRIBUTING.md CHANGELOG.md LICENSE
is_docs ./docs/notes.txt
is_docs docs/GUIDE.MD
not_docs skills/work-issue/SKILL.md
not_docs docs/guide.md skills/pr-check/SKILL.md
not_docs CLAUDE.md
not_docs docs/CLAUDE.md
not_docs agents/test-saboteur.md
not_docs skills/project-bootstrap/templates/CONTRIBUTING.md.tmpl
not_docs docs/templates/page.md
not_docs .github/PULL_REQUEST_TEMPLATE.md
not_docs .claude/workflow.json
not_docs tests/README.md
not_docs hooks/README.md
not_docs src/main.py
not_docs docs/run.sh
not_docs README.md.bak
not_docs docs/../skills/a/SKILL.md
not_docs ../outside/README.md
not_docs /etc/README.md
is_docs docs/a.rst docs/b.markdown docs/c.txt docs/i.jpg docs/i.jpeg docs/i.gif docs/i.svg docs/i.webp docs/i.png
is_docs Docs/guide.md DOCS/Guide.MD
is_docs 'docs\guide.md'
is_docs "docs/my file.md" docs/.notes.md docs/skills.md docs/skills-overview.md docs/myskills/a.md docs/test/a.md docs/scripts.md
is_docs README README.txt README.rst NOTICE NOTICE.txt SECURITY.md CODE_OF_CONDUCT.md Readme.md license
is_docs docs/../README.md docs/./x.md docs//x.md docs/sub/../x.md
not_docs requirements.txt
not_docs NOTES.md
not_docs design-ideas.md
not_docs README.png
each_not_docs README.py LICENSE.sh CHANGELOG.json
not_docs docs/SKILL.md
not_docs SKILL.md
not_docs docs/skill.md
not_docs docs/Skills/a.md
not_docs docs/Templates/page.md
each_not_docs docs/skills/a.md docs/agents/a.md docs/hooks/a.md docs/commands/a.md docs/scripts/a.md docs/tests/a.md
not_docs docs/.claude/a.md
not_docs docs/.github/a.md
not_docs docs/guide/templates/page.md
not_docs docs/a/b/hooks/c.md
not_docs src/docs/api.md
not_docs docs-old/a.md
not_docs mydocs/a.md
not_docs docs.md
each_not_docs docs/x.pdf docs/x.html
not_docs docs/notes
not_docs docs/x.md.bak
not_docs docs/x.md.tmpl
each_not_docs logo.png assets/a.svg
not_docs 'c:docs\x.md'
not_docs 'docs/sub\..\..\x.md'
not_docs 'C:\docs\x.md'
not_docs '\\server\share\docs\x.md'
each_not_docs .gitattributes .editorconfig Makefile
not_docs ""
out="$(dox --base main extra)"; rc=$?; [ $rc -eq 2 ]; chk "--base with an extra argument is a usage error (exit 2)" $? "rc=$rc $out"
out="$(dox --help)"; rc=$?; [ $rc -eq 2 ]; chk "an unknown flag is a usage error (exit 2)" $? "rc=$rc $out"
out="$(dox -x)"; rc=$?; [ $rc -eq 2 ]; chk "a leading dash is a usage error, not a path" $? "rc=$rc $out"
out="$(dox docs/a.md src/b.py skills/c/SKILL.md)"; echo "$out" | grep -q "src/b.py" && echo "$out" | grep -q "skills/c/SKILL.md" && ! echo "$out" | grep -q "docs/a.md"
chk "the not-docs-only answer names exactly the offending files" $? "$out"
out="$(dox)"; rc=$?; [ $rc -eq 2 ]; chk "no arguments is a usage error (exit 2)" $? "rc=$rc"
out="$(dox --base)"; rc=$?; [ $rc -eq 2 ]; chk "--base without a branch is a usage error (exit 2)" $? "rc=$rc"
DG="$W/dg"; mkdir -p "$DG/docs" "$DG/skills/x"; git -C "$DG" init -q -b main; git -C "$DG" config user.email t@t; git -C "$DG" config user.name t
echo a > "$DG/README.md"; git -C "$DG" add README.md; git -C "$DG" commit -q -m base
git -C "$DG" checkout -q -b docs-branch; echo b > "$DG/docs/new.md"; git -C "$DG" add docs/new.md; git -C "$DG" commit -q -m docs
out="$(cd "$DG" && python "$DO" --base main 2>&1)"; rc=$?
[ $rc -eq 0 ] && [ "$out" = "docs-only" ]; chk "--base reads the branch's changed files from git: a docs branch is docs-only" $? "rc=$rc $out"
echo c > "$DG/skills/x/SKILL.md"; git -C "$DG" add skills/x/SKILL.md; git -C "$DG" commit -q -m skill
out="$(cd "$DG" && python "$DO" --base main 2>&1)"; rc=$?
[ $rc -eq 1 ] && echo "$out" | grep -q "skills/x/SKILL.md"; chk "...and adding a SKILL.md makes it not docs-only, naming the file" $? "rc=$rc $out"
# a repo whose base branch moves on after the branch was cut (three-dot semantics), renames, deletions, odd names
DH="$W/dh"; mkdir -p "$DH/docs" "$DH/skills/x" "$DH/scripts"; git -C "$DH" init -q -b main; git -C "$DH" config user.email t@t; git -C "$DH" config user.name t
echo a > "$DH/README.md"; echo s > "$DH/skills/x/SKILL.md"; echo r > "$DH/scripts/a.py"; git -C "$DH" add -A; git -C "$DH" commit -q -m base
git -C "$DH" checkout -q -b topic; echo b > "$DH/docs/new.md"; git -C "$DH" add -A; git -C "$DH" commit -q -m docs
git -C "$DH" checkout -q main; mkdir -p "$DH/src"; echo c > "$DH/src/x.py"; git -C "$DH" add -A; git -C "$DH" commit -q -m "main moves on"
git -C "$DH" checkout -q topic
out="$(cd "$DH" && python "$DO" --base main 2>&1)"; rc=$?
[ $rc -eq 0 ] && [ "$out" = "docs-only" ]; chk "--base uses the merge base: files changed on main after the branch point are ignored" $? "rc=$rc $out"
git -C "$DH" mv skills/x/SKILL.md docs/moved.md; git -C "$DH" commit -q -m "move a skill into docs"
out="$(cd "$DH" && python "$DO" --base main 2>&1)"; rc=$?
[ $rc -eq 1 ] && echo "$out" | grep -q "skills/x/SKILL.md"; chk "moving a SKILL.md into docs/ is not docs-only: the file that disappeared is listed" $? "rc=$rc $out"
git -C "$DH" reset -q --hard HEAD~1
git -C "$DH" rm -q scripts/a.py; git -C "$DH" commit -q -m "delete a script"
out="$(cd "$DH" && python "$DO" --base main 2>&1)"; rc=$?
[ $rc -eq 1 ] && echo "$out" | grep -q "scripts/a.py"; chk "deleting a script is not docs-only" $? "rc=$rc $out"
git -C "$DH" reset -q --hard HEAD~1
echo d > "$DH/docs/café notes.md"; echo e > "$DH/docs/it's.md"; git -C "$DH" add -A; git -C "$DH" commit -q -m "odd names"
out="$(cd "$DH" && python "$DO" --base main 2>&1)"; rc=$?
[ $rc -eq 0 ] && [ "$out" = "docs-only" ]; chk "docs with non-ASCII, space and quote characters in their names are docs-only" $? "rc=$rc $out"
mkdir -p "$DH/docs/sub"; (cd "$DH/docs/sub" && python "$DO" --base main) >/dev/null 2>&1; [ $? -eq 0 ]; chk "--base from a subfolder gives the same answer" $? ""
out="$(cd "$DH" && PATH="$W/nowhere" "$(command -v python)" "$DO" --base main 2>&1)"; rc=$?
[ $rc -eq 2 ]; chk "git missing from PATH is an error (exit 2), not 'not docs-only'" $? "rc=$rc $out"
git -C "$DG" checkout -q main
out="$(cd "$DG" && python "$DO" --base main 2>&1)"; rc=$?
[ $rc -eq 1 ] && echo "$out" | grep -q "no changed files"; chk "a branch with no changes is not docs-only" $? "rc=$rc $out"
out="$(cd "$DG" && python "$DO" --base no-such-branch 2>&1)"; rc=$?
[ $rc -eq 2 ]; chk "an unknown base branch is an error (exit 2), not 'docs-only'" $? "rc=$rc $out"

echo "== board status (fake gh)"
PID="PVT_proj"; OTHER="PVT_other"; FIELD="PVTSSF_status"
mkdir -p "$W/proj/.claude" "$W/bin"; git -C "$W/proj" init -q
cat > "$W/proj/.claude/workflow.json" <<EOF
{"version":1,"board":{"owner":"me","number":1,"project_id":"$PID",
 "columns":{"backlog":"Backlog","ready":"Ready","in_progress":"In Progress","in_review":"In Review","done":"Done"},
 "fields":{"status":{"id":"$FIELD","options":{"backlog":"O_BACK","ready":"O_READY","in_progress":"O_INP","in_review":"O_REV","done":"O_DONE"}}}}}
EOF
# Fake gh: a Python script so it runs the same on Windows, macOS and Linux.
# State lives in $FAKE_STATE (current Status name, "on the board" flag, call log);
# env switches simulate failure modes.
cat > "$W/fake_gh.py" <<'EOF'
import json, os, sys
st = os.environ["FAKE_STATE"]
args = sys.argv[1:]
open(os.path.join(st, "calls.log"), "a").write(" ".join(args) + " @cwd=" + os.path.basename(os.getcwd()) + "\n")
flag = lambda n: os.environ.get(n, "0") == "1"
def out(s): print(s); sys.exit(0)
joined = " ".join(args)
if args[:2] == ["repo", "view"]: out("me/demo")
if args[:2] == ["api", "graphql"]:
    if "repository(owner" in joined:
        if flag("FAKE_NO_ISSUE"): out(json.dumps({"data": {"repository": {"issue": None}}}))
        if flag("FAKE_OTHER_PROJECT"): nodes = [{"id": "PVTI_elsewhere", "project": {"id": "PVT_other"}}]
        elif os.path.exists(os.path.join(st, "onboard")): nodes = [{"id": "PVTI_x", "project": {"id": "PVT_proj"}}]
        else: nodes = []
        out(json.dumps({"data": {"repository": {"issue": {"id": "I_1", "url": "https://github.com/me/demo/issues/7", "projectItems": {"nodes": nodes}}}}}))
    if "node(id" in joined:
        name = open(os.path.join(st, "status")).read().strip()
        out(json.dumps({"data": {"node": {"fieldValueByName": {"name": name}}}}))
if args[:2] == ["project", "item-add"]:
    if os.environ.get("FAKE_ADD_OUT"): out(os.environ["FAKE_ADD_OUT"])
    open(os.path.join(st, "onboard"), "w").close(); out("PVTI_new")
if args[:2] == ["project", "item-edit"]:
    if flag("FAKE_EDIT_NOOP"): sys.exit(0)          # "succeeds" but changes nothing
    opt = args[args.index("--single-select-option-id") + 1]
    names = {"O_INP": "In Progress", "O_READY": "Ready", "O_DONE": "Done"}
    if opt in names: open(os.path.join(st, "status"), "w").write(names[opt])
    sys.exit(0)
sys.stderr.write("fake gh: unhandled: " + joined + "\n"); sys.exit(1)
EOF
WN="$(cygpath -m "$W" 2>/dev/null || echo "$W")"        # native-style path for the python-based fake
export AUDAX_GH="python $WN/fake_gh.py" FAKE_STATE="$WN"
reset() { safe_rm "$W/onboard" "$W/calls.log"; echo "Backlog" > "$W/status"; touch "$W/calls.log"; unset FAKE_NO_ISSUE FAKE_OTHER_PROJECT FAKE_ADD_OUT FAKE_EDIT_NOOP; }
bs() { env -u CLAUDE_PROJECT_DIR python "$S/board_status.py" "$@" --project-dir "$W/proj" 2>&1; }

reset; touch "$W/onboard"
out="$(bs 7 in_progress)"; rc=$?
[ $rc -eq 0 ] && [ "$out" = "#7 -> In Progress" ] && ok "issue already on the board: status set and read back" || bad "set on existing item" "rc=$rc $out"
grep -q "item-edit --project-id PVT_proj --id PVTI_x --field-id PVTSSF_status --single-select-option-id O_INP" "$W/calls.log"; [ $? -eq 0 ] && ok "  edit used the right project, item, field and option ids" || bad "edit ids" "$(cat "$W/calls.log")"
grep -q "item-add" "$W/calls.log"; [ $? -ne 0 ] && ok "  and did not re-add it" || bad "no re-add" "$(cat "$W/calls.log")"

reset
out="$(bs 7 in_progress)"; rc=$?
[ $rc -eq 0 ] && [ "$out" = "#7 -> In Progress" ] && ok "issue NOT on the board: added first, then set" || bad "add then set" "rc=$rc $out"
grep -q "item-add 1 --owner me --url https://github.com/me/demo/issues/7" "$W/calls.log"; [ $? -eq 0 ] && ok "  item-add used the board number, owner and the issue's url" || bad "item-add args" "$(cat "$W/calls.log")"

reset; export FAKE_OTHER_PROJECT=1
out="$(bs 7 ready)"; rc=$?
[ $rc -eq 0 ] && grep -q "item-add" "$W/calls.log" && ok "issue only on a DIFFERENT project: still added to this one" || bad "other project" "rc=$rc $out $(cat "$W/calls.log")"

reset; touch "$W/onboard"; export FAKE_EDIT_NOOP=1
out="$(bs 7 in_progress)"; rc=$?
[ $rc -eq 4 ] && echo "$out" | grep -q "reads back" && ok "an edit that silently does nothing is caught (exit 4)" || bad "silent no-op edit" "rc=$rc $out"

reset; export FAKE_ADD_OUT="garbage"
out="$(bs 7 in_progress)"; rc=$?
[ $rc -eq 4 ] && ok "item-add returning no item id is caught (exit 4)" || bad "bad item-add" "rc=$rc $out"

reset; touch "$W/onboard"; echo "In Progress" > "$W/status"
out="$(bs 7 --read)"; rc=$?
[ $rc -eq 0 ] && [ "$out" = "#7 -> In Progress" ] && ok "--read prints the current status" || bad "--read" "rc=$rc $out"

reset
out="$(bs 7 --read)"; rc=$?
[ $rc -eq 3 ] && ! grep -q "item-add" "$W/calls.log" && ok "--read on an issue not on the board: exit 3 and changes nothing" || bad "--read not on board" "rc=$rc $out"

reset; out="$(bs 7 sideways)"; rc=$?
[ $rc -eq 2 ] && echo "$out" | grep -q "unknown role" && ok "unknown role is rejected (exit 2)" || bad "unknown role" "rc=$rc $out"

reset; export FAKE_NO_ISSUE=1; out="$(bs 7 ready)"; rc=$?
[ $rc -eq 2 ] && echo "$out" | grep -q "not found" && ok "nonexistent issue is rejected (exit 2)" || bad "no issue" "rc=$rc $out"

reset; mkdir -p "$W/bare"; git -C "$W/bare" init -q
out="$(python "$S/board_status.py" 7 ready --project-dir "$W/bare" 2>&1)"; rc=$?
[ $rc -eq 2 ] && echo "$out" | grep -q "no .claude/workflow.json" && ok "project without workflow.json: clear error (exit 2)" || bad "no config" "rc=$rc $out"

echo "== board status: finding the project from anywhere (issue #5)"
mkdir -p "$W/elsewhere"
bsx() { (cd "$W/elsewhere" && env -u CLAUDE_PROJECT_DIR python "$S/board_status.py" "$@" 2>&1); }
reset; touch "$W/onboard"; echo "In Progress" > "$W/status"
out="$(bsx 7 --read --repo "$W/proj")"; rc=$?
[ $rc -eq 0 ] && [ "$out" = "#7 -> In Progress" ] && ok "--repo <path> works from a directory outside the project" || bad "--repo path from elsewhere" "rc=$rc $out"
out="$(bsx 7 --read --project-dir "$W/proj")"; rc=$?
[ $rc -eq 0 ] && [ "$out" = "#7 -> In Progress" ] && ok "--project-dir still works the same way" || bad "--project-dir" "rc=$rc $out"
out="$(cd "$W/elsewhere" && CLAUDE_PROJECT_DIR="$WN/proj" python "$S/board_status.py" 7 --read 2>&1)"; rc=$?
[ $rc -eq 0 ] && [ "$out" = "#7 -> In Progress" ] && ok "\$CLAUDE_PROJECT_DIR is used when no flag is given" || bad "env var" "rc=$rc $out"
out="$(cd "$W/elsewhere" && CLAUDE_PROJECT_DIR="$WN/bare" python "$S/board_status.py" 7 --read --repo "$W/proj" 2>&1)"; rc=$?
[ $rc -eq 0 ] && [ "$out" = "#7 -> In Progress" ] && ok "--repo <path> beats a \$CLAUDE_PROJECT_DIR that points elsewhere" || bad "flag beats env" "rc=$rc $out"
out="$(bsx 7 --read)"; rc=$?
[ $rc -eq 2 ] && echo "$out" | grep -q "no .claude/workflow.json" && echo "$out" | grep -q "elsewhere" && echo "$out" | grep -q -- "--repo <path to the project>"
chk_e=$?; [ $chk_e -eq 0 ] && ok "no config found: the error names where it looked and suggests --repo" || bad "error message" "rc=$rc $out"
out="$(bsx 7 --read --repo not-a-folder)"; rc=$?
[ $rc -eq 2 ] && echo "$out" | grep -q "neither an existing folder nor owner/name" && ok "--repo with neither a folder nor owner/name is rejected" || bad "bad --repo" "rc=$rc $out"
# owner/name and the working directory come from the project folder, not from the caller
reset; touch "$W/onboard"; echo "In Progress" > "$W/status"
bsx 7 --read --repo "$W/proj" >/dev/null
grep -q "^repo view .*@cwd=proj$" "$W/calls.log" && grep -q -- "-f o=me -f r=demo" "$W/calls.log" && grep -q -- "-F n=7 @cwd=proj$" "$W/calls.log"
chk "--repo <path>: gh asked for owner/name from inside the project, and that name was used" $? "$(cat "$W/calls.log")"
# searching upward, and where the search stops
mkdir -p "$W/proj/sub/deeper"
out="$(bsx 7 --read --repo "$W/proj/sub/deeper")"; rc=$?
[ $rc -eq 0 ] && [ "$out" = "#7 -> In Progress" ]; chk "--repo <subfolder>: the search goes up to the project's workflow.json" $? "rc=$rc $out"
out="$(cd "$W/proj/sub/deeper" && env -u CLAUDE_PROJECT_DIR python "$S/board_status.py" 7 --read 2>&1)"; rc=$?
[ $rc -eq 0 ] && [ "$out" = "#7 -> In Progress" ]; chk "no flag, current directory inside the project: found by searching up" $? "rc=$rc $out"
mkdir -p "$W/outer/.claude" "$W/outer/inner/x"; cp "$W/proj/.claude/workflow.json" "$W/outer/.claude/"; git -C "$W/outer/inner" init -q
out="$(bsx 7 --read --repo "$W/outer/inner/x")"; rc=$?
[ $rc -eq 2 ] && echo "$out" | grep -q "looked in 2 folders, ending at .*inner"; chk "the search stops at the repo root and never uses a config above it" $? "rc=$rc $out"
# what the not-found message says
out="$(bsx 7 --read --project-dir "$W/bare")"
echo "$out" | grep -q "(--project-dir; looked in 1 folder, ending at .*bare)"; chk "message: --project-dir named as the source, 1 folder, ends at the repo root" $? "$out"
out="$(bsx 7 --read --repo "$W/bare")"
echo "$out" | grep -q "(--repo; looked in 1 folder"; chk "message: --repo named as the source" $? "$out"
out="$(cd "$W/elsewhere" && CLAUDE_PROJECT_DIR="$WN/bare" python "$S/board_status.py" 7 --read 2>&1)"
echo "$out" | grep -q '([$]CLAUDE_PROJECT_DIR; looked in 1 folder'; chk "message: CLAUDE_PROJECT_DIR named as the source" $? "$out"
mkdir -p "$W/elsewhere/a/b"
out="$(cd "$W/elsewhere/a/b" && env -u CLAUDE_PROJECT_DIR python "$S/board_status.py" 7 --read 2>&1)"
echo "$out" | grep -Eq "[(]the current directory; looked in ([3-9]|[1-9][0-9]+) folders"; chk "message: the current directory named, with a folder count of at least 3" $? "$out"
# precedence
out="$(cd "$W/elsewhere" && CLAUDE_PROJECT_DIR="$WN/bare" python "$S/board_status.py" 7 --read --project-dir "$W/proj" 2>&1)"; rc=$?
[ $rc -eq 0 ] && [ "$out" = "#7 -> In Progress" ]; chk "--project-dir beats CLAUDE_PROJECT_DIR" $? "rc=$rc $out"
# bad values fail before any gh call
reset
for bad in "../projx" "C:/no/such/proj" "no-slash"; do
  out="$(bsx 7 --read --repo "$bad")"; rc=$?
  [ $rc -eq 2 ] && echo "$out" | grep -q "neither an existing folder"; chk "a mistyped path ($bad) is an error, not owner/name" $? "rc=$rc $out"
done
out="$(bsx 7 --read --project-dir "$W/not-there")"; rc=$?
[ $rc -eq 2 ] && echo "$out" | grep -q "not a folder that exists"; chk "a --project-dir that does not exist is an error, not a search from its parent" $? "rc=$rc $out"
out="$(bsx 7 --read --repo)"; rc=$?
[ $rc -eq 2 ] && echo "$out" | grep -q "needs a value" && ! echo "$out" | grep -q Traceback; chk "a flag with no value is a usage error, not a crash" $? "rc=$rc $out"
[ ! -s "$W/calls.log" ]; chk "none of those made a gh call" $? "$(cat "$W/calls.log")"
reset; touch "$W/onboard"; bs '#7' --read >/dev/null
grep -q -- "-F n=7" "$W/calls.log"; chk "a #7 style issue number is passed as 7" $? "$(cat "$W/calls.log")"

reset; touch "$W/onboard"
out="$(bs 7 --read --repo me/demo)"; rc=$?
[ $rc -eq 0 ] && grep -q "o=me" "$W/calls.log" && grep -q "r=demo" "$W/calls.log" && ok "--repo owner/name still names the GitHub repo" || bad "--repo owner/name" "rc=$rc $out $(cat "$W/calls.log")"

reset; python - "$W/proj/.claude/workflow.json" <<'PYEOF'
import json,sys
p=sys.argv[1]; d=json.load(open(p)); del d["board"]["fields"]["status"]["options"]["done"]; json.dump(d,open(p,"w"))
PYEOF
out="$(bs 7 done)"; rc=$?
[ $rc -eq 2 ] && echo "$out" | grep -q "no id for role" && ok "a role with no option id in the config is rejected (exit 2)" || bad "missing option id" "rc=$rc $out"

echo "== bootstrap's board config feeds work-issue (producer/consumer contract)"
BJ="$HERE/../skills/project-bootstrap/scripts/board_json.py"
cat > "$W/fields.json" <<'EOF'
{"fields":[{"id":"PVTSSF_status","name":"Status","type":"ProjectV2SingleSelectField","options":[
 {"id":"O_BACK","name":"Backlog"},{"id":"O_READY","name":"Ready"},{"id":"O_INP","name":"In Progress"},{"id":"O_REV","name":"In Review"},{"id":"O_DONE","name":"Done"}]},
 {"id":"PVTSSF_prio","name":"Priority","type":"ProjectV2SingleSelectField","options":[{"id":"P_1","name":"P1"},{"id":"P_2","name":"P2"},{"id":"P_3","name":"P3"}]},
 {"id":"F_title","name":"Title","type":"ProjectV2Field"}]}
EOF
python "$BJ" me 1 PVT_proj < "$W/fields.json" > "$W/board.json" 2>"$W/bj.err"; rc=$?
python - "$W/board.json" <<'PYEOF2'
import json,sys
b=json.load(open(sys.argv[1]))
assert b["columns"]=={"backlog":"Backlog","ready":"Ready","in_progress":"In Progress","in_review":"In Review","done":"Done"}, b["columns"]
assert b["fields"]["status"]["options"]=={"backlog":"O_BACK","ready":"O_READY","in_progress":"O_INP","in_review":"O_REV","done":"O_DONE"}, b["fields"]["status"]
assert b["fields"]["priority"]["options"]=={"P1":"P_1","P2":"P_2","P3":"P_3"}
assert b["owner"]=="me" and b["number"]==1 and b["project_id"]=="PVT_proj" and b["fields"]["status"]["id"]=="PVTSSF_status"
PYEOF2
[ $rc -eq 0 ] && [ $? -eq 0 ] && ok "board_json: options are keyed by role, columns map role to display name, priority kept" || bad "board_json shape" "rc=$rc $(cat "$W/bj.err")"
sed 's/"In Review"/"Review"/' "$W/fields.json" | python "$BJ" me 1 PVT_proj >/dev/null 2>"$W/bj.err"; rc=$?
[ $rc -ne 0 ] && grep -q "in_review" "$W/bj.err" && ok "board_json: a renamed/missing column fails loudly, naming the role" || bad "board_json renamed column" "rc=$rc $(cat "$W/bj.err")"
python - "$W/board.json" "$W/proj/.claude/workflow.json" <<'PYEOF2'
import json,sys
json.dump({"version":1,"board":json.load(open(sys.argv[1]))},open(sys.argv[2],"w"))
PYEOF2
reset; touch "$W/onboard"
out="$(bs 7 in_progress)"; rc=$?
[ $rc -eq 0 ] && [ "$out" = "#7 -> In Progress" ] && ok "a workflow.json built from bootstrap's output works with board_status.py end to end" || bad "roundtrip" "rc=$rc $out"

echo "== create-board.sh saved views (fake gh)"
CB="$HERE/../skills/project-bootstrap/scripts/create-board.sh"
mkdir -p "$W/cbbin"
cat > "$W/cbbin/gh" <<'GHEOF'
#!/usr/bin/env bash
exec python "$FAKE_CB_PY" "$@"
GHEOF
chmod +x "$W/cbbin/gh"
cat > "$W/fake_cb.py" <<'PYEOF3'
import json, os, sys
args = sys.argv[1:]
open(os.environ["FAKE_CB_LOG"], "a").write(" ".join(args) + "\n")
joined = " ".join(args)
fail = os.environ.get("FAKE_CB_FAIL", "")
def out(s=""): print(s); sys.exit(0)
if args[:2] == ["auth", "status"]: out("token scopes: 'project', 'repo'")
if args[:2] == ["project", "create"]: out(json.dumps({"number": 9, "id": "PVT_new"}))
if args[:2] == ["project", "field-list"]:
    out(json.dumps({"fields": [
        {"id": "F_title", "name": "Title"}, {"id": "F_assign", "name": "Assignees"}, {"id": "F_labels", "name": "Labels"},
        {"id": "PVTSSF_status", "name": "Status", "options": [{"id": "O1", "name": "Backlog"}, {"id": "O2", "name": "Ready"},
            {"id": "O3", "name": "In Progress"}, {"id": "O4", "name": "In Review"}, {"id": "O5", "name": "Done"}]},
        {"id": "F_prio", "name": "Priority", "options": [{"id": "P1", "name": "P1"}, {"id": "P2", "name": "P2"}, {"id": "P3", "name": "P3"}]}]}))
if args[:2] == ["api", "graphql"]:
    if "views(first" in joined:
        out(json.dumps({"data": {"node": {"views": {"nodes": [{"id": "V_default", "name": "View 1", "layout": "TABLE_LAYOUT"}]}}}}))
    if "createProjectV2View" in joined:
        if fail == "create": print("boom", file=sys.stderr); sys.exit(1)
        out("{}")
    if "updateProjectV2View" in joined:
        if fail == "rename": print("boom", file=sys.stderr); sys.exit(1)
        out("{}")
    out("{}")
out()
PYEOF3
runcb() {  # $1 = failure mode (or empty); sets CBOUT (stdout), CBERR (stderr), CBRC
  : > "$W/cb.log"
  CBOUT="$(FAKE_CB_PY="$W/fake_cb.py" FAKE_CB_LOG="$W/cb.log" FAKE_CB_FAIL="$1" PATH="$W/cbbin:$PATH" bash "$CB" me demo "Demo board" "core" 2>"$W/cb.err")"; CBRC=$?
  CBERR="$(cat "$W/cb.err")"
}
isjson() { python -c 'import sys,json;json.load(sys.stdin)' >/dev/null 2>&1; }
runcb ""
CALLS="$(cat "$W/cb.log")"
[ $CBRC -eq 0 ] && echo "$CALLS" | grep -q "createProjectV2View" && echo "$CALLS" | grep -q "BOARD_LAYOUT" && echo "$CALLS" | grep -q 'name:"Prioritized backlog"' \
  && ok "creates a 'Prioritized backlog' board-layout view" || bad "view created" "rc=$CBRC $CALLS $CBERR"
for f in F_title F_assign F_labels F_prio; do echo "$CALLS" | grep -q "ids\[\]=$f" || bad "visible field $f passed" "$CALLS"; done
echo "$CALLS" | grep -q "ids\[\]=PVTSSF_status" && bad "Status must not be a visible field" "$CALLS" || ok "visible fields are Title, Assignees, Labels, Priority (not Status)"
echo "$CALLS" | grep -q "updateProjectV2View" && echo "$CALLS" | grep -q "v=V_default" && ok "renames the default table view to 'Table'" || bad "rename" "$CALLS"
FC="$(echo "$CALLS" | grep -n 'field-create' | head -1 | cut -d: -f1)"; VC="$(echo "$CALLS" | grep -n 'createProjectV2View' | head -1 | cut -d: -f1)"
[ -n "$FC" ] && [ -n "$VC" ] && [ "$FC" -lt "$VC" ] && ok "the view is created after the Priority field" || bad "ordering" "field-create line '$FC', view line '$VC'"
echo "$CBOUT" | isjson && ok "board JSON is printed on stdout" || bad "board json" "$CBOUT"
runcb create
echo "$CBERR" | grep -q "could not create the 'Prioritized backlog' view" && [ $CBRC -eq 0 ] && echo "$CBOUT" | isjson \
  && ok "a failing view creation warns, is non-fatal, and the board JSON is still printed" || bad "create failure" "rc=$CBRC $CBERR"
grep -q "label create" "$W/cb.log" && ok "labels are still created after a view failure" || bad "labels after failure" "$(cat "$W/cb.log")"
runcb rename
echo "$CBERR" | grep -q "could not rename the default view" && [ $CBRC -eq 0 ] && ! echo "$CBERR" | grep -q "could not create" && echo "$CBOUT" | isjson \
  && ok "a failing rename only warns about the rename" || bad "rename failure" "rc=$CBRC $CBERR"

echo; echo "passed: $PASS   failed: $FAIL"
[ "$FAIL" -eq 0 ]
