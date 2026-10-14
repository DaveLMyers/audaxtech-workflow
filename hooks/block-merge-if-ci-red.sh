#!/usr/bin/env bash
# PreToolUse hook (matcher: Bash) - blocks `gh pr merge` unless CI is green.
# Shipped by the audaxtech-workflow plugin; active only in projects with
# .claude/workflow.json.
#
# The pr-check skill already says CI
# failing is a manual "don't merge," but that only holds if whoever's
# driving remembers to check. This makes it enforced instead of remembered:
# reads stdin hook-input JSON, and if the Bash command actually invokes
# `gh pr merge`, denies the tool call unless every check is pass/skipping.
#
# Uses `python` for JSON in/out (safer than hand-escaping in bash); no jq
# dependency, since jq isn't guaranteed to be on PATH here.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Inert unless this project opted in (see _project_enabled.py).
gate_rc=0
python "$SCRIPT_DIR/_project_enabled.py" merge_gate_hook || gate_rc=$?
case "$gate_rc" in
  0) ;;            # opted in: carry on
  3) exit 1 ;;     # marker unreadable: visible (non-blocking) hook error, message already on stderr
  *) exit 0 ;;     # not opted in / switched off: stay inert
esac

export HOOK_INPUT="$(cat)"

# Cheap pre-filter on the raw payload before paying for a python startup:
# skip straight out for the common case of a Bash call that isn't a merge.
if ! printf '%s' "$HOOK_INPUT" | grep -q 'merge'; then
  exit 0
fi

COMMAND="$(printf '%s' "$HOOK_INPUT" | python "$SCRIPT_DIR/_extract_command.py")"

# Only act on commands that actually invoke `gh pr merge` - not unrelated
# gh/git commands, and not merely mentioning the phrase.
if ! printf '%s' "$COMMAND" | grep -qE '(^|[;&|[:space:]])gh[[:space:]]+pr[[:space:]]+merge([[:space:]]|$)'; then
  exit 0
fi

deny() {
  export DENY_REASON="$1"
  python -c '
import os, json
print(json.dumps({
    "hookSpecificOutput": {
        "hookEventName": "PreToolUse",
        "permissionDecision": "deny",
        "permissionDecisionReason": os.environ["DENY_REASON"],
    }
}))
'
}

# Pull an explicit PR number/URL/branch off the merge command, if given -
# `gh pr checks` needs one when the command isn't merging the PR for the
# current branch (e.g. `gh pr merge 42`).
TARGET="$(printf '%s' "$COMMAND" | grep -oE 'gh[[:space:]]+pr[[:space:]]+merge[[:space:]]+[^[:space:]-][^[:space:]]*' | awk '{print $NF}' || true)"

# `timeout` bounds the gh call itself, inside this hook's own settings.json
# timeout budget, so a hung/slow `gh pr checks` fails this script closed
# (an explicit deny below) rather than racing an external hook-timeout
# whose allow-vs-deny behavior on expiry isn't guaranteed.
#
# GNU `timeout` is missing on stock macOS (and `gtimeout` only exists with
# Homebrew coreutils), where a bare `timeout` call would fail and make this
# gate deny every merge. So fall back to a small shell watchdog with the same
# contract: merged stdout+stderr, the command's exit code, 124 on timeout.
# WORKFLOW_HOOKS_NO_TIMEOUT_BIN=1 forces the fallback (used by the tests).
run_with_timeout() {
  local secs="$1"; shift
  if [ -z "${WORKFLOW_HOOKS_NO_TIMEOUT_BIN:-}" ] && command -v timeout >/dev/null 2>&1; then
    timeout "${secs}s" "$@"
  elif [ -z "${WORKFLOW_HOOKS_NO_TIMEOUT_BIN:-}" ] && command -v gtimeout >/dev/null 2>&1; then
    gtimeout "${secs}s" "$@"
  else
    local out flag pid wd rc
    out="$(mktemp)"; flag="$out.timedout"
    "$@" >"$out" 2>&1 &
    pid=$!
    # TERM at the deadline, KILL two seconds later if it is still there. The
    # flag file is how we know the watchdog fired, so a command that exits 128+
    # on its own is not mistaken for a timeout.
    ( sleep "$secs"; : >"$flag"; kill "$pid" 2>/dev/null; sleep 2; kill -9 "$pid" 2>/dev/null ) >/dev/null 2>&1 &
    wd=$!
    wait "$pid"; rc=$?
    kill "$wd" 2>/dev/null
    cat "$out"
    if [ -e "$flag" ]; then rc=124; fi
    rm -f "$out" "$flag"
    return "$rc"
  fi
}

# WORKFLOW_HOOKS_GH_TIMEOUT overrides the 20s limit (used by the tests).
GH_TIMEOUT="${WORKFLOW_HOOKS_GH_TIMEOUT:-20}"
if [ -n "$TARGET" ]; then
  CHECKS_RAW="$(run_with_timeout "$GH_TIMEOUT" gh pr checks "$TARGET" --json name,bucket 2>&1)" && GH_RC=0 || GH_RC=$?
else
  CHECKS_RAW="$(run_with_timeout "$GH_TIMEOUT" gh pr checks --json name,bucket 2>&1)" && GH_RC=0 || GH_RC=$?
fi

if [ "$GH_RC" -eq 124 ]; then
  deny "Blocked gh pr merge: gh pr checks timed out reading PR status. Retry once network/gh is responsive, or ask the user to confirm merging anyway."
  exit 0
fi

export CHECKS_RAW GH_RC

python -c '
import os, json

raw = os.environ.get("CHECKS_RAW", "")

try:
    checks = json.loads(raw)
except Exception:
    print(json.dumps({
        "hookSpecificOutput": {
            "hookEventName": "PreToolUse",
            "permissionDecision": "deny",
            "permissionDecisionReason": "Blocked gh pr merge: could not read PR checks via gh pr checks (" + raw.strip()[:300] + "). Resolve that first, or ask the user to confirm merging anyway.",
        }
    }))
    raise SystemExit

bad = [c for c in checks if c.get("bucket") not in ("pass", "skipping")]
if not bad and os.environ.get("GH_RC", "0") != "0":
    # gh failed yet reported nothing wrong: do not trust the output.
    print(json.dumps({
        "hookSpecificOutput": {
            "hookEventName": "PreToolUse",
            "permissionDecision": "deny",
            "permissionDecisionReason": "Blocked gh pr merge: gh pr checks exited with status " + os.environ["GH_RC"] + " although it reported no failing check, so the result cannot be trusted. Resolve that first, or ask the user to confirm merging anyway.",
        }
    }))
    raise SystemExit
if bad:
    summary = ", ".join(c.get("name", "?") + ": " + c.get("bucket", "?") for c in bad)
    print(json.dumps({
        "hookSpecificOutput": {
            "hookEventName": "PreToolUse",
            "permissionDecision": "deny",
            "permissionDecisionReason": "Blocked gh pr merge: CI is not green. Checks: " + summary + ". Get CI green (see the pr-check skill, if this project has one) before merging, or ask the user to confirm merging anyway.",
        }
    }))
'

exit 0
