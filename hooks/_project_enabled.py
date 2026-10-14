#!/usr/bin/env python
# Shared gate for the plugin's hooks.
#
# Exit codes:
#   0  this hook should run for the current project
#   1  do nothing (no marker, component switched off, or no project dir)
#   3  the marker exists but cannot be read: stderr says why. The calling hook
#      exits non-zero with that message so it is visible, instead of silently
#      leaving the project unprotected. (It still does not block the command.)
#
# The plugin is enabled globally, but its hooks must only act in projects that
# opted in by having .claude/workflow.json (written by project-bootstrap).
# Anywhere else the hooks are inert - a repo with no CI, say, must not have
# every PR merge denied because no checks can be read.
#
# Usage: _project_enabled.py <component-key>   (e.g. merge_gate_hook)
#
# Where the marker is looked for: CLAUDE_PROJECT_DIR (the session's project,
# NOT the shell's cwd - cwd is exactly what the cwd guard exists to distrust),
# then each parent directory up to and including the first one that contains
# .git. That way a session started in a subfolder of an opted-in repo is still
# protected, while a marker in some unrelated directory above the repo is
# never picked up.
import json
import os
import sys


def find_marker(start):
    d = os.path.abspath(start)
    while True:
        candidate = os.path.join(d, ".claude", "workflow.json")
        if os.path.isfile(candidate):
            return candidate
        if os.path.exists(os.path.join(d, ".git")):
            return None  # reached the repo root without finding one
        parent = os.path.dirname(d)
        if parent == d:
            return None
        d = parent


def main():
    root = os.environ.get("CLAUDE_PROJECT_DIR", "")
    if not root or len(sys.argv) != 2:
        sys.exit(1)
    path = find_marker(root)
    if path is None:
        sys.exit(1)
    try:
        with open(path, encoding="utf-8") as f:
            cfg = json.load(f)
    except Exception as e:  # unreadable or malformed marker
        sys.stderr.write(
            "audaxtech-workflow: %s exists but could not be read (%s). "
            "Its hooks (merge gate, cwd guard) are OFF for this project until "
            "that file is valid JSON.\n" % (path, e)
        )
        sys.exit(3)
    if not isinstance(cfg, dict) or cfg.get("components", {}).get(sys.argv[1], True) is False:
        sys.exit(1)
    sys.exit(0)


if __name__ == "__main__":
    main()
