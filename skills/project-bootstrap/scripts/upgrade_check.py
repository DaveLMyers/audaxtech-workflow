#!/usr/bin/env python
"""Report which pieces of the standard project process an existing repo lacks.

READ-ONLY: this script never writes anything. It compares a repo against what
project-bootstrap would create and prints what is missing, so the skill can ask
the owner and then add only those pieces (see "Upgrade mode" in SKILL.md).

Usage: upgrade_check.py <repo-dir> [--kind game|web|library|tool|other] [--json]

The kind comes from <repo>/.claude/workflow.json when it has one, else --kind,
else `game` (bootstrap's default; the report says it was assumed). Components
switched off in workflow.json (`components.<name>: false`) are not reported.

Limits: file names are compared the way the OS compares them, so on Windows and
macOS (case-insensitive by default) docs/DESIGN-IDEAS.md counts as docs/design-ideas.md.
The CLAUDE.md pointer is recognised by the file name appearing anywhere in CLAUDE.md.

Exit codes: 0 = report produced (even if things are missing), 2 = bad usage or
the repo directory does not exist.
"""
import argparse
import json
import os
import re
import sys

GAME_DOCS = ["VISION.md", "DESIGN.md", "GAMEPLAY.md", "HOW_TO_PLAY.md", "design-ideas.md"]
ISSUE_TEMPLATES = ["feature.yml", "bug_report.yml", "chore.yml", "research.yml"]
GAME_SECTION_RE = re.compile(r"^##[ 	]+Game-specific process\b", re.MULTILINE)  # a level-2 heading, not "###"
IDEAS_POINTER = "design-ideas.md"


def read(path):
    try:
        with open(path, encoding="utf-8-sig", errors="replace") as f:  # -sig: Notepad adds a BOM
            return f.read()
    except OSError:
        return None


def load_marker(repo):
    """(config dict, note). A missing or unreadable marker is not an error here."""
    path = os.path.join(repo, ".claude", "workflow.json")
    text = read(path)
    if text is None:
        return {}, None
    try:
        data = json.loads(text)
        if not isinstance(data, dict):
            raise ValueError("not an object")
        return data, None
    except ValueError as e:
        return {}, ".claude/workflow.json exists but cannot be read (%s); treated as absent" % e


def check(repo, kind_arg):
    cfg, note = load_marker(repo)
    components = cfg.get("components") if isinstance(cfg.get("components"), dict) else {}
    on = lambda name: components.get(name, True) is not False

    kind, kind_source = cfg.get("kind"), "workflow.json"
    if not kind:
        kind, kind_source = (kind_arg, "--kind") if kind_arg else ("game", "assumed (bootstrap default)")

    missing, present = [], []

    def want(path, what, template):
        full = os.path.join(repo, *path.split("/"))
        (present if os.path.isfile(full) else missing).append(
            {"path": path, "what": what, "template": template, "type": "file"}
        )

    # Pieces every kind gets.
    want("CONTRIBUTING.md", "the workflow document", "CONTRIBUTING.md.tmpl")
    want("CLAUDE.md", "the short session guide", "CLAUDE.md.tmpl")
    if on("decisions_log"):
        want("docs/DECISIONS.md", "the decisions log", "docs/DECISIONS.md")
    if on("issue_and_pr_templates"):
        want(".github/PULL_REQUEST_TEMPLATE.md", "PR template", "github/PULL_REQUEST_TEMPLATE.md")
        for t in ISSUE_TEMPLATES:
            want(".github/ISSUE_TEMPLATE/" + t, "issue template", "github/ISSUE_TEMPLATE/" + t)
    if on("ci"):
        # Any workflow file counts: a repo whose CI is test.yml must not be offered a second one.
        wf = os.path.join(repo, ".github", "workflows")
        has_ci = os.path.isdir(wf) and any(n.lower().endswith((".yml", ".yaml")) for n in os.listdir(wf))
        (present if has_ci else missing).append(
            {"path": ".github/workflows/ci.yml", "what": "CI workflow (no workflow file found)", "template": "github/workflows/ci.yml.tmpl", "type": "file"}
        )
    want(".claude/workflow.json", "the marker that switches the plugin's hooks on", "(generated)")

    # Game-only pieces.
    if kind == "game" and components.get("game_docs", True) is not False:
        for d in GAME_DOCS:
            want("docs/" + d, "game doc", "kinds/game/" + d)
        contributing = read(os.path.join(repo, "CONTRIBUTING.md"))
        if contributing is not None and not GAME_SECTION_RE.search(contributing):
            missing.append({
                "path": "CONTRIBUTING.md", "type": "section",
                "what": "the 'Game-specific process' section",
                "template": "kinds/game/contributing-extra.md",
            })
        claude = read(os.path.join(repo, "CLAUDE.md"))
        if claude is not None and IDEAS_POINTER not in claude:
            missing.append({
                "path": "CLAUDE.md", "type": "line",
                "what": "the pointer saying stray design ideas go in docs/design-ideas.md",
                "template": "kinds/game/claude-extra.md",
            })

    return {
        "repo": os.path.abspath(repo),
        "kind": kind,
        "kind_source": kind_source,
        "note": note,
        "missing": missing,
        "present": [p["path"] for p in present],
    }


def render(report):
    out = ["Repo: %s" % report["repo"], "Kind: %s (from %s)" % (report["kind"], report["kind_source"])]
    if report["note"]:
        out.append("Note: " + report["note"])
    if not report["missing"]:
        out.append("Nothing missing: this repo already has every piece for its kind.")
    else:
        out.append("Missing (%d):" % len(report["missing"]))
        for m in report["missing"]:
            out.append("  - %s [%s]: %s  (template: %s)" % (m["path"], m["type"], m["what"], m["template"]))
    out.append("Already present (%d): left untouched." % len(report["present"]))
    return "\n".join(out)


def main(argv):
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("repo")
    ap.add_argument("--kind", choices=["game", "web", "library", "tool", "other"])
    ap.add_argument("--json", action="store_true")
    args = ap.parse_args(argv)
    if not os.path.isdir(args.repo):
        print("not a directory: %s" % args.repo, file=sys.stderr)
        return 2
    report = check(args.repo, args.kind)
    print(json.dumps(report, indent=2) if args.json else render(report))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
