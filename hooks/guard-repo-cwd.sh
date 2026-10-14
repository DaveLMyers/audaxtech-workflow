#!/usr/bin/env bash
# PreToolUse hook (matcher: Bash) - blocks git-mutating commands that would
# run outside this project's repo.
#
# Failure mode this prevents: a `cd` into a sibling repo (for a quick
# cross-repo read) left unreverted before a later bare git command, which
# then silently runs against the OTHER repo - git resolves from cwd, not
# intent. Reads stdin hook-input JSON, and if the Bash command is a git
# subcommand that mutates repo/branch state, denies it unless the working
# directory resolves to the session's project (CLAUDE_PROJECT_DIR). Shipped by
# the audaxtech-workflow plugin; active only in projects with .claude/workflow.json.
#
# Uses `python` for JSON output; no jq dependency.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Inert unless this project opted in (see _project_enabled.py).
gate_rc=0
python "$SCRIPT_DIR/_project_enabled.py" cwd_guard_hook || gate_rc=$?
case "$gate_rc" in
  0) ;;            # opted in: carry on
  3) exit 1 ;;     # marker unreadable: visible (non-blocking) hook error, message already on stderr
  *) exit 0 ;;     # not opted in / switched off: stay inert
esac

# The project root is the session's, not this script's (the script lives in
# the plugin). Resolved via `git -C`, not the raw env value, so it matches the
# path style `git rev-parse --show-toplevel` returns below - on Windows Git
# Bash, /e/... and E:/... never compare equal for the same directory.
EXPECTED_ROOT="$(git -C "$CLAUDE_PROJECT_DIR" rev-parse --show-toplevel 2>/dev/null || true)"
# Not a git project (or can't tell): nothing to guard.
[ -n "$EXPECTED_ROOT" ] || exit 0

export HOOK_INPUT="$(cat)"

# Cheap pre-filter on the raw payload before paying for a python startup:
# skip straight out for the common case of a Bash call that isn't a git
# command at all.
if ! printf '%s' "$HOOK_INPUT" | grep -qE 'checkout|commit|push|branch|merge|reset|rebase|tag|cherry-pick|revert'; then
  exit 0
fi

COMMAND="$(printf '%s' "$HOOK_INPUT" | python "$SCRIPT_DIR/_extract_command.py")"

if ! printf '%s' "$COMMAND" | grep -qE '(^|[;&|[:space:]])git[[:space:]]+(checkout[[:space:]]+-b|commit|push|branch[[:space:]]+-[dD]|merge|reset|rebase|tag|cherry-pick|revert)([[:space:]]|$)'; then
  exit 0
fi

TOPLEVEL="$(git rev-parse --show-toplevel 2>/dev/null || true)"

if [ -z "$TOPLEVEL" ] || [ "$TOPLEVEL" != "$EXPECTED_ROOT" ]; then
  export TOPLEVEL EXPECTED_ROOT
  python -c '
import os, json
toplevel = os.environ.get("TOPLEVEL") or "an unresolved directory"
expected = os.environ["EXPECTED_ROOT"]
reason = (
    "Blocked: this git command would run in \x27" + toplevel + "\x27, not "
    + expected + ". This usually means a prior cd into a sibling repo "
    "was never reverted before this command. cd "
    "back to " + expected + ", or bundle a one-off cross-repo command with "
    "its own cd in a single call instead of leaving cwd changed across calls."
)
print(json.dumps({
    "hookSpecificOutput": {
        "hookEventName": "PreToolUse",
        "permissionDecision": "deny",
        "permissionDecisionReason": reason,
    }
}))
'
fi

exit 0
