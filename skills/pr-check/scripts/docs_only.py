#!/usr/bin/env python
"""Say whether a change is docs-only, so it can get the lighter PR description and review.

Usage:
  docs_only.py --base main          the files changed on this branch (git diff --name-only <base>...HEAD)
  docs_only.py PATH [PATH ...]      or name the changed files yourself (repo-relative, / separators)

Prints "docs-only" and exits 0, or "not docs-only" with the offending paths and exits 1.
Exit 2 for bad usage, or when git cannot list the changes.

What counts as docs-only: every changed file is prose that people read and nothing
reads as instructions or runs:
  - Markdown or plain-text files (.md, .markdown, .txt, .rst) under docs/, and images
    under docs/;
  - README, CONTRIBUTING, CHANGELOG, LICENSE, CODE_OF_CONDUCT, SECURITY and NOTICE files
    in the repository root.
Everything else is NOT docs-only, even when it is Markdown: a skill's SKILL.md, agent and
command definitions, templates (templates/, *.tmpl), CLAUDE.md (it steers every session),
issue and PR templates, anything under skills/, agents/, hooks/, .claude/ or .github/,
scripts, tests and config. Those change what runs or what Claude does, so they get the
full PR description and the full review. An empty change is not docs-only.
"""
import posixpath
import subprocess
import sys

PROSE_EXT = (".md", ".markdown", ".txt", ".rst")
IMAGE_EXT = (".png", ".jpg", ".jpeg", ".gif", ".svg", ".webp")
ROOT_DOCS = ("readme", "contributing", "changelog", "license", "code_of_conduct", "security", "notice")
# Folders whose contents are instructions, definitions or machinery, whatever their extension.
MACHINERY = ("skills", "agents", "hooks", "commands", ".claude", ".github", "templates", "tests", "scripts")


def is_docs_path(path):
    p = path.strip().replace("\\", "/")
    if not p or p.startswith("/") or (len(p) > 1 and p[1] == ":"):
        return False                       # empty, absolute, or a Windows drive path
    p = posixpath.normpath(p)
    parts = p.split("/")
    if ".." in parts:
        return False                       # leaves the repository
    low = [x.lower() for x in parts]
    name = low[-1]
    if any(x in MACHINERY for x in low[:-1]):
        return False
    if name in ("skill.md", "claude.md") or name.endswith(".tmpl"):
        return False
    if len(parts) == 1:
        stem = name.split(".")[0]
        return stem in ROOT_DOCS and (name == stem or name.endswith(PROSE_EXT))
    if low[0] == "docs":
        return name.endswith(PROSE_EXT) or name.endswith(IMAGE_EXT)
    return False


def changed_files(base):
    r = subprocess.run(["git", "diff", "--name-only", base + "...HEAD"], capture_output=True, text=True)
    if r.returncode != 0:
        raise SystemExit("docs_only: git could not list the changes against %r: %s" % (base, r.stderr.strip()))
    return [l for l in r.stdout.splitlines() if l.strip()]


def main(argv):
    args = list(argv)
    if args[:1] == ["--base"]:
        if len(args) != 2:
            print(__doc__.split("\n\n")[0], file=sys.stderr)
            return 2
        try:
            files = changed_files(args[1])
        except SystemExit as e:
            print(e, file=sys.stderr)
            return 2
    elif args and not args[0].startswith("-"):
        files = args
    else:
        print(__doc__.split("\n\n")[0], file=sys.stderr)
        return 2
    bad = [f for f in files if not is_docs_path(f)]
    if files and not bad:
        print("docs-only")
        return 0
    print("not docs-only" + ("" if files else " (no changed files)"))
    for f in bad:
        print("  " + f)
    return 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
