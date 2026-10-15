# audaxtech-workflow

A [Claude Code](https://claude.com/claude-code) plugin: a project workflow **built for game development**, packaged so you can start a new game with the process already in place. It works for other kinds of project too (see [Kinds and stacks](#kinds-and-stacks)), but games are the default and the best-supported path.

It encodes one opinionated way of working: every change is an issue on a board, work happens on a branch, a PR is not "done" until CI is green and an independent review has been run, and judgment calls are written down. The pieces below make that cheap to set up and hard to skip.

## What's in it

| Piece | What it does |
|---|---|
| `project-bootstrap` skill | Scaffolds a new repo's process (including `.gitattributes` and `.editorconfig` so line endings stay LF), or (upgrade mode) reports what an older repo is missing and adds only that: CONTRIBUTING, a DECISIONS log, issue/PR templates, a CI workflow, CLAUDE.md, and a GitHub Projects v2 board with columns, a priority field, a "Prioritized backlog" view and labels. For a game it also adds the game docs (VISION, DESIGN, GAMEPLAY, HOW_TO_PLAY, a design-ideas log). |
| Stack modules | Engine conventions, testing guidance, CI steps and ignore rules, picked at bootstrap. Today: `godot-gdscript`, with optional cross-platform and translatable-text rules (both on by default for games). |
| `toolchain-run` skill | Generates a pinned, repo-local toolchain setup (version pin file, bash and PowerShell setup scripts, a `run` skill) so nobody installs the engine system-wide or hunts for it. Reuses an install you already have, but only if it is exactly the pinned version. |
| `work-issue` skill | Takes an issue from Ready to ready-to-merge following the workflow, so "work issue #90" is the whole prompt: checks repo state, moves the board card, branches, implements with tests, lets you try it before anything is pushed, opens the PR, runs `pr-check`, and asks before merging. It never merges without an explicit yes. |
| `pr-check` skill | The pre-merge checklist: it boots and tests the project, runs an independent review, checks docs, and for a game means actually playing the change. |
| `blind-spec-reviewer` agent | Lists what should be tested, from the spec alone, never seeing the implementation. |
| `test-saboteur` agent | Tries to build subtly wrong implementations the existing tests would still accept. |
| `github-projects-workflow` skill | Gotchas for driving a Projects v2 board with `gh` (issues don't join the board on their own, `item-list` silently paginates, and so on). |
| Hooks | A merge gate that denies a PR merge unless CI is green, and a guard that denies git-mutating commands run from the wrong repository. Both are **inert** in any project without a `.claude/workflow.json` marker. |

## Install

```
/plugin marketplace add DaveLMyers/audaxtech-workflow
/plugin install audaxtech-workflow@audaxtech
```

Or from a shell: `claude plugin marketplace add DaveLMyers/audaxtech-workflow`, then `claude plugin install audaxtech-workflow@audaxtech`. Restart Claude Code to load it. Skills are then namespaced, e.g. `/audaxtech-workflow:project-bootstrap`.

Requires `bash`, `python` and `gh` (GitHub CLI, with the `project` scope for board creation) on PATH. On Windows, use Git Bash.

## Use it

Once a project is set up, say "work issue #N" and the `work-issue` skill runs the whole flow, stopping to ask before pushing and before merging.

In a new or existing repo, ask Claude to bootstrap the project (or run `/audaxtech-workflow:project-bootstrap`). It asks what kind of project it is, then which engine, proposes the labels and board, and **asks once before touching GitHub** (creating the repo, board and labels). Local files are written first, so a failure in the board step leaves a working repo.

A project opts in to the hooks by having `.claude/workflow.json`, which bootstrap writes. Delete it, or set a component to `false` in it, to switch a hook off for that one project.

## Kinds and stacks

- **Kind** is what the project is: `game` (the default), `web`, `library`, `tool` or `other`. It chooses the area-label preset and the kind-specific docs and process sections.
- **Stack** is the engine or language: `godot-gdscript` today. It supplies conventions, testing guidance, CI steps and `.gitignore` lines.
- Add a stack by adding a folder under `skills/project-bootstrap/templates/stacks/` with a `stack.json`. Nothing is invented for an engine that has no stack: bootstrap falls back to generic text and says so.

Personal defaults (GitHub owner, merge method, board columns, CI matrix, components) live in `~/.claude/workflow-profile.json`; see [`skills/project-bootstrap/references/PROFILE.md`](skills/project-bootstrap/references/PROFILE.md).

## What is verified, and what is not

This was extracted from two real Godot projects and then tested piece by piece. All five test suites run in CI on Linux, macOS (Apple Silicon) and Windows on every PR and push to `main`, and are green on all three; locally they are run on Windows with Git Bash. The counts below are from the latest run.

**Tested:**
- the hooks: 65 cases, `tests/run-hook-tests.sh`, each fix sabotage-checked, including the merge gate's fallback where there is no GNU `timeout` (stock macOS), which CI found; the merge gate has also been used live in a real repository;
- `work-issue`'s helper scripts and `pr-check`'s `docs_only.py` classifier: 142 cases against a fake `gh` and throwaway git repos, `tests/run-workissue-tests.sh`. These cover board status and branch naming (plus a live read and write against a real board), `create-board.sh`'s saved views, and what counts as docs-only;
- `project-bootstrap`'s upgrade check and its line-ending templates: 46 cases against throwaway repos, including the older layout from issue #3, `tests/run-bootstrap-tests.sh`;
- the delete guard the suites use (`tests/_safe_rm.sh`): 21 cases, `tests/run-saferm-tests.sh`; the symlink case is skipped where symlinks are not available, as on the Windows setup used here;
- the toolchain generator for bash and PowerShell, including fresh install, version bump, bad pin, and reuse of an existing install by flag, env var and PATH: 20 cases against a fake tool served from localhost, `tests/run-toolchain-tests.sh` (its PowerShell half runs only on Windows).

**Not yet verified:**
- the skills' prose steps have not been run end to end: upgrade mode's step that appends the missing pieces (only its report is tested), the lighter docs-only path, the `work-issue` guidance on CI after a PR opens, visual tuning loops and stray design ideas, and writing `.gitattributes` and `.editorconfig` into a brand-new project (the templates are checked, a fresh bootstrap run is not);
- `create-board.sh`'s view step against a live new board end to end (the `createProjectV2View` call was used by hand on a real board; the "Table" rename via `updateProjectV2View` has only run against the fake `gh`);
- the cwd guard triggered live (unit-tested only: a stale `cd` cannot be reproduced in the harness);
- the macOS Godot download path (the URL and bundle layout come from a working setup but have not been fetched by the generated script);
- the Godot stack module rendered through a fresh bootstrap run;
- the skills and agents on Linux and macOS: the test suites pass there in CI, but the interactive flows have only been used on Windows with Git Bash;
- there is no Unity (or other engine) stack yet.

## Tests

```
bash tests/run-hook-tests.sh
bash tests/run-toolchain-tests.sh
bash tests/run-workissue-tests.sh
bash tests/run-bootstrap-tests.sh
bash tests/run-saferm-tests.sh
claude plugin validate .
```
All the test scripts are self-contained and clean up after themselves (they delete only through the guard above).

## License

[MIT](LICENSE) © Dave L. Myers
