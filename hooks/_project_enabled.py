#!/usr/bin/env python
# Shared gate for the plugin's hooks. Exit 0 = this hook should run for the
# current project; exit 1 = do nothing.
#
# The plugin is enabled globally, but its hooks must only act in projects
# that opted in by having .claude/workflow.json (written by project-bootstrap).
# Anywhere else the hooks are inert - a repo with no CI, say, must not have
# every `gh pr merge` denied because no checks can be read.
#
# Usage: _project_enabled.py <component-key>   (e.g. merge_gate_hook)
# Project root comes from CLAUDE_PROJECT_DIR (the session's project, NOT the
# shell's cwd - cwd is exactly what the cwd guard exists to distrust).
# Unset/missing/unreadable config => disabled (fail open, never block work
# in a project that didn't ask for this).
import json
import os
import sys


def main():
    root = os.environ.get("CLAUDE_PROJECT_DIR", "")
    if not root or len(sys.argv) != 2:
        sys.exit(1)
    path = os.path.join(root, ".claude", "workflow.json")
    try:
        with open(path, encoding="utf-8") as f:
            cfg = json.load(f)
    except Exception:
        sys.exit(1)
    if cfg.get("components", {}).get(sys.argv[1], True) is False:
        sys.exit(1)
    sys.exit(0)


if __name__ == "__main__":
    main()
