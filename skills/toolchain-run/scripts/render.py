#!/usr/bin/env python
"""Render a repo-local toolchain setup from a JSON spec.

Usage: python render.py <spec.json> <repo_dir> [--dry-run]

Writes into <repo_dir>:
  <pin_file>                          pinned version (only if absent - never clobbers a bump)
  tools/setup-<name>.sh / .ps1        idempotent fetch scripts
  .claude/skills/run/SKILL.md         the project's "how to run things" skill (only if absent -
                                      merge by hand into an existing one, e.g. a 2nd toolchain)
and appends "/<bin_dir>/" to .gitignore if missing.

See ../SKILL.md for the spec schema and ../examples/godot.spec.json for a
complete real example.
"""
import json
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
TEMPLATES = os.path.join(HERE, "..", "templates")
REQUIRED = ["tool", "name", "project", "version", "pin_file", "bin_dir",
            "version_args", "version_match", "platforms"]


def die(msg):
    sys.exit("render.py: " + msg)


def validate(spec):
    for k in REQUIRED:
        if k not in spec:
            die("spec missing required key: " + k)
    plats = spec["platforms"]
    if "windows" not in plats or "unsupported" in plats["windows"]:
        die("a windows platform with url/archive/bin is required (setup.ps1 is windows-only)")
    for p, v in plats.items():
        if p not in ("windows", "linux", "macos"):
            die("unknown platform: " + p)
        if "unsupported" not in v:
            for k in ("url", "archive", "bin"):
                if k not in v:
                    die("platform %s missing %s" % (p, k))
            if v["archive"] not in ("zip", "tar.gz"):
                die("platform %s archive must be zip or tar.gz" % p)


def sh_quote(s):
    return "'" + s.replace("'", "'\\''") + "'"


def sh_dq(s):
    """Double-quoted shell string with {version} -> ${VERSION}; other specials escaped."""
    def esc(x):
        for ch in ("\\", '"', "$", "`"):
            x = x.replace(ch, "\\" + ch)
        return x
    return '"' + "${VERSION}".join(esc(p) for p in s.split("{version}")) + '"'


def platform_cases(plats):
    out = []
    for p in ("linux", "macos", "windows"):
        v = plats.get(p)
        out.append("  %s)" % p)
        if v is None or "unsupported" in v:
            msg = (v or {}).get("unsupported", "%s isn't wired up in this script yet." % p)
            for line in msg.splitlines():
                out.append("    echo %s >&2" % sh_quote(line))
            out.append("    exit 1 ;;")
        else:
            out.append("    URL=%s" % sh_dq(v["url"]))
            out.append("    ARCHIVE=%s" % sh_quote(v["archive"]))
            out.append("    BIN_REL=%s ;;" % sh_dq(v["bin"]))
    return "\n".join(out)


def render_template(name, repl):
    with open(os.path.join(TEMPLATES, name), encoding="utf-8") as f:
        s = f.read()
    for k, v in repl.items():
        s = s.replace("@@%s@@" % k, v)
    if "@@" in s:
        die("unreplaced placeholder left in " + name)
    return s


def run_skill(spec):
    b = spec["bin_dir"]
    name = spec["name"]
    tool = spec["tool"]
    lines = []
    A = lines.append
    A("---")
    A("name: run")
    A("description: How to launch, test and verify %s locally - the pinned %s binary's location, the setup script that fetches it, and the exact commands to use. Use whenever launching, running, testing, building or verifying this project, or whenever %s can't be found on PATH - don't search the filesystem for an install before checking here." % (spec["project"], tool, tool))
    A("---")
    A("")
    A("# Running %s" % spec["project"])
    A("")
    A("%s is not installed system-wide for this project, and no PATH edit should be assumed or needed. A pinned version is fetched into a git-ignored, repo-local folder (`%s/`), so this works identically for a human contributor, CI, and a fresh Claude Code session with no memory of prior setup - one canonical answer to \"where's %s,\" not one per machine." % (tool, b, tool))
    A("")
    A("## First time in this repo")
    A("")
    A("Run the setup script once (idempotent - safe to re-run; no-ops if the right version is present):")
    A("")
    A("- Windows: `.\\tools\\setup-%s.ps1`" % name)
    A("- macOS/Linux/Git Bash: `./tools/setup-%s.sh`" % name)
    A("")
    A("It fetches the version pinned in `%s`. To upgrade, change that one file (CI uses the same script and cache key)." % spec["pin_file"])
    A("")
    A("## The binary")
    A("")
    A("- Windows: `%s\\%s.cmd`" % (b, name))
    A("- macOS/Linux/Git Bash: `%s/%s`" % (b, name))
    A("")
    A("Use this in place of bare `%s` in every command below and in this repo's docs." % name)
    for n in spec.get("notes", []):
        A("")
        A(n)
    cmds = spec.get("commands", [])
    if cmds:
        A("")
        A("## Commands")
        for c in cmds:
            A("")
            A("**%s**" % c["title"])
            A("")
            A("```")
            A(c["cmd"].replace("{bin}", "%s/%s" % (b, name)))
            A("```")
            if c.get("note"):
                A(c["note"])
    A("")
    A("## If something's still not found")
    A("")
    A("Don't fall back to searching the filesystem for an install - re-run the setup script (idempotent) and use the path it prints. If that fails, the problem is the script or the pinned version, not a missing copy elsewhere on the machine.")
    A("")
    return "\n".join(lines)


def write(path, content, dry, keep_existing=False):
    if keep_existing and os.path.exists(path):
        print("kept existing  " + path)
        return
    print(("would write   " if dry else "wrote          ") + path)
    if dry:
        return
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w", encoding="utf-8", newline="\n") as f:
        f.write(content)


def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    dry = "--dry-run" in sys.argv
    if len(args) != 2:
        die("usage: render.py <spec.json> <repo_dir> [--dry-run]")
    with open(args[0], encoding="utf-8") as f:
        spec = json.load(f)
    validate(spec)
    repo = args[1]
    w = spec["platforms"]["windows"]
    va = spec["version_args"]
    repl = {
        "TOOL": spec["tool"], "NAME": spec["name"],
        "PIN_FILE": spec["pin_file"], "BIN_DIR": spec["bin_dir"],
        "VERSION_MATCH": spec["version_match"],
        "VERSION_ARGS": " ".join(sh_quote(a) for a in va),
        "VERSION_ARGS_PS": " ".join("'%s'" % a.replace("'", "''") for a in va),
        "PLATFORM_CASES": platform_cases(spec["platforms"]),
        "WIN_URL": w["url"].replace("'", "''"), "WIN_ARCHIVE": w["archive"],
        "WIN_BIN": w["bin"].replace("'", "''"),
    }
    tools = os.path.join(repo, "tools")
    write(os.path.join(repo, spec["pin_file"]), spec["version"] + "\n", dry, keep_existing=True)
    write(os.path.join(tools, "setup-%s.sh" % spec["name"]), render_template("setup.sh.tmpl", repl), dry)
    write(os.path.join(tools, "setup-%s.ps1" % spec["name"]), render_template("setup.ps1.tmpl", repl), dry)
    write(os.path.join(repo, ".claude", "skills", "run", "SKILL.md"), run_skill(spec), dry, keep_existing=True)

    gi = os.path.join(repo, ".gitignore")
    entry = "/%s/" % spec["bin_dir"].strip("/")
    existing = open(gi, encoding="utf-8").read() if os.path.exists(gi) else ""
    if entry not in existing.splitlines():
        print(("would append   " if dry else "appended       ") + ".gitignore: " + entry)
        if not dry:
            with open(gi, "a", encoding="utf-8", newline="\n") as f:
                f.write(("" if existing.endswith("\n") or not existing else "\n")
                        + "\n# Local %s toolchain (fetched by tools/setup-%s.*)\n%s\n" % (spec["tool"], spec["name"], entry))


if __name__ == "__main__":
    main()
