---
name: project-bootstrap
description: Scaffolds the full working process for a new project - CONTRIBUTING.md, DECISIONS.md log, issue/PR templates, CI skeleton, a short CLAUDE.md, a `.claude/workflow.json` marker that switches on the audaxtech-workflow plugin's hooks and pr-check for the project, plus a GitHub Projects v2 board with standard columns, Priority field and labels. Games are the default and best-supported kind; other kinds work too. Use when the user is starting a new project/repo or wants the standard workflow set up in an existing one. Triggers on "new project," "start a project," "bootstrap," "scaffold the repo/process," "set up the workflow/board for this project."
---

# Project bootstrap

Packages a project process that was worked out in practice so a new
project starts with it instead of rediscovering it. Everything here is
domain-neutral; stack-specific parts (build/test/run commands, CI steps,
style conventions) are filled in during the interview.

Templates live in `templates/` beside this file, the board script in
`scripts/create-board.sh`. `{{PLACEHOLDERS}}` in templates are replaced by
you; after rendering, grep the output for any leftover `{{`.

## Order of operations (do not reorder)

Local files first (reversible), GitHub-side things last (they live on the
user's account). A failure in the board step must leave a working repo.

### 0. Preconditions
- `git -C <dir> status` and `branch` - the user may have concurrent sessions;
  don't assume state. Confirm the target directory with the user.
- `gh auth status` must show the `project` scope (else `gh auth refresh -s
  project`, which the user must do). `python` must be on PATH (the plugin's hooks use it). The **audaxtech-workflow plugin must be installed and enabled** - it supplies the merge-gate and cwd-guard hooks, the `pr-check` skill and the reviewer agents that this project will rely on; if it isn't, say so and stop rather than generating a project that references missing pieces.
- Is it already a git repo? Does a GitHub remote exist? Existing files that
  collide (CONTRIBUTING.md, CLAUDE.md, .github/, .claude/workflow.json) must be
  **merged, not overwritten** - read them first and show the user a diff of
  what you'd change.

### 1. Interview (one batch of questions, then a single confirmation)
Ask only what you can't infer from the directory:
- **Kind first:** is this a game (the default), a web app, a library, or something else? Then, for a game, which engine (Godot, Unity, ...). The kind picks the area preset and the kind-specific templates below; the engine picks the toolchain and conventions.
- Project name, one-line description, GitHub owner/repo name, public/private.
- Stack and the real commands to build, test, run (drives CI steps, the
  Testing section, and the `run` step of `pr-check`).
- **Areas** for `area:` labels (the major systems; 3-8 is right).
- Solo or team (affects only wording in the review/approval bullets).
- Sibling repos the user reads across (just informs CLAUDE.md wording).

Then present ONE confirmation listing every outward-facing action, and wait
for a clear yes before any of them:
> I'll (a) create GitHub repo `owner/name` (private) *[only if none exists]*,
> (b) create Projects board "<Name>" under `owner` and link it to the repo,
> (c) set its Status columns (Backlog/Ready/In Progress/In Review/Done) and
> a Priority field (P1/P2/P3), (d) create labels `type:*`, `priority:*`,
> `area:<...>`. Nothing is pushed or committed until you say so.
The user may decline the board ("no board") - then skip step 4 and render
CONTRIBUTING.md without the board sections. Approval covers exactly what was
listed; anything else (pushing, extra repos) needs its own ask.

### 2. Render local files
From `templates/`:

| Template | Destination |
|---|---|
| `CONTRIBUTING.md.tmpl` | `CONTRIBUTING.md` (board ids stay as placeholders until step 4) |
| `docs/DECISIONS.md` | `docs/DECISIONS.md` (set `{{DATE}}`) |
| `CLAUDE.md.tmpl` | `CLAUDE.md` |
| `github/PULL_REQUEST_TEMPLATE.md` | `.github/PULL_REQUEST_TEMPLATE.md` |
| `github/ISSUE_TEMPLATE/*.yml` | `.github/ISSUE_TEMPLATE/` (expand `{{AREA_OPTIONS}}` into lines like `        - area:ui`) |
| `github/workflows/ci.yml.tmpl` | `.github/workflows/ci.yml` |
| `kinds/<kind>/*` | Kind-specific additions. For `game` (when `components.game_docs` is on): `DESIGN.md`, `GAMEPLAY.md`, `HOW_TO_PLAY.md` into `docs/`, and `contributing-extra.md` appended to CONTRIBUTING.md via `{{EXTRA_SECTIONS}}` (fill `{{ENGINE_CONVENTIONS}}` with the engine's real conventions from the interview, or a short placeholder note if none are known yet). No `kinds/<kind>/` folder = nothing extra. |
| *(generated, no template)* | `.claude/workflow.json` - the resolved config (see `references/PROFILE.md`). **Its presence is what turns the plugin's hooks on for this project**, and `components.*` switches them individually. Hooks and `pr-check` are NOT copied into the repo; the plugin owns them. |

Fill the stack-specific placeholders with real content, not stubs:
`{{TESTING_SECTION}}` (how to run tests), `{{CI_STEPS}}` (checkout is already
there; add toolchain setup, build, test), `{{RUN_STEP}}` (how to boot/run it),
`{{TOOLCHAIN_BULLET}}` (CLAUDE.md pointer to how to run things, if non-obvious),
`{{EXTRA_SECTIONS}}` (stack conventions, deployment - or delete the marker).
If the stack needs a pinned downloadable tool (an engine, compiler, CLI), use the `toolchain-run` skill to generate the setup scripts and the project's `run` skill, and reference it from `{{RUN_STEP}}`/`{{TOOLCHAIN_BULLET}}`.
Delete unused `{{...}}` lines rather than leaving them. Also write a minimal
README.md and a `.gitignore` if absent. Keep the root CLAUDE.md short.

### 3. Verify the local files before touching GitHub
- `.claude/workflow.json` parses as JSON and its `components` keys match `references/PROFILE.md`.
- If the project already has its own copies of the hooks in `.claude/settings.json` (an older bootstrap), they will run *twice* alongside the plugin's - flag it and offer to remove the project copies.
- Validate YAML (`python -c "import yaml,sys;yaml.safe_load(open(f))"` for
  each file under `.github/`) if PyYAML exists; otherwise eyeball indentation.
- `grep -rn '{{' ` over the rendered files - must be clean except the board-id
  placeholders still awaiting step 4.

### 4. Create the board (only after the step 1 confirmation)
```
bash <this skill's base directory>/scripts/create-board.sh \
  <owner> <repo> "<Board title>" "area1,area2,area3"
```
The repo must already exist on GitHub (labels need it). The script creates the
board, links it, replaces the default Status options with the five standard
ones, adds Priority, creates labels, and prints all ids as JSON. It is **not
idempotent for the board** - if it fails midway, run `gh project list --owner
<owner>` and clean up/continue rather than re-running blind.

Write the printed ids into CONTRIBUTING.md (`{{BOARD_URL}}`, `{{BOARD_NUMBER}}`,
`{{PROJECT_ID}}`, `{{STATUS_FIELD_ID}}`, `{{OPT_*}}`, `{{PRIORITY_FIELD_ID}}`,
`{{OPT_P1..3}}`). Never carry ids over from another project; they're per-board.

### 5. Things only the user can do (say so plainly; the API can't)
Projects v2 workflows can't be enabled via API. In the board's Settings ->
Workflows, enable **Item added to project**, **Pull request linked to issue**
(-> In Review) and **Pull request merged** (-> Done). Warn: **"Auto-close
issue" can fire the moment Status is set to Done** - decide deliberately. Remind
them "merged -> Done" can silently miss, and offer (don't create unasked) a
scheduled reconciliation routine that diffs issue/PR state against the board.

### 6. Hand-off
- Show `git status`; **don't commit/push without asking.** For an existing
  repo, propose branch `chore/bootstrap-process`; for a brand-new repo, one
  initial commit is fine once they agree. Use Conventional Commits.
- Offer to file the first issues on the new board (via `github-projects-workflow`
  patterns: create, then `gh project item-add`, then set Status).
- Report plainly what was created, what was skipped, and the manual steps left.

## Notes / known limits
- Hooks assume `bash` and `python` on PATH (true under Git Bash on Windows).
- The merge-gate hook only covers `gh pr merge` from Claude Code sessions, not
  the GitHub UI; free-plan private repos can't enforce required checks. State
  this honestly in CONTRIBUTING.md (the template already does).
- No stack-specific CI/test templates yet. If a stack recurs (Godot, Node,
  Python), add `templates/stacks/<stack>/` with ready CI steps and testing
  text rather than rewriting them each time. Related skills worth building
  next: a toolchain-run generator and a release pipeline.
