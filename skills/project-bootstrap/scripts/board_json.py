#!/usr/bin/env python
"""Turn `gh project field-list --format json` into the `board` block of .claude/workflow.json.

Usage: gh project field-list N --owner O --format json | board_json.py <owner> <number> <project_id>

The block is keyed by ROLE (backlog, ready, in_progress, in_review, done), not by
display name, so skills can say "move to in_progress" even if a project renames the
column. work-issue's board_status.py reads exactly this shape.
"""
import json
import sys

ROLES = {"Backlog": "backlog", "Ready": "ready", "In Progress": "in_progress",
         "In Review": "in_review", "Done": "done"}


def build(fields, owner, number, project_id):
    by_name = {f["name"]: f for f in fields}
    status, priority = by_name["Status"], by_name.get("Priority")
    board = {
        "enabled": True,
        "owner": owner,
        "number": int(number),
        "project_id": project_id,
        "url": "https://github.com/users/%s/projects/%s" % (owner, number),
        "columns": {role: name for name, role in ROLES.items()},
        "fields": {
            "status": {"id": status["id"],
                       "options": {ROLES[o["name"]]: o["id"] for o in status.get("options", []) if o["name"] in ROLES}},
        },
    }
    if priority:
        board["fields"]["priority"] = {"id": priority["id"],
                                       "options": {o["name"]: o["id"] for o in priority.get("options", [])}}
    missing = [r for r in ROLES.values() if r not in board["fields"]["status"]["options"]]
    if missing:
        raise SystemExit("board_json: Status field has no option for: %s (columns renamed or missing?)" % ", ".join(missing))
    return board


if __name__ == "__main__":
    if len(sys.argv) != 4:
        raise SystemExit(__doc__)
    print(json.dumps(build(json.load(sys.stdin)["fields"], *sys.argv[1:4]), indent=2))
