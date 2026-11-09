# audaxtech-workflow

A Claude Code plugin (skills, agents and hooks) that gives a new project a ready-made workflow. Full context: [README.md](README.md),
[CONTRIBUTING.md](CONTRIBUTING.md). This file stays short on purpose (it
loads into every session) - only what's worth knowing before doing anything.
Claude Code reads it through [CLAUDE.md](CLAUDE.md), which imports it and adds the few
rules that only apply to Claude Code.

## Before doing anything else

- **Check `git status`/`git branch` before any repo-modifying action.** The
  user may run several agent sessions against this repo concurrently -
  don't assume the working tree is how you left it.
- **Prefer `git -C "<repo path>" <command>` over relying on cwd** for any git
  command, and never leave a cross-repo `cd` unreverted across tool calls -
  bundle it with the command that needs it.
- **Before calling any PR or issue "done" or "ready to merge"**: run the
  pre-merge check (in Claude Code, the `pr-check` skill from the audaxtech-workflow
  plugin). Standing step.
- **This is a tool, not a game.** There are no game docs. Tests live in
  `tests/` (`bash tests/run-hook-tests.sh`, `run-toolchain-tests.sh`,
  `run-workissue-tests.sh`, `run-bootstrap-tests.sh`, `run-saferm-tests.sh`) and must pass before a PR is ready.
- **Stray design thoughts go in `docs/design-ideas.md`**, in the owner's words with a status,
  not into the backlog. An open "revisit" issue on the board points at an entry there.
- **Full workflow** (branching, commits, issues/board, testing, style):
  [CONTRIBUTING.md](CONTRIBUTING.md).
