#!/usr/bin/env python
"""Say whether a repo's CI runs macOS on every pull request, which the standard workflow does not allow.

Usage: macos_ci.py [REPO]          (REPO defaults to the current folder)

macOS runners queue for 10+ minutes and cost ten times the minutes, so the workflow runs macOS only when the owner
asks for it (`gh workflow run CI -f macos=true`). Prints "ok" and exits 0 when no workflow file runs macOS on a
pull request, else lists the files and exits 1. Exit 2 for a folder that does not exist.

It uses the same detector as project-bootstrap's upgrade_check.py (the `macos_every_pr` key), so "macOS on every PR"
means one thing. Nothing is written. A repo with `components.ci: false` in .claude/workflow.json has no CI to check
and is reported ok. So is a repo that overrides the default with `"ci": {"macos_on_every_pr": true}` there: off is the
workflow's opinion, and a project may always choose otherwise.
"""
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, os.pardir, os.pardir, "project-bootstrap", "scripts"))


def main(argv):
    if len(argv) > 1 or (argv and argv[0] in ("-h", "--help")):
        print(__doc__.strip().split("\n\n")[0] + "\n\nUsage: macos_ci.py [REPO]", file=sys.stderr)
        return 2
    repo = argv[0] if argv else "."
    if not os.path.isdir(repo):
        print("not a directory: %s" % repo, file=sys.stderr)
        return 2
    try:
        import upgrade_check
    except ImportError:
        print("cannot find project-bootstrap/scripts/upgrade_check.py next to this skill", file=sys.stderr)
        return 2
    report = upgrade_check.check(repo, None)
    found = report["macos_every_pr"]
    if report["macos_override"]:
        print("ok (this project overrides the default: ci.macos_on_every_pr is true in .claude/workflow.json)")
        return 0
    if not found:
        print("ok")
        return 0
    print("CI runs macOS on every pull request (the standard runs it only on request):")
    for p in found:
        print("  - %s" % p)
    print("Fix: use the on-request form (project-bootstrap, upgrade mode: a workflow_dispatch trigger with a boolean "
          "`macos` input, and the matrix built from it).")
    return 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
