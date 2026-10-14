#!/usr/bin/env bash
# Tests for the work-issue skill's helper scripts: branch naming (pure) and
# board status changes (against a FAKE `gh`, so nothing touches a real board).
#
# Usage: bash tests/run-workissue-tests.sh      (exit 0 = all passed)
set -u

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
S="$HERE/../skills/work-issue/scripts"
W="$(mktemp -d)"; trap 'rm -rf "$W"' EXIT
PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); echo "ok    $1"; }
bad() { FAIL=$((FAIL+1)); echo "FAIL  $1  (${2:0:240})"; }
eq()  { [ "$2" = "$3" ] && ok "$1" || bad "$1" "expected '$3' got '$2'"; }

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
open(os.path.join(st, "calls.log"), "a").write(" ".join(args) + "\n")
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
reset() { rm -f "$W/onboard" "$W/calls.log"; echo "Backlog" > "$W/status"; touch "$W/calls.log"; unset FAKE_NO_ISSUE FAKE_OTHER_PROJECT FAKE_ADD_OUT FAKE_EDIT_NOOP; }
bs() { python "$S/board_status.py" "$@" --project-dir "$W/proj" 2>&1; }

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

echo; echo "passed: $PASS   failed: $FAIL"
[ "$FAIL" -eq 0 ]
