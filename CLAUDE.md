# audaxtech-workflow

A Claude Code plugin (skills, agents and hooks) that gives a new project a ready-made workflow. Full context: [README.md](README.md),
[CONTRIBUTING.md](CONTRIBUTING.md). This file stays short on purpose (it
loads into every session) - only what's worth knowing before doing anything.

## Before doing anything else

- **Check `git status`/`git branch` before any repo-modifying action.** The
  user may run several Claude Code sessions against this repo concurrently -
  don't assume the working tree is how you left it.
- **Prefer `git -C "<repo path>" <command>` over relying on cwd** for any git
  command, and never leave a cross-repo `cd` unreverted across tool calls -
  bundle it with the command that needs it. The audaxtech-workflow plugin's cwd-guard
  hook denies git-mutating commands run outside this repo, but it's a backstop.
- **Before calling any PR or issue "done" or "ready to merge"**: run the
  `pr-check` skill (from the audaxtech-workflow plugin). Standing step.
- **This is a tool, not a game.** There are no game docs. Tests live in
  `tests/` (`bash tests/run-hook-tests.sh`, `run-toolchain-tests.sh`,
  `run-workissue-tests.sh`) and must pass before a PR is ready.
- **This repo uses its own workflow.** The plugin's hooks are live here
  because `.claude/workflow.json` exists. Don't edit `hooks/` or the skills
  from a cached plugin copy under `~/.claude/plugins`; change this repo.
- **Hooks must stay inert in projects without the marker** - see
  "Plugin conventions" in CONTRIBUTING.md.
- **Full workflow** (branching, commits, issues/board, testing, style):
  [CONTRIBUTING.md](CONTRIBUTING.md).
