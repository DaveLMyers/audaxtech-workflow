#!/usr/bin/env python
# SessionStart helper: say, every session, that this project is behind the installed plugin's
# setup, until it is brought up to date or the hook is switched off for the project. It runs the
# read-only upgrade check (skills/project-bootstrap/scripts/upgrade_check.py) and prints one line
# when the check finds something. It never edits a file, and it never fails the session: every
# problem (no marker, a marker with no kind, a check that crashes or hangs, output it cannot read) ends in a
# silent exit 0.
#
# "Behind" means the check reports at least one item: a missing piece, an old project copy of the
# plugin's hooks, a project skill that shadows a plugin skill, or macOS CI on every PR. A release
# that adds a template or a check is therefore reported in every project that lacks it, and a
# release that changes nothing a project needs says nothing. There is no version or counter to keep.
#
# The caller (session-start-nudge.sh) has already checked that the project opted in and has
# not switched this hook off (components.setup_nudge_hook), via _project_enabled.py.
import json
import math
import os
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from _project_enabled import find_marker  # noqa: E402  (same folder; the path line above must come first)

CHECK = os.path.join(HERE, os.pardir, "skills", "project-bootstrap", "scripts", "upgrade_check.py")
SHOWN = 3  # how many items to name in the one line
ASK = ("Ask for upgrade mode to see what is different (read-only until you approve), or set "
       "components.setup_nudge_hook to false in .claude/workflow.json to stop this notice.")


DEFAULT_TIMEOUT = 10.0


def timeout_seconds():
    """AUDAXTECH_NUDGE_TIMEOUT in seconds; anything that is not a finite number above zero falls back to the default."""
    try:
        t = float(os.environ.get("AUDAXTECH_NUDGE_TIMEOUT", ""))
    except ValueError:
        return DEFAULT_TIMEOUT
    return t if math.isfinite(t) and t > 0 else DEFAULT_TIMEOUT


def items_of(report):
    """One short label per thing the check found, in report order."""
    labels = []
    for m in report.get("missing", []):
        labels.append("%s [%s]" % (m.get("path", "?"), m.get("type", "?")))
    oh = report.get("old_hooks") or {}
    for h in oh.get("settings", []):
        labels.append("%s [old %s hook]" % (h.get("file", "?"), h.get("hook", "?")))
    for f in oh.get("files", []):
        labels.append("%s [old %s hook]" % (f.get("path", "?"), f.get("hook", "?")))
    for s in report.get("shadowing_skills", []):
        labels.append("%s [shadows the plugin's %s]" % (s.get("path", "?"), s.get("skill", "?")))
    for p in report.get("macos_every_pr", []):
        labels.append("%s [macOS on every PR]" % p)
    return labels


def build_output(labels):
    n = len(labels)
    named = ", ".join(labels[:SHOWN]) + (" and %d more" % (n - SHOWN) if n > SHOWN else "")
    what = "%d thing%s differ%s from what the installed plugin sets up (%s)" % (
        n, "" if n == 1 else "s", "s" if n == 1 else "", named)
    return {
        "systemMessage": "audaxtech-workflow: in this project, %s. %s" % (what, ASK),
        "hookSpecificOutput": {
            "hookEventName": "SessionStart",
            "additionalContext": (
                "The audaxtech-workflow plugin's read-only check reports that in this project, %s. Tell the "
                "owner once, in a sentence, at a natural point, and offer the project-bootstrap skill's "
                "upgrade mode (its first step is the same read-only report). Do not run the upgrade or "
                "edit any file unasked." % what
            ),
        },
    }


def main():
    root = os.environ.get("CLAUDE_PROJECT_DIR", "")
    if not root:
        return
    marker = find_marker(root)
    if marker is None:
        return
    repo = os.path.dirname(os.path.dirname(marker))  # <repo>/.claude/workflow.json
    proc = subprocess.run(
        [sys.executable, "-I", CHECK, repo, "--json"],
        stdin=subprocess.DEVNULL, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL,
        timeout=timeout_seconds(),
    )
    if proc.returncode != 0:
        return
    report = json.loads(proc.stdout.decode("utf-8", "replace"))
    if not isinstance(report, dict):
        return
    # A marker with no kind makes the check assume `game` and list game docs the project may not want:
    # a guess is not worth a notice every session.
    if str(report.get("kind_source", "")).startswith("assumed"):
        return
    labels = items_of(report)
    if labels:
        sys.stdout.write(json.dumps(build_output(labels)) + "\n")


if __name__ == "__main__":
    try:
        main()
    except Exception:  # a nudge is never worth a failed session start (this includes a timeout)
        pass
    sys.exit(0)
