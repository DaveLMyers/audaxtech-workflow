#!/usr/bin/env bash
# Behavior tests for the plugin's hooks. Self-contained and safe to run
# anywhere: it builds throwaway git repos in temp dirs, and uses a FAKE `gh`
# on PATH, so it never touches a real repo, PR or network.
#
# Usage: bash tests/run-hook-tests.sh      (exit 0 = all passed)
#
# Note for Claude Code sessions: the merge-gate hook inspects the Bash command
# text, so a command line that literally contains the merge phrase is denied
# before it runs. This file assembles that phrase at runtime (MERGE=...) so
# running the suite is not itself blocked.
set -u

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$HERE/_safe_rm.sh"
H="$HERE/../hooks"
T="$(mktemp -d)"; safe_rm_allow "$T"      # the "project" (has/lacks .claude/workflow.json per test)
O="$(mktemp -d)"; safe_rm_allow "$O"      # an unrelated repo
FAKEBIN="$(mktemp -d)"; safe_rm_allow "$FAKEBIN"
git -C "$T" init -q; git -C "$O" init -q; mkdir -p "$T/.claude"
MERGE="gh pr"" merge 42"

# Fake gh: `gh pr checks ...` prints $FAKE_GH_CHECKS and exits $FAKE_GH_RC
# (default 0), or fails with $FAKE_GH_ERR on stderr (exit 1) when that is set.
# $FAKE_GH_SLEEP makes it hang first (exec, so a kill leaves no orphan).
# Anything else exits 1.
cat > "$FAKEBIN/gh" <<'EOF'
#!/usr/bin/env bash
if [ "${1:-}" = "pr" ] && [ "${2:-}" = "checks" ]; then
  [ -n "${FAKE_GH_SLEEP:-}" ] && exec sleep "$FAKE_GH_SLEEP"
  if [ -n "${FAKE_GH_ERR:-}" ]; then echo "$FAKE_GH_ERR" >&2; exit 1; fi
  echo "${FAKE_GH_CHECKS:-[]}"; exit "${FAKE_GH_RC:-0}"
fi
exit 1
EOF
chmod +x "$FAKEBIN/gh"
export PATH="$FAKEBIN:$PATH"

PASS=0; FAIL=0
# run_hook <hook> <project_dir|-> <cwd> <command>  -> sets OUT
run_hook() {
  local payload
  payload=$(python -c 'import json,sys;print(json.dumps({"tool_input":{"command":sys.argv[1]}}))' "$4")
  if [ "$2" = "-" ]; then
    OUT=$(echo "$payload" | (cd "$3" && env -u CLAUDE_PROJECT_DIR bash "$H/$1" 2>&1))
  else
    OUT=$(echo "$payload" | (cd "$3" && CLAUDE_PROJECT_DIR="$2" bash "$H/$1" 2>&1))
  fi
  RC=$?
}
expect_allow() { # label
  if [ -z "$OUT" ]; then PASS=$((PASS+1)); echo "ok    $1"
  else FAIL=$((FAIL+1)); echo "FAIL  $1  (expected allow, got: ${OUT:0:110})"; fi
}
expect_deny() { # label [substring the reason must contain]
  if echo "$OUT" | grep -q '"permissionDecision": "deny"' && { [ -z "${2:-}" ] || echo "$OUT" | grep -qF -- "$2"; }; then
    PASS=$((PASS+1)); echo "ok    $1"
  else FAIL=$((FAIL+1)); echo "FAIL  $1  (expected deny${2:+ containing '$2'}, got: ${OUT:0:110})"; fi
}
marker() { echo "$1" > "$T/.claude/workflow.json"; }
# A malformed marker must be loud (message on stderr, non-zero) but must NOT
# block the command (exit 2 would block; anything else is a non-blocking error).
expect_warn() { # label
  if [ "$RC" -ne 0 ] && [ "$RC" -ne 2 ] && echo "$OUT" | grep -q "could not be read"; then PASS=$((PASS+1)); echo "ok    $1"
  else FAIL=$((FAIL+1)); echo "FAIL  $1  (rc=$RC, expected a non-blocking error naming the problem, got: ${OUT:0:110})"; fi
}

echo "== opt-in gating: no workflow.json means inert"
safe_rm "$T/.claude/workflow.json"
run_hook guard-repo-cwd.sh "$T" "$O" "git commit -m x";        expect_allow "cwd guard inert without marker"
FAKE_GH_CHECKS='[{"name":"ci","bucket":"fail"}]' run_hook block-merge-if-ci-red.sh "$T" "$T" "$MERGE"
                                                               expect_allow "merge gate inert without marker (even with red CI)"
run_hook guard-repo-cwd.sh - "$O" "git commit -m x";           expect_allow "inert when CLAUDE_PROJECT_DIR is unset"

echo "== cwd guard (marker present)"
marker '{"version":1,"components":{}}'
run_hook guard-repo-cwd.sh "$T" "$T" "git commit -m x";        expect_allow "git commit inside the project"
run_hook guard-repo-cwd.sh "$T" "$O" "git commit -m x";        expect_deny  "git commit from a different repo" "Blocked"
run_hook guard-repo-cwd.sh "$T" "$O" "git push origin main";   expect_deny  "git push from a different repo"
run_hook guard-repo-cwd.sh "$T" "$O" "git status";             expect_allow "read-only git elsewhere is fine"
run_hook guard-repo-cwd.sh "$T" "$O" "ls -la";                 expect_allow "non-git command elsewhere"
marker '{"version":1,"components":{"cwd_guard_hook":false}}'
run_hook guard-repo-cwd.sh "$T" "$O" "git commit -m x";        expect_allow "cwd guard switched off per project"

echo "== merge gate (marker present, fake gh)"
marker '{"version":1,"components":{}}'
run_hook block-merge-if-ci-red.sh "$T" "$T" "gh pr view 1";    expect_allow "unrelated gh command ignored"
FAKE_GH_CHECKS='[{"name":"test","bucket":"pass"},{"name":"export","bucket":"pass"}]' \
  run_hook block-merge-if-ci-red.sh "$T" "$T" "$MERGE";        expect_allow "all checks pass"
FAKE_GH_CHECKS='[{"name":"test","bucket":"pass"},{"name":"lint","bucket":"skipping"}]' \
  run_hook block-merge-if-ci-red.sh "$T" "$T" "$MERGE";        expect_allow "pass + skipping is green"
FAKE_GH_CHECKS='[{"name":"test","bucket":"pass"},{"name":"export","bucket":"fail"}]' \
  run_hook block-merge-if-ci-red.sh "$T" "$T" "$MERGE";        expect_deny  "one failing check blocks, and names it" "export: fail"
FAKE_GH_CHECKS='[{"name":"test","bucket":"pending"}]' \
  run_hook block-merge-if-ci-red.sh "$T" "$T" "$MERGE";        expect_deny  "pending CI blocks" "test: pending"
FAKE_GH_CHECKS='[{"name":"test","bucket":"cancel"}]' \
  run_hook block-merge-if-ci-red.sh "$T" "$T" "$MERGE";        expect_deny  "cancelled CI blocks" "test: cancel"
FAKE_GH_ERR='no pull requests found' \
  run_hook block-merge-if-ci-red.sh "$T" "$T" "$MERGE";        expect_deny  "unreadable CI fails closed" "could not read PR checks"
FAKE_GH_CHECKS='not json at all' \
  run_hook block-merge-if-ci-red.sh "$T" "$T" "$MERGE";        expect_deny  "garbage from gh fails closed"
FAKE_GH_CHECKS='[{"name":"test","bucket":"fail"}]' \
  run_hook block-merge-if-ci-red.sh "$T" "$T" "gh pr"" merge 7 --squash"; expect_deny "explicit PR number + flags still gated"
# macOS has no GNU `timeout`; the gate must still work (and still deny red CI)
# through its shell-watchdog fallback. WORKFLOW_HOOKS_NO_TIMEOUT_BIN=1 forces
# that path; every case below runs on both paths where it makes sense.
NOTO=WORKFLOW_HOOKS_NO_TIMEOUT_BIN
for mode in real watchdog; do
  if [ "$mode" = watchdog ]; then export $NOTO=1; else unset $NOTO; fi
  echo "-- $mode path"
  FAKE_GH_CHECKS='[{"name":"test","bucket":"pass"}]'     run_hook block-merge-if-ci-red.sh "$T" "$T" "$MERGE";      expect_allow "$mode: green CI allowed"
  FAKE_GH_CHECKS='[{"name":"test","bucket":"fail"}]'     run_hook block-merge-if-ci-red.sh "$T" "$T" "$MERGE";      expect_deny  "$mode: red CI still blocks" "test: fail"
  FAKE_GH_ERR='no pull requests found'     run_hook block-merge-if-ci-red.sh "$T" "$T" "$MERGE";      expect_deny  "$mode: unreadable CI fails closed, stderr text kept" "no pull requests found"
  # gh failing while its output looks green must not be trusted
  FAKE_GH_RC=1 FAKE_GH_CHECKS='[{"name":"test","bucket":"pass"}]'     run_hook block-merge-if-ci-red.sh "$T" "$T" "$MERGE";      expect_deny  "$mode: non-zero gh exit with green output blocks" "exited with status 1"
  # a gh that dies by itself with 128+ is a failure, not a timeout
  FAKE_GH_RC=130 FAKE_GH_CHECKS='[{"name":"test","bucket":"pass"}]'     run_hook block-merge-if-ci-red.sh "$T" "$T" "$MERGE";      expect_deny  "$mode: gh exit 130 is not reported as a timeout" "exited with status 130"
  # a hung gh: denied with the timeout message, and promptly
  START=$SECONDS
  WORKFLOW_HOOKS_GH_TIMEOUT=1 FAKE_GH_SLEEP=8 FAKE_GH_CHECKS='[{"name":"test","bucket":"pass"}]'     run_hook block-merge-if-ci-red.sh "$T" "$T" "$MERGE";      expect_deny  "$mode: hung gh is denied as timed out" "timed out"
  [ $((SECONDS-START)) -lt 6 ] && { PASS=$((PASS+1)); echo "ok    $mode: hung gh was cut off promptly"; }     || { FAIL=$((FAIL+1)); echo "FAIL  $mode: hung gh took $((SECONDS-START))s (limit was 1s)"; }
  # a quick gh must not wait out the limit (a lingering watchdog sleep would)
  START=$SECONDS
  WORKFLOW_HOOKS_GH_TIMEOUT=30 FAKE_GH_CHECKS='[{"name":"test","bucket":"pass"}]'     run_hook block-merge-if-ci-red.sh "$T" "$T" "$MERGE";      expect_allow "$mode: quick gh with a 30s limit allowed"
  [ $((SECONDS-START)) -lt 15 ] && { PASS=$((PASS+1)); echo "ok    $mode: quick gh returned without waiting out the limit"; }     || { FAIL=$((FAIL+1)); echo "FAIL  $mode: quick gh took $((SECONDS-START))s"; }
done
unset $NOTO

# Which binary gets used: stubs that record their use, then run the command.
STUBS="$(mktemp -d)"; safe_rm_allow "$STUBS"
for b in timeout gtimeout; do
  printf '#!/usr/bin/env bash
echo used >> "%s/%s.used"
shift
exec "$@"
' "$STUBS" "$b" > "$STUBS/$b"; chmod +x "$STUBS/$b"
done
GREEN='[{"name":"test","bucket":"pass"}]'
safe_rm "$STUBS"/*.used
PATH="$STUBS:$PATH" FAKE_GH_CHECKS="$GREEN" run_hook block-merge-if-ci-red.sh "$T" "$T" "$MERGE"
[ -f "$STUBS/timeout.used" ] && [ ! -f "$STUBS/gtimeout.used" ]; chk_path() { if [ "$1" -eq 0 ]; then PASS=$((PASS+1)); echo "ok    $2"; else FAIL=$((FAIL+1)); echo "FAIL  $2"; fi; }
chk_path $? "timeout binary is preferred when present"
safe_rm "$STUBS"/*.used
PATH="$STUBS:$PATH" WORKFLOW_HOOKS_NO_TIMEOUT_BIN=1 FAKE_GH_CHECKS="$GREEN" run_hook block-merge-if-ci-red.sh "$T" "$T" "$MERGE"
[ ! -f "$STUBS/timeout.used" ] && [ ! -f "$STUBS/gtimeout.used" ]
chk_path $? "the env flag overrides both timeout and gtimeout"
safe_rm -r "$STUBS"
marker '{"version":1,"components":{"merge_gate_hook":false}}'
FAKE_GH_CHECKS='[{"name":"test","bucket":"fail"}]' \
  run_hook block-merge-if-ci-red.sh "$T" "$T" "$MERGE";        expect_allow "merge gate switched off per project"

echo "== text that merely MENTIONS a command is not a command (red CI, marker present)"
marker '{"version":1,"components":{}}'
RED='[{"name":"test","bucket":"fail"}]'
M="gh pr"" merge"
export FAKE_GH_CHECKS="$RED"
run_hook block-merge-if-ci-red.sh "$T" "$T" "git commit -m \"fix: $M deny rule\"";        expect_allow "commit message in double quotes"
run_hook block-merge-if-ci-red.sh "$T" "$T" "git commit -m 'fix: $M deny rule'";          expect_allow "commit message in single quotes"
run_hook block-merge-if-ci-red.sh "$T" "$T" "echo '$M 5'";                                expect_allow "echo of the phrase"
run_hook block-merge-if-ci-red.sh "$T" "$T" "grep -rn \"$M\" docs/";                      expect_allow "grep pattern"
run_hook block-merge-if-ci-red.sh "$T" "$T" $'git commit -F - <<\'EOF\'\nsubject\n\nbody says '"$M"$' 5\nEOF'; expect_allow "heredoc body fed to git"
run_hook block-merge-if-ci-red.sh "$T" "$T" "gh pr create --title t --body \"closes the $M gap\""; expect_allow "PR body mentioning it"

echo "== real invocations are still caught, however they are wrapped"
run_hook block-merge-if-ci-red.sh "$T" "$T" "echo hi; $M 5";                              expect_deny "after a semicolon"
run_hook block-merge-if-ci-red.sh "$T" "$T" "git commit -m \"x $M y\" && $M 5";           expect_deny "real merge after a harmless quoted mention"
run_hook block-merge-if-ci-red.sh "$T" "$T" "bash -c \"$M 5\"";                           expect_deny "inside bash -c"
run_hook block-merge-if-ci-red.sh "$T" "$T" "sh -c '$M 5'";                               expect_deny "inside sh -c with single quotes"
run_hook block-merge-if-ci-red.sh "$T" "$T" "eval '$M 5'";                                expect_deny "inside eval"
run_hook block-merge-if-ci-red.sh "$T" "$T" "echo \"\$($M 5)\"";                          expect_deny "command substitution in double quotes"
run_hook block-merge-if-ci-red.sh "$T" "$T" "echo \`$M 5\`";                              expect_deny "backtick substitution"
run_hook block-merge-if-ci-red.sh "$T" "$T" $'bash <<\'EOF\'\n'"$M"$' 5\nEOF';            expect_deny "heredoc executed by bash"
run_hook block-merge-if-ci-red.sh "$T" "$T" "echo \"oops $M 5";                           expect_deny "unterminated quote fails safe"
unset FAKE_GH_CHECKS

echo "== same rule for the cwd guard (run from a different repo)"
run_hook guard-repo-cwd.sh "$T" "$O" 'echo "git commit -m x"';                             expect_allow "echo mentioning git commit"
run_hook guard-repo-cwd.sh "$T" "$O" 'grep "git push" notes.txt';                          expect_allow "grep for git push"
run_hook guard-repo-cwd.sh "$T" "$O" 'gh pr create --body "then git push the branch"';     expect_allow "PR body mentioning git push"
run_hook guard-repo-cwd.sh "$T" "$O" 'git commit -m "mentions git push in its message"';  expect_deny  "real commit with a mention in the message"
run_hook guard-repo-cwd.sh "$T" "$O" 'bash -c "git push origin main"';                     expect_deny  "git push inside bash -c"

echo "== marker lookup: subfolders count, directories above the repo do not"
marker '{"version":1,"components":{}}'
mkdir -p "$T/sub/deeper"
run_hook guard-repo-cwd.sh "$T/sub/deeper" "$O" "git commit -m x";   expect_deny  "session started in a subfolder of an opted-in repo is still protected" "Blocked"
OUTER="$(mktemp -d)"; safe_rm_allow "$OUTER"; mkdir -p "$OUTER/.claude" "$OUTER/inner"; echo '{"version":1,"components":{}}' > "$OUTER/.claude/workflow.json"; git -C "$OUTER/inner" init -q
run_hook guard-repo-cwd.sh "$OUTER/inner" "$O" "git commit -m x";    expect_allow "a marker in a directory ABOVE the repo root is ignored"

echo "== a malformed marker is loud, and does not block"
echo '{ "components": ' > "$T/.claude/workflow.json"
run_hook guard-repo-cwd.sh "$T" "$O" "git commit -m x";              expect_warn  "cwd guard: malformed marker reports itself"
run_hook block-merge-if-ci-red.sh "$T" "$T" "$MERGE";                expect_warn  "merge gate: malformed marker reports itself"
run_hook guard-repo-cwd.sh "$T" "$O" "ls";                           expect_warn  "reported even on an unrelated command (so it is noticed early)"
marker '{"version":1,"components":{}}'
run_hook guard-repo-cwd.sh "$T" "$O" "git commit -m x";              expect_deny  "fixing the file restores protection" "Blocked"

echo "== session-start nudge: a project behind the plugin is told, every session, and nothing is changed"
NUDGE=session-start-nudge.sh
expect_nudge() { # label [substring the message must contain]
  if echo "$OUT" | python -c '
import sys, json
d = json.loads(sys.stdin.read())
assert d["hookSpecificOutput"]["hookEventName"] == "SessionStart"
assert d["systemMessage"].startswith("audaxtech-workflow: in this project,"), d["systemMessage"]
assert "upgrade mode" in d["systemMessage"] and "setup_nudge_hook" in d["systemMessage"]
assert "unasked" in d["hookSpecificOutput"]["additionalContext"]
assert sys.argv[1] in d["systemMessage"], d["systemMessage"]' "${2:-}" 2>/dev/null && [ "$RC" -eq 0 ]; then
    PASS=$((PASS+1)); echo "ok    $1"
  else FAIL=$((FAIL+1)); echo "FAIL  $1  (rc=$RC, expected one SessionStart JSON message${2:+ containing '$2'}, got: ${OUT:0:160})"; fi
}
expect_quiet() { # label: no output at all and a clean exit
  if [ -z "$OUT" ] && [ "$RC" -eq 0 ]; then PASS=$((PASS+1)); echo "ok    $1"
  else FAIL=$((FAIL+1)); echo "FAIL  $1  (rc=$RC, expected silence, got: ${OUT:0:160})"; fi
}
# A kind:tool project with every piece the upgrade check looks for, so the check reports nothing.
P="$(mktemp -d)"; safe_rm_allow "$P"
fresh() {
  safe_rm -r "$P"; mkdir -p "$P/.claude" "$P/docs" "$P/.github/ISSUE_TEMPLATE" "$P/.github/workflows"
  git -C "$P" init -q
  for f in CONTRIBUTING.md AGENTS.md docs/DECISIONS.md .github/PULL_REQUEST_TEMPLATE.md .github/workflows/ci.yml .gitattributes .editorconfig; do echo x > "$P/$f"; done
  echo "@AGENTS.md" > "$P/CLAUDE.md"
  for f in feature bug_report chore research; do echo x > "$P/.github/ISSUE_TEMPLATE/$f.yml"; done
  echo '{"version":1,"kind":"tool"}' > "$P/.claude/workflow.json"
}
snap() { (cd "$1" && find . -type f -not -path './.git/*' | sort | xargs cksum); }

fresh;                                                          run_hook "$NUDGE" "$P" "$P" "-"; expect_quiet "a project that is up to date: silent"
safe_rm "$P/.claude/workflow.json"; safe_rm "$P/.editorconfig"; run_hook "$NUDGE" "$P" "$P" "-"; expect_quiet "no marker: silent, even with pieces missing"
fresh; safe_rm "$P/.editorconfig"
run_hook "$NUDGE" "$P" "$P" "-";                                expect_nudge "one missing piece: nudged, naming it" "1 thing differs"
echo "$OUT" | grep -q '.editorconfig \[file\]'; chk_rc=$?
[ $chk_rc -eq 0 ] && { PASS=$((PASS+1)); echo "ok    and the message names the file and its type"; } || { FAIL=$((FAIL+1)); echo "FAIL  the message names the file and its type (${OUT:0:160})"; }
FIRST="$OUT"; run_hook "$NUDGE" "$P" "$P" "-"
[ "$OUT" = "$FIRST" ] && [ -n "$OUT" ] && { PASS=$((PASS+1)); echo "ok    the next session says the same thing again (it nags until fixed)"; } || { FAIL=$((FAIL+1)); echo "FAIL  the next session says the same thing again"; }
echo x > "$P/.editorconfig"
run_hook "$NUDGE" "$P" "$P" "-";                                expect_quiet "once the piece is added, silent"
fresh; safe_rm "$P/CLAUDE.md"
run_hook "$NUDGE" "$P" "$P" "-";                                expect_nudge "AGENTS.md without its CLAUDE.md stub is reported" "CLAUDE.md [file]"
fresh; safe_rm "$P/AGENTS.md"; echo "- be careful" > "$P/CLAUDE.md"
run_hook "$NUDGE" "$P" "$P" "-";                                expect_nudge "a CLAUDE.md-only repo is reported as a migration" "AGENTS.md [migration]"
fresh; safe_rm "$P/.editorconfig" "$P/.gitattributes" "$P/docs/DECISIONS.md" "$P/CONTRIBUTING.md"
run_hook "$NUDGE" "$P" "$P" "-";                                expect_nudge "four missing pieces: counted, three named, the rest counted" "4 things differ"
echo "$OUT" | grep -q 'and 1 more'; [ $? -eq 0 ] && { PASS=$((PASS+1)); echo "ok    and the fourth is summarised as 'and 1 more'"; } || { FAIL=$((FAIL+1)); echo "FAIL  'and 1 more' (${OUT:0:200})"; }
fresh; mkdir -p "$P/.claude"
echo '{"hooks":{"PreToolUse":[{"matcher":"Bash","hooks":[{"type":"command","command":"bash tools/hooks/block-merge-if-ci-red.sh"}]}]}}' > "$P/.claude/settings.json"
run_hook "$NUDGE" "$P" "$P" "-";                                expect_nudge "an old project copy of the merge gate is reported even when nothing is missing" "old merge-gate hook"
fresh; mkdir -p "$P/.claude/skills/pr-check"; echo x > "$P/.claude/skills/pr-check/SKILL.md"
run_hook "$NUDGE" "$P" "$P" "-";                                expect_nudge "a project skill shadowing pr-check is reported" "shadows the plugin's pr-check"
fresh; printf 'on:\n  pull_request:\njobs:\n  t:\n    runs-on: macos-latest\n' > "$P/.github/workflows/ci.yml"
run_hook "$NUDGE" "$P" "$P" "-";                                expect_nudge "macOS on every PR is reported" "macOS on every PR"
fresh; safe_rm "$P/.editorconfig"; echo '{"version":1,"kind":"tool","components":{"setup_nudge_hook":false}}' > "$P/.claude/workflow.json"
run_hook "$NUDGE" "$P" "$P" "-";                                expect_quiet "components.setup_nudge_hook false: silent even when behind"
echo '{"version":1,"kind":"tool","components":{"merge_gate_hook":false,"cwd_guard_hook":false}}' > "$P/.claude/workflow.json"
run_hook "$NUDGE" "$P" "$P" "-";                                expect_nudge "the other hooks switched off do not silence it" ".editorconfig"
echo '{"version":1,"kind":"tool","components":{"ci":false,"decisions_log":false,"issue_and_pr_templates":false}}' > "$P/.claude/workflow.json"
safe_rm -r "$P/.github" "$P/docs"
run_hook "$NUDGE" "$P" "$P" "-";                                expect_nudge "components the project switched off are not reported (only the missing .editorconfig is)" "1 thing differs"
echo '{ "components": ' > "$P/.claude/workflow.json"
run_hook "$NUDGE" "$P" "$P" "-";                                expect_quiet "malformed marker: silent, exit 0 (the PreToolUse hooks report it)"
fresh; safe_rm "$P/.editorconfig"
run_hook "$NUDGE" - "$P" "-";                                   expect_quiet "CLAUDE_PROJECT_DIR unset: silent"
mkdir -p "$P/sub/dir"
run_hook "$NUDGE" "$P/sub/dir" "$P/sub/dir" "-";                expect_nudge "a session started in a subfolder checks the repo root" ".editorconfig"
before="$(snap "$P")"; run_hook "$NUDGE" "$P" "$P" "-"; run_hook "$NUDGE" "$P" "$P" "-"
[ "$(snap "$P")" = "$before" ] && [ -z "$(git -C "$P" status --porcelain --untracked-files=no)" ] && { PASS=$((PASS+1)); echo "ok    running the nudge changes no file"; } || { FAIL=$((FAIL+1)); echo "FAIL  running the nudge changes no file"; }

# A copy of the hook next to a stand-in upgrade check: whatever it does, the session must not be disturbed.
HC="$(mktemp -d)"; safe_rm_allow "$HC"; mkdir -p "$HC/hooks" "$HC/skills/project-bootstrap/scripts"
cp "$H/session-start-nudge.sh" "$H/_setup_nudge.py" "$H/_project_enabled.py" "$HC/hooks/"
H_SAVE="$H"; H="$HC/hooks"; STUB="$HC/skills/project-bootstrap/scripts/upgrade_check.py"
fresh
run_hook "$NUDGE" "$P" "$P" "-";                                expect_quiet "the upgrade check is not there: silent"
printf 'import sys\nsys.exit(1)\n' > "$STUB"
run_hook "$NUDGE" "$P" "$P" "-";                                expect_quiet "the upgrade check exits non-zero: silent"
printf 'print("not json")\n' > "$STUB"
run_hook "$NUDGE" "$P" "$P" "-";                                expect_quiet "the upgrade check prints something that is not JSON: silent"
printf 'print("[1, 2]")\n' > "$STUB"
run_hook "$NUDGE" "$P" "$P" "-";                                expect_quiet "the upgrade check prints JSON that is not an object: silent"
printf 'print("{\\"missing\\": [5, null]}")\n' > "$STUB"
run_hook "$NUDGE" "$P" "$P" "-";                                expect_quiet "items of an unexpected shape: silent, no crash"
printf 'print("{\\"missing\\": []}")\n' > "$STUB"
run_hook "$NUDGE" "$P" "$P" "-";                                expect_quiet "a report with nothing in it: silent"
printf 'import json\nprint(json.dumps({"missing": [{"path": "f%%d" %% i, "type": "file"} for i in range(5)]}))\n' > "$STUB"
run_hook "$NUDGE" "$P" "$P" "-";                                expect_nudge "five items: counted, three named" "5 things differ"
echo "$OUT" | grep -q 'f0 \[file\], f1 \[file\], f2 \[file\] and 2 more'; [ $? -eq 0 ] && { PASS=$((PASS+1)); echo "ok    and the other two are summarised as 'and 2 more'"; } || { FAIL=$((FAIL+1)); echo "FAIL  'and 2 more' (${OUT:0:240})"; }
printf 'import time\ntime.sleep(30)\n' > "$STUB"
start=$SECONDS; AUDAXTECH_NUDGE_TIMEOUT=1 run_hook "$NUDGE" "$P" "$P" "-"; took=$((SECONDS-start))
expect_quiet "an upgrade check that hangs is cut off: silent"
[ "$took" -lt 15 ] && { PASS=$((PASS+1)); echo "ok    and the session start is held up for about a second, not 30 (took ${took}s)"; } || { FAIL=$((FAIL+1)); echo "FAIL  the hang is cut off in time (took ${took}s)"; }
H="$H_SAVE"

echo "== the hook is registered for session start only"
python -c '
import json, sys
h = json.load(open(sys.argv[1]))["hooks"]
ss = h["SessionStart"]
assert [g["matcher"] for g in ss] == ["startup"], ss
cmds = [x["command"] for g in ss for x in g["hooks"]]
assert cmds == ["bash \"${CLAUDE_PLUGIN_ROOT}/hooks/session-start-nudge.sh\""], cmds
assert "PreToolUse" in h and "session-start-nudge" not in json.dumps(h["PreToolUse"])' "$H/hooks.json"
if [ $? -eq 0 ]; then PASS=$((PASS+1)); echo "ok    hooks.json: SessionStart on startup only, and the PreToolUse hooks are unchanged"
else FAIL=$((FAIL+1)); echo "FAIL  hooks.json registration"; fi

safe_rm -r "$T" "$O" "$FAKEBIN" "$OUTER" "$HC" "$P"
echo; echo "passed: $PASS   failed: $FAIL"
[ "$FAIL" -eq 0 ]
