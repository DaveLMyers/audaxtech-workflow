---
name: toolchain-run
description: Generates a repo-local, pinned toolchain setup for a project - a version pin file, idempotent setup scripts (PowerShell + bash) that fetch the exact tool version into a git-ignored folder, a stable launcher, and a project `run` skill documenting the exact commands - so no one (human, CI, or a fresh Claude session) ever installs the tool system-wide or hunts the filesystem for it. Use when a new project depends on a downloadable engine/compiler/CLI (Godot, Unity CLI, ffmpeg, a linter binary...) or when a repo's "how do I run/test this" answer is inconsistent across machines or sessions. Triggers on "pin the toolchain," "set up how to run this," "where is X installed," "run skill," or when project-bootstrap needs its run step.
---

# Toolchain-run generator

Generalizes what critter-wars-godot learned the hard way: two Claude sessions
once each found Godot in a different place on the same machine. The fix is
one canonical, repo-local answer produced by a script, with a pin file as the
single source of truth for the version (CI uses the same script and keys its
cache on the pin file).

## When it fits / when it doesn't

- **Fits:** a tool distributed as a downloadable archive containing a binary
  (zip or tar.gz) with a predictable URL per version and platform.
- **Doesn't fit:** ecosystems with their own version pinning - Node
  (`.nvmrc`/`volta`/`engines`), Python (`uv`/`pyenv` + lockfile), Rust
  (`rust-toolchain.toml`), .NET (`global.json`). Use those, and write the
  `run` skill by hand pointing at them. Also not for installers (.msi/.pkg)
  or multi-GB IDEs.

## Process

1. **Gather facts about the tool** (ask, or look at its official release page):
   exact version to pin; download URL pattern for Windows, Linux, macOS;
   archive type per platform (`zip` | `tar.gz`); the binary's path *inside*
   the archive; a command that prints the version and what its output
   contains; the real commands the project needs (test, build, run, lint).
   Note any platform quirks (e.g. GUI-subsystem exes that can't be piped).
2. **Confirm the URLs before relying on them.** Downloading is an action the
   user should approve (name the file, source, rough size). Prefer checking a
   URL with a HEAD request first; a wrong URL is the usual failure.
3. **Write a spec** (JSON; schema below). Start from
   `references/godot.spec.json`, a complete real example.
4. **Render:** `python <this skill's base directory>/scripts/render.py spec.json <repo> [--dry-run]`.
   Writes the pin file (never overwrites an existing pin), `tools/setup-<name>.sh`
   and `.ps1`, `.claude/skills/run/SKILL.md` (kept if one exists - merge by
   hand for a second toolchain), and appends the bin dir to `.gitignore`.
5. **Test it for real** before calling it done (see below), then add the
   extras: a CLAUDE.md line pointing at the `run` skill ("don't search the
   filesystem for X"), and the CI wiring.
6. Don't commit/push without asking; follow the project's own workflow.

### Spec schema

```json
{
  "tool": "Godot", "name": "godot", "project": "Critter Wars",
  "version": "4.7.2-stable",
  "pin_file": ".godot-version", "bin_dir": ".godot-bin",
  "version_args": ["--headless", "--version"],
  "version_match": "{version_core}",
  "platforms": {
    "windows": {"url": "...{version}...", "archive": "zip", "bin": "path/in/archive.exe"},
    "linux":   {"url": "...", "archive": "zip|tar.gz", "bin": "..."},
    "macos":   {"unsupported": "message shown; omit the key for a generic one"}
  },
  "notes":    ["markdown paragraphs placed under 'The binary'"],
  "commands": [{"title": "Run tests", "cmd": "{bin} --headless ...", "note": "optional"}]
}
```

- `{version}` = the pin file contents; `{version_core}` = the part before the
  first `-` (tool output often punctuates differently than the release tag,
  e.g. `4.7.2.stable.official...` vs `4.7.2-stable`). `version_match` is a
  substring that must appear in the version command's output for the
  idempotency check to pass.
- `windows` is required (the `.ps1` is Windows-only; the `.sh` also runs
  under Git Bash and maps it there). `{bin}` in commands becomes
  `<bin_dir>/<name>`.
- The generated launcher is `<bin_dir>/<name>.cmd` on Windows and
  `<bin_dir>/<name>` (a tiny `exec` shim) elsewhere, so callers have one
  stable name regardless of the archive's internal layout or version.

## Testing without trusting the network

The method used to validate this skill, and worth repeating for a new spec's
mechanics: build a fake tool as a zip and tar.gz (a script that prints
`name X.Y.Z`), serve the folder with `python -m http.server <port> --bind
127.0.0.1`, point a spec's URLs at it, then verify: fresh install, launcher
output, re-run says "already set up", bump the pin and confirm it re-fetches,
bad URL fails loudly (non-zero), unsupported platform fails cleanly. The bash
script takes `SETUP_PLATFORM=linux|macos|windows` to force a branch. Kill the
server afterwards. Then do one real fetch of the actual tool (with the user's
OK) to confirm the real URL and archive layout.

## CI wiring (GitHub Actions)

```yaml
- uses: actions/cache@v4
  with:
    path: <bin_dir>
    key: <name>-${{ hashFiles('<pin_file>') }}-linux
- run: ./tools/setup-<name>.sh
```
The cache key on the pin file means a version bump is automatically a cache
miss. Use the script itself, not a separate copy of the download logic.

## Known limits

- Single binary per spec. A second tool = a second spec; hand-merge the `run`
  skills.
- macOS `.app` bundles and installers aren't handled; mark macOS `unsupported`
  with manual instructions, or extend the template for the bundle layout.
- Verified end to end against a local fake tool (PowerShell and bash, both
  archive types). The Godot spec itself mirrors the repo's proven scripts but
  has not been re-fetched through the generated scripts.
