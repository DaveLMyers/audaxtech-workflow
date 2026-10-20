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
Files are checked for presence only, not content: a .gitattributes that exists but has no
eol rule is reported as present, so the skill should still read it before saying all is well.

Game-specific process: when CONTRIBUTING.md already has that section, each "###" subsection
of kinds/game/contributing-extra.md is checked by heading and the missing ones are listed. The
"Engine conventions" subsection is only a {{ENGINE_CONVENTIONS}} placeholder, so it is never offered
to a repo that has its own conventions / cross-platform / translatable-text heading; it is listed
under `skipped` instead (and flagged `omit_subsections` when the whole section is to be appended).

Old project hooks: copies of the merge-gate and cwd-guard hooks in .claude/settings.json or
tools/hooks/ would run twice next to the plugin's. They are listed, with the doc lines that
mention them, under `old_hooks` (separate from `missing`). Detection is by name: read the hits.

Shadowing skills: a folder under .claude/skills/ named like one of the plugin's own skills (pr-check, work-issue, ...)
is listed under `shadowing_skills`. The project's copy wins the plain name, stops getting the plugin's updates and
skips steps added since it was made. Detection is by folder name; read the copy to see what is project-specific in it.
A project's own skills (such as the `run` skill) are never listed.

macOS on every PR: macOS runners queue for 10+ minutes and cost ten times the minutes, so the standard CI runs macOS
only on request (a `workflow_dispatch` trigger with a `macos` input). A workflow file under .github/workflows/ that
triggers on pull_request and names a macOS runner (`macos-...`) without that input is listed under `macos_every_pr`.
Comment lines are ignored. Detection is by text, so read the file before changing it.

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
GAME_SECTION_RE = re.compile(r"^##[ \t]+Game-specific process\b", re.MULTILINE | re.IGNORECASE)  # a level-2 heading, not "###"
IDEAS_POINTER = "design-ideas.md"
TEMPLATE_EXTRA = os.path.join(os.path.dirname(os.path.abspath(__file__)), os.pardir,
                              "templates", "kinds", "game", "contributing-extra.md")
SUBSECTION_RE = re.compile(r"^###[ \t]+(.+?)[ \t]*$", re.MULTILINE)
HEADING_RE = re.compile(r"^#{1,6}[ \t]+(.+?)[ \t]*$", re.MULTILINE)
ENGINE_HEADING = "engine conventions"
# Headings that mean the repo has its own engine/code conventions. A bare "Commit conventions"
# or "Branch naming conventions" does not count: those say nothing about the engine.
_CONVENTION_WORDS = r"(?:engine|godot|unity|unreal|gdscript|coding|code|style|language)"
OWN_CONVENTIONS_RE = re.compile(
    r"cross-platform|translatable"
    r"|\b" + _CONVENTION_WORDS + r"\b[^\n]*\bconventions?\b"
    r"|\bconventions?\b[^\n]*\b" + _CONVENTION_WORDS + r"\b", re.IGNORECASE)
# Other spellings of the template's subsection headings, compared with punctuation removed.
SUBSECTION_ALIASES = {
    "gamedocs": {"gamedocuments", "gamedocumentation", "gamedesigndocs"},
    "playtesting": {"playtest", "playtests", "playtestingthegame"},
}
# Older project-level copies of the plugin's two hooks, matched by name.
OLD_HOOKS = {
    "merge-gate": re.compile(r"block[-_]merge|merge[-_]gate|ci[-_]red", re.IGNORECASE),
    "cwd-guard": re.compile(r"guard[-_]repo[-_]cwd|cwd[-_]guard|repo[-_]cwd", re.IGNORECASE),
}
HOOK_DIR = "tools/hooks"
PLUGIN_SKILLS_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), os.pardir, os.pardir)
DOC_FILES = ["CONTRIBUTING.md", "CLAUDE.md", "README.md"]
SCRIPT_RE = re.compile(r"[\w.-]+\.(?:sh|py|ps1|js)")


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


def outside_fences(text):
    """The text without fenced code blocks, so a `# comment` in a code sample is not a heading."""
    out, fence = [], None
    for line in text.splitlines():
        m = re.match(r"^[ \t]{0,3}(`{3,}|~{3,})", line)
        if m:
            if fence is None:
                fence = m.group(1)[0]
            elif m.group(1)[0] == fence:
                fence = None
            continue
        if fence is None:
            out.append(line)
    return "\n".join(out)


def template_subsections():
    """Headings of the game template's ### subsections, in order ([] if the template is unreadable)."""
    text = read(TEMPLATE_EXTRA)
    return SUBSECTION_RE.findall(text) if text else []


def squash(heading):
    return re.sub(r"[^a-z0-9]", "", heading.lower())


def has_heading(sub, headings):
    """True if the repo has the template subsection `sub` under its own name or a known alias."""
    key = squash(sub)
    wanted = {key} | SUBSECTION_ALIASES.get(key, set())
    return any(squash(h) in wanted for h in headings)


def hook_kind(text):
    for kind, rx in OLD_HOOKS.items():
        if rx.search(text):
            return kind
    return None


def find_old_hooks(repo):
    """Project-level copies of the plugin's hooks, and the doc lines that mention them."""
    settings, files, names, notes = [], [], set(), []
    for fname in ("settings.json", "settings.local.json"):
        text = read(os.path.join(repo, ".claude", fname))
        if text is None:
            continue
        try:
            data = json.loads(text)
        except ValueError:
            notes.append(".claude/%s could not be parsed as JSON, so its hooks were not checked: read it yourself" % fname)
            continue
        hooks = data.get("hooks") if isinstance(data, dict) else None
        if not isinstance(hooks, dict):
            continue
        for event, groups in hooks.items():
            for group in groups if isinstance(groups, list) else []:
                entries = group.get("hooks") if isinstance(group, dict) else None
                for h in entries if isinstance(entries, list) else []:
                    cmd = h.get("command") if isinstance(h, dict) else None
                    if not isinstance(cmd, str) or "CLAUDE_PLUGIN_ROOT" in cmd:
                        continue  # the plugin's own entry, not an old copy
                    kind = hook_kind(cmd)
                    if kind:
                        settings.append({"file": ".claude/" + fname, "event": event,
                                         "matcher": group.get("matcher"), "hook": kind, "command": cmd})
                        names.update(n for n in SCRIPT_RE.findall(cmd) if hook_kind(n))
    hook_dir = os.path.join(repo, *HOOK_DIR.split("/"))
    if os.path.isdir(hook_dir):
        for n in sorted(os.listdir(hook_dir)):
            kind = hook_kind(n)
            if kind and os.path.isfile(os.path.join(hook_dir, n)):
                files.append({"path": HOOK_DIR + "/" + n, "hook": kind})
                names.add(n)
    refs = []
    if settings or files:
        docs = list(DOC_FILES)
        for root, dirs, fs in os.walk(os.path.join(repo, "docs")):
            dirs.sort()
            docs += [os.path.relpath(os.path.join(root, f), repo).replace(os.sep, "/")
                     for f in sorted(fs) if f.lower().endswith(".md")]
        needles = sorted(names | {HOOK_DIR + "/" + n for n in names})
        for rel in docs:
            text = read(os.path.join(repo, *rel.split("/")))
            for i, line in enumerate((text or "").splitlines(), 1):
                if any(n in line for n in needles):
                    refs.append({"file": rel, "line": i, "text": line.strip()[:160]})
    return {"settings": settings, "files": files, "doc_references": refs, "notes": notes}


def find_shadowing_skills(repo):
    """Project skills under .claude/skills/ that share a folder name with a plugin skill.

    Names are compared ignoring case (Windows and macOS file systems do). Returns (list, note);
    the note is set when the plugin's skills folder cannot be read, so "none" is not trusted blindly.
    """
    def skill_names(base):
        try:
            return {n for n in os.listdir(base) if os.path.isfile(os.path.join(base, n, "SKILL.md"))}
        except OSError:
            return set()
    plugin = {n.lower() for n in skill_names(PLUGIN_SKILLS_DIR)}
    if not plugin:
        return [], "the plugin's skills folder was not found next to this script, so shadowing skills were not checked"
    return ([{"skill": n.lower(), "path": ".claude/skills/%s/SKILL.md" % n}
             for n in sorted(skill_names(os.path.join(repo, ".claude", "skills"))) if n.lower() in plugin], None)


# The on-request form: a boolean `macos` input under workflow_dispatch.inputs. Every line of the block is indented,
# so the match stops at the next top-level key (jobs:) and a job that happens to be called macos does not count.
ON_REQUEST_RE = re.compile(
    r"workflow_dispatch[ \t]*:[ \t]*\n(?:[ \t]+[^\n]*\n)*?[ \t]+inputs[ \t]*:[ \t]*\n"
    r"(?:[ \t]+[^\n]*\n)*?[ \t]+macos[ \t]*:[ \t]*\n(?:[ \t]+[^\n]*\n)*?[ \t]+type[ \t]*:[ \t]*['\"]?boolean\b")
COMMENT_RE = re.compile(r"(^|[ \t])#.*$")


def find_macos_every_pr(repo):
    """Workflow files that run a macOS job on every pull request instead of only on request.

    A file counts when, ignoring comments, it triggers on pull_request, names a macOS runner, and lacks the
    on-request form (a boolean `macos` input under workflow_dispatch, which the CI template renders). Only
    files directly under .github/workflows/ are read, as GitHub does. Text-based: it does not check that the
    matrix is actually gated on the input, nor that every macOS job is.
    """
    wf = os.path.join(repo, ".github", "workflows")
    try:
        names = sorted(n for n in os.listdir(wf) if n.lower().endswith((".yml", ".yaml")))
    except OSError:
        return []
    found = []
    for n in names:
        text = read(os.path.join(wf, n))
        if text is None:
            continue
        text = "\n".join(COMMENT_RE.sub("", l) for l in text.splitlines()) + "\n"
        if (re.search(r"\bpull_request\b", text) and re.search(r"\bmacos-", text, re.IGNORECASE)
                and not ON_REQUEST_RE.search(text)):
            found.append(".github/workflows/" + n)
    return found


def check(repo, kind_arg):
    cfg, note = load_marker(repo)
    shadowing, shadow_note = find_shadowing_skills(repo)
    if shadow_note:
        note = (note + "; " if note else "") + shadow_note
    components = cfg.get("components") if isinstance(cfg.get("components"), dict) else {}
    on = lambda name: components.get(name, True) is not False

    marker_file = os.path.join(repo, ".claude", "workflow.json")
    marker = ("missing" if not os.path.isfile(marker_file)
              else "unreadable" if note else "no kind" if not cfg.get("kind") else "ok")
    kind, kind_source = cfg.get("kind"), "workflow.json"
    if not kind:
        kind, kind_source = (kind_arg, "--kind") if kind_arg else ("game", "assumed (bootstrap default)")

    missing, present, skipped = [], [], []

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
    want(".gitattributes", "line-ending rules", "gitattributes.txt")
    want(".editorconfig", "editor basics (charset, line endings)", "editorconfig.txt")
    want(".claude/workflow.json", "the marker that switches the plugin's hooks on", "(generated)")

    # Game-only pieces.
    if kind == "game" and components.get("game_docs", True) is not False:
        for d in GAME_DOCS:
            want("docs/" + d, "game doc", "kinds/game/" + d)
        contributing = read(os.path.join(repo, "CONTRIBUTING.md"))
        if contributing is not None:
            contributing = outside_fences(contributing)
            headings = HEADING_RE.findall(contributing)
            own_conventions = any(OWN_CONVENTIONS_RE.search(h) for h in headings)
            if not GAME_SECTION_RE.search(contributing):
                entry = {
                    "path": "CONTRIBUTING.md", "type": "section",
                    "what": "the 'Game-specific process' section",
                    "template": "kinds/game/contributing-extra.md",
                }
                if own_conventions:
                    entry["omit_subsections"] = ["Engine conventions"]
                    entry["what"] += " (append without its Engine conventions subsection: the repo has its own conventions)"
                missing.append(entry)
            else:
                subs = template_subsections()
                if not subs:
                    note = (note + "; " if note else "") + "game template contributing-extra.md not found, subsections were not checked"
                for sub in subs:
                    if has_heading(sub, headings):
                        continue
                    if sub.lower() == ENGINE_HEADING and own_conventions:
                        skipped.append({
                            "path": "CONTRIBUTING.md", "subsection": sub,
                            "why": "placeholder-only, and the repo already has its own conventions",
                        })
                        continue
                    missing.append({
                        "path": "CONTRIBUTING.md", "type": "subsection",
                        "what": "the '%s' subsection of the Game-specific process section" % sub,
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
        "marker": marker,
        "note": note,
        "missing": missing,
        "skipped": skipped,
        "old_hooks": find_old_hooks(repo),
        "shadowing_skills": shadowing,
        "macos_every_pr": find_macos_every_pr(repo) if on("ci") else [],
        "present": [p["path"] for p in present],
    }


def render(report):
    out = ["Repo: %s" % report["repo"]]
    if report["kind_source"].startswith("assumed"):
        why = (".claude/workflow.json has no kind" if report.get("marker") == "no kind"
               else "no usable .claude/workflow.json was found")
        out.append("Kind: %s (%s, so %s was assumed; pass --kind to say otherwise)"
                   % (report["kind"], why, report["kind"]))
    else:
        out.append("Kind: %s (from %s)" % (report["kind"], report["kind_source"]))
    if report["note"]:
        out.append("Note: " + report["note"])
    if not report["missing"]:
        out.append("Nothing missing: this repo already has every piece for its kind.")
    else:
        out.append("Missing (%d):" % len(report["missing"]))
        for m in report["missing"]:
            out.append("  - %s [%s]: %s  (template: %s)" % (m["path"], m["type"], m["what"], m["template"]))
    for sk in report["skipped"]:
        out.append("Not offered: the '%s' subsection of %s (%s)." % (sk["subsection"], sk["path"], sk["why"]))
    oh = report["old_hooks"]
    for n in oh["notes"]:
        out.append("Note: " + n)
    if oh["settings"] or oh["files"]:
        out.append("Old project hooks (they would run twice next to the plugin's; offer to remove):")
        for h in oh["settings"]:
            out.append("  - %s [%s] %s %s: %s" % (h["file"], h["hook"], h["event"], h["matcher"] or "", h["command"]))
        for f in oh["files"]:
            out.append("  - %s [%s script]" % (f["path"], f["hook"]))
        if oh["doc_references"]:
            out.append("  Doc lines that mention them (update after removing):")
            for r in oh["doc_references"]:
                out.append("    %s:%d: %s" % (r["file"], r["line"], r["text"]))
    if report["shadowing_skills"]:
        out.append("Project skills that shadow the plugin's (the copy wins the plain name and stops getting updates; offer to move what is project-specific into CONTRIBUTING.md and remove it):")
        for sk in report["shadowing_skills"]:
            out.append("  - %s [%s]" % (sk["path"], sk["skill"]))
    if report["macos_every_pr"]:
        out.append("CI that runs macOS on every PR (macOS queues for 10+ minutes; the standard runs it only on request via workflow_dispatch; offer to change it):")
        for p in report["macos_every_pr"]:
            out.append("  - %s" % p)
    out.append("Already present (%d): left untouched." % len(report["present"]))
    return "\n".join(out)


def main(argv):
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("repo")
    ap.add_argument("--kind", choices=["game", "web", "library", "tool", "other"])
    ap.add_argument("--json", action="store_true")
    args = ap.parse_args(argv)
    try:
        sys.stdout.reconfigure(errors="backslashreplace")
    except (AttributeError, ValueError):
        pass
    if not os.path.isdir(args.repo):
        print("not a directory: %s" % args.repo, file=sys.stderr)
        return 2
    report = check(args.repo, args.kind)
    print(json.dumps(report, indent=2) if args.json else render(report))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
