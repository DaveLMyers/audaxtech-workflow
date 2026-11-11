#!/usr/bin/env bash
# SessionStart hook (matcher: startup) - tells the owner, in one line, when this project is
# behind the installed plugin's setup, and changes nothing.
#
# Failure mode this prevents: `claude plugin update` swaps the plugin's files and nothing
# else, so a project set up by an older version keeps working and says nothing, and the owner
# has to remember to ask for upgrade mode after every release. This is the "migrations are
# pending" notice: it runs the read-only upgrade check each session and speaks only when the
# check finds something, so it repeats until the project is upgraded or the hook is switched
# off (components.setup_nudge_hook). The migration itself stays an explicit, approved step.
# Shipped by the audaxtech-workflow plugin; active only in projects with .claude/workflow.json.
#
# Always exits 0 and prints nothing when there is nothing to say. A malformed marker is
# already reported by the PreToolUse hooks, so it is not repeated here.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Inert unless this project opted in (see _project_enabled.py) and has not switched it off.
gate_rc=0
python "$SCRIPT_DIR/_project_enabled.py" setup_nudge_hook 2>/dev/null || gate_rc=$?
[ "$gate_rc" -eq 0 ] || exit 0

python "$SCRIPT_DIR/_setup_nudge.py" 2>/dev/null || true
exit 0
