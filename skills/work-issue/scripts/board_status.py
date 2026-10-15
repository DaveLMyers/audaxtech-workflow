#!/usr/bin/env python
"""Read or set an issue's Status on the project's GitHub Projects v2 board.

Usage:
  board_status.py <issue-number> <role>            set Status to a role
  board_status.py <issue-number> --read            print the current Status
  options: --repo PATH|owner/name
               PATH  = the project's folder: the script reads its .claude/workflow.json
                       and asks git/gh from there, so it works from any directory.
                       owner/name = the GitHub repo (the project is then found as below).
                       Anything else, such as a mistyped path, is rejected.
           --project-dir PATH  (the project's folder; same as --repo PATH)
         With neither: $CLAUDE_PROJECT_DIR, else the current directory, searching up
         from there for .claude/workflow.json (stopping at the repo root).

<role> is one of: backlog, ready, in_progress, in_review, done. Board ids and
the role -> column-name mapping come from .claude/workflow.json
(board.project_id, board.fields.status.{id,options}, board.columns).

Why a script: the hand-rolled version fails quietly in three known ways. An
issue created with `gh issue create` is NOT on the board until it is added;
`gh project item-list` paginates and lags (it can miss an item that exists);
and an edit can "succeed" without the status actually changing. So this adds
the issue if it is missing, takes the item id from the issue itself (not from
item-list), and reads the status back to confirm.

Exit codes: 0 ok | 2 bad usage/config | 3 --read and not on the board | 4 verify failed
"""
import json
import os
import re
import shlex
import shutil
import subprocess
import sys

# GitHub owner/name: an owner starts with a letter or digit, so "../x" or "C:/x/y" is never one.
OWNER_NAME = re.compile(r"^[A-Za-z0-9][A-Za-z0-9-]*/[A-Za-z0-9_.-]+$")
ROLES = ("backlog", "ready", "in_progress", "in_review", "done")


class Fail(Exception):
    def __init__(self, msg, code=2):
        super().__init__(msg)
        self.code = code


def gh_command():
    """How to invoke gh. AUDAX_GH overrides it (a command, may include arguments); the
    tests use it to substitute a fake. Otherwise resolve gh through PATH/PATHEXT."""
    override = os.environ.get("AUDAX_GH")
    if override:
        return shlex.split(override)
    return [shutil.which("gh") or "gh"]


def gh(*args, cwd=None):
    r = subprocess.run([*gh_command(), *args], capture_output=True, text=True, cwd=cwd)
    if r.returncode != 0:
        raise Fail("gh %s failed: %s" % (" ".join(args[:3]), (r.stderr or r.stdout).strip()), 2)
    return r.stdout.strip()


def find_config(start):
    """(path or None, folders searched). Walks up from start to the repo root."""
    d = os.path.abspath(start)
    searched = []
    while True:
        searched.append(d)
        p = os.path.join(d, ".claude", "workflow.json")
        if os.path.isfile(p):
            return p, searched
        if os.path.exists(os.path.join(d, ".git")):
            return None, searched
        parent = os.path.dirname(d)
        if parent == d:
            return None, searched
        d = parent


def current_status(item_id, cwd):
    q = ('query($id:ID!){node(id:$id){... on ProjectV2Item{fieldValueByName(name:"Status")'
         '{... on ProjectV2ItemFieldSingleSelectValue{name}}}}}')
    out = json.loads(gh("api", "graphql", "-f", "query=" + q, "-f", "id=" + item_id, cwd=cwd))
    v = (out.get("data", {}).get("node") or {}).get("fieldValueByName") or {}
    return v.get("name")


def main(argv):
    args = list(argv)
    repo = None
    env_dir = os.environ.get("CLAUDE_PROJECT_DIR")
    project_dir = env_dir or os.getcwd()
    dir_source = "$CLAUDE_PROJECT_DIR" if env_dir else "the current directory"
    read_only = False
    pos = []
    i = 0
    while i < len(args):
        a = args[i]
        if a in ("--repo", "--project-dir") and i + 1 >= len(args):
            raise Fail("%s needs a value" % a, 2)
        if a == "--repo":
            repo = args[i + 1]; i += 2
        elif a == "--project-dir":
            project_dir = args[i + 1]; dir_source = "--project-dir"; i += 2
        elif a == "--read":
            read_only = True; i += 1
        else:
            pos.append(a); i += 1
    if not pos or (not read_only and len(pos) != 2) or (read_only and len(pos) != 1):
        raise Fail(__doc__.split("Why a script")[0].strip(), 2)
    number = pos[0].lstrip("#")
    role = None if read_only else pos[1]
    if role is not None and role not in ROLES:
        raise Fail("unknown role %r (expected one of: %s)" % (role, ", ".join(ROLES)), 2)

    if repo and os.path.isdir(repo):
        project_dir, dir_source, repo = repo, "--repo", None
    elif repo and not OWNER_NAME.match(repo):
        raise Fail("--repo %r is neither an existing folder nor owner/name (a mistyped path ends up here)" % repo, 2)
    if not os.path.isdir(project_dir):
        raise Fail("%s %r is not a folder that exists" % (dir_source, project_dir), 2)

    cfg_path, searched = find_config(project_dir)
    if not cfg_path:
        raise Fail("no .claude/workflow.json found searching up from %s (%s; looked in %d folder%s, "
                   "ending at %s). Run it from inside the project, or pass --repo <path to the project>."
                   % (project_dir, dir_source, len(searched), "" if len(searched) == 1 else "s", searched[-1]), 2)
    try:
        board = json.load(open(cfg_path, encoding="utf-8"))["board"]
        owner, num, pid = board["owner"], board["number"], board["project_id"]
        status = board["fields"]["status"]
        field_id, options = status["id"], status["options"]
    except (KeyError, ValueError) as e:
        raise Fail("%s is missing board.owner/number/project_id/fields.status (%s)" % (cfg_path, e), 2)
    columns = board.get("columns", {})
    if role is not None and role not in options:
        raise Fail("board.fields.status.options has no id for role %r" % role, 2)

    if not repo:
        repo = gh("repo", "view", "--json", "nameWithOwner", "--jq", ".nameWithOwner", cwd=project_dir)
    ro, rn = repo.split("/", 1)

    q = ('query($o:String!,$r:String!,$n:Int!){repository(owner:$o,name:$r){issue(number:$n)'
         '{id url projectItems(first:20){nodes{id project{id}}}}}}')
    out = json.loads(gh("api", "graphql", "-f", "query=" + q, "-f", "o=" + ro, "-f", "r=" + rn,
                        "-F", "n=" + number, cwd=project_dir))
    issue = (out.get("data", {}).get("repository") or {}).get("issue")
    if not issue:
        raise Fail("issue #%s not found in %s" % (number, repo), 2)
    item = next((n["id"] for n in issue["projectItems"]["nodes"] if n["project"]["id"] == pid), None)

    if item is None:
        if read_only:
            print("#%s is not on the board" % number)
            return 3
        item = gh("project", "item-add", str(num), "--owner", owner, "--url", issue["url"],
                  "--format", "json", "--jq", ".id", cwd=project_dir)
        if not item.startswith("PVTI_"):
            raise Fail("adding #%s to the board did not return an item id (got %r)" % (number, item), 4)

    if read_only:
        print("#%s -> %s" % (number, current_status(item, project_dir)))
        return 0

    gh("project", "item-edit", "--project-id", pid, "--id", item, "--field-id", field_id,
       "--single-select-option-id", options[role], cwd=project_dir)
    got = current_status(item, project_dir)
    want = columns.get(role)
    if want is not None and got != want:
        raise Fail("set #%s to %r but the board reads back %r" % (number, want, got), 4)
    print("#%s -> %s" % (number, got))
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main(sys.argv[1:]))
    except Fail as e:
        sys.stderr.write("board_status: %s\n" % e)
        sys.exit(e.code)
