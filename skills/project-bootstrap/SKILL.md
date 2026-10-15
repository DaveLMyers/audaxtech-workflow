---
name: project-bootstrap
description: Scaffolds the full working process for a new project - CONTRIBUTING.md, DECISIONS.md log, issue/PR templates, CI skeleton, a short CLAUDE.md, a `.claude/workflow.json` marker that switches on the audaxtech-workflow plugin's hooks and pr-check for the project, plus a GitHub Projects v2 board with standard columns, Priority field and labels. Games are the default and best-supported kind; other kinds work too. Use when the user is starting a new project/repo or wants the standard workflow set up in an existing one, or an older repo brought up to date with what the templates now provide (upgrade mode). Triggers on "new project," "start a project," "bootstrap," "scaffold the repo/process," "set up the workflow/board for this project."
---

# Project bootstrap

Packages a project process that was worked out in practice so a new
project starts with it instead of rediscovering it. Everything here is
domain-neutral; stack-specific parts (build/test/run commands, CI steps,
style conventions) are filled in during the interview.

**Paths.** `<skill>` below means this skill's base directory: the folder that
holds this SKILL.md, `skills/project-bootstrap/` inside the plugin (not the
plugin root). Everything this skill ships is under it: `<skill>/templates/`,
`<skill>/scripts/` (`create-board.sh`, `board_json.py`, `upgrade_check.py`) and
`<skill>/references/` (`PROFILE.md`, `profile.example.json`). A bare
`templates/...` or `references/...` path in this file is relative to `<skill>`.
`{{PLACEHOLDERS}}` in templates are replaced by you; after rendering, grep the
output for any leftover `{{`.

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
- **Kind first:** is this a game (the default), a web app, a library, or something else? Then, for a game, which engine (Godot, Unity, ...). The kind picks the area preset and the kind-specific templates below; the engine picks a **stack** from `templates/stacks/` (today: `godot-gdscript`; read its `stack.json`, including `status`) and the toolchain. No matching stack = say so, fall back to generic text, and offer to write one later - never invent engine conventions.
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
> a Priority field (P1/P2/P3), (d) add a "Prioritized backlog" board view
> (columns by Status) and rename the default view "Table", (e) create labels
> `type:*`, `priority:*`, `area:<...>`. Nothing is pushed or committed until you say so.
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
| `github/ISSUE_TEMPLATE/*.yml` (feature, bug, chore, research) | `.github/ISSUE_TEMPLATE/` (expand `{{AREA_OPTIONS}}` into lines like `        - area:ui`) |
| `gitattributes.txt`, `editorconfig.txt` | `.gitattributes`, `.editorconfig` (LF in the repo and the working tree on every OS, CRLF only for Windows scripts; no indentation rules, since those depend on the language). In an existing repo, never overwrite: if the file is there, show what the template adds and append only the missing rules. **Check what the index holds before warning about line endings:** `git ls-files --eol` prints `i/<index> w/<working tree>` per file. If the index is `i/lf`, nothing needs renormalizing. On Windows with `core.autocrlf=true` a working tree of `w/crlf` over `i/lf` is normal (Git converts on checkout and commit), so do **not** run `git add --renormalize` and do not call it a problem. Only if the index itself is `i/crlf` or `i/mixed`, warn: adding `.gitattributes` makes Git show every such file as modified until `git add --renormalize .` is run, which must be its own commit, never mixed into other work. Tell the user that `.editorconfig`'s `end_of_line = lf` is what makes their editor save LF, so new edits stay LF even where Git hands out CRLF. |
| `github/workflows/ci.yml.tmpl` | `.github/workflows/ci.yml`. Fill `{{CI_MATRIX}}` from `ci.matrix` (one line per entry: `          - { name: "Linux", os: ubuntu-latest }`); games default to Linux, macOS Intel, macOS Apple Silicon and Windows. Tell the user the cost trade-off (private repos spend the free monthly allowance faster on macOS/Windows) and that `ci.matrix` trims it. |
| `stacks/<stack>/*` | The chosen stack's `stack.json` lists what it fills: `conventions.md` -> `{{ENGINE_CONVENTIONS}}`, `testing.md` -> `{{TESTING_SECTION}}`, `ci-steps.yml` -> `{{CI_STEPS}}` (the setup script it calls comes from the `toolchain-run` skill), `gitignore.txt` appended to `.gitignore`. Entries under `optional` marked `default: true` (cross-platform habits, translatable text) are included unless the matching component is switched off - say they are on and that they can opt out; append them to the game-specific CONTRIBUTING section. Mention the stack's `status` honestly. |
| `kinds/<kind>/*` | Kind-specific additions. For `game` (when `components.game_docs` is on): `VISION.md`, `DESIGN.md`, `GAMEPLAY.md`, `HOW_TO_PLAY.md` and `design-ideas.md` into `docs/` (set `{{DATE}}`), `claude-extra.md` into `{{KIND_BULLETS}}` of CLAUDE.md, and `contributing-extra.md` appended to CONTRIBUTING.md via `{{EXTRA_SECTIONS}}` (fill `{{ENGINE_CONVENTIONS}}` with the engine's real conventions from the interview, or a short placeholder note if none are known yet; in an existing repo that already has its own conventions, drop that subsection instead - see Upgrade mode). No `kinds/<kind>/` folder = nothing extra. |
| *(generated, no template)* | `.claude/workflow.json` - the resolved config (see `<skill>/references/PROFILE.md`; how to build it from `profile.example.json` is under "The workflow.json file" below). **Its presence is what turns the plugin's hooks on for this project**, and `components.*` switches them individually. Hooks and `pr-check` are NOT copied into the repo; the plugin owns them. |

Interview answers fill `{{PROJECT_NAME}}`, `{{ONE_LINE_DESCRIPTION}}`, `{{OWNER}}` and `{{AREA_LABELS}}` (the `area:` labels as a comma-separated list), plus `{{AREA_OPTIONS}}` in the issue templates. Board ids (`{{BOARD_*}}`, `{{PROJECT_ID}}`, `{{STATUS_FIELD_ID}}`, `{{PRIORITY_FIELD_ID}}`, `{{OPT_*}}`) come from `create-board.sh` in step 4.

Fill the stack-specific placeholders with real content, not stubs:
`{{TESTING_SECTION}}` (how to run tests), `{{CI_STEPS}}` (checkout is already
there; add toolchain setup, build, test), `{{RUN_STEP}}` (how to boot/run it),
`{{TOOLCHAIN_BULLET}}` (CLAUDE.md pointer to how to run things, if non-obvious),
`{{EXTRA_SECTIONS}}` (stack conventions, deployment - or delete the marker).
If the stack needs a pinned downloadable tool (an engine, compiler, CLI), use the `toolchain-run` skill to generate the setup scripts and the project's `run` skill, and reference it from `{{RUN_STEP}}`/`{{TOOLCHAIN_BULLET}}`.
Delete unused `{{...}}` lines rather than leaving them. Also write a minimal
README.md (it starts with what the project is, how to use it and what to rely on), a `.gitignore` and the two files above if absent. Keep the root CLAUDE.md short.

### 3. Verify the local files before touching GitHub
- `.claude/workflow.json` parses as JSON and its `components` keys match `<skill>/references/PROFILE.md`.
- If the project already has its own copies of the hooks (in `.claude/settings.json` or `tools/hooks/`, from an older bootstrap), they will run *twice* alongside the plugin's - flag it and offer to remove the project copies (details under Upgrade mode, step 4).
- Validate YAML (`python -c "import yaml,sys;yaml.safe_load(open(f))"` for
  each file under `.github/`) if PyYAML exists; otherwise eyeball indentation.
- `grep -rn '{{' ` over the rendered files - must be clean except the board-id
  placeholders still awaiting step 4.

### 4. Create the board (only after the step 1 confirmation)
```
bash <skill>/scripts/create-board.sh \
  <owner> <repo> "<Board title>" "area1,area2,area3"
```
The repo must already exist on GitHub (labels need it). The script creates the
board, links it, replaces the default Status options with the five standard
ones, adds Priority, adds a "Prioritized backlog" board view (columns by Status;
Title, Assignees, Labels, Priority shown) and renames the default view "Table",
creates labels, and prints all ids as JSON. The views are best-effort: if that call
fails the script warns on stderr and carries on, and the user can add the view in the
board UI. It is **not
idempotent for the board** - if it fails midway, run `gh project list --owner
<owner>` and clean up/continue rather than re-running blind.

The script prints the project's `board` block, **keyed by role** (`backlog`, `ready`,
`in_progress`, `in_review`, `done`). Merge it into `.claude/workflow.json` as `board`
(this is exactly what the `work-issue` skill's `board_status.py` reads, so do not
reshape it), and use the same values for CONTRIBUTING.md: `{{BOARD_URL}}` = `url`,
`{{BOARD_NUMBER}}` = `number`, `{{PROJECT_ID}}` = `project_id`, `{{STATUS_FIELD_ID}}` =
`fields.status.id`, `{{OPT_BACKLOG}}`...`{{OPT_DONE}}` = `fields.status.options.<role>`,
`{{PRIORITY_FIELD_ID}}` and `{{OPT_P1..3}}` = `fields.priority`. Never carry ids over
from another project; they're per-board. Validate the file is still JSON afterwards.

### The workflow.json file (new project or upgrade)

Start from `<skill>/references/profile.example.json` (the profile's defaults) and
resolve it into the project's `.claude/workflow.json`:
- **Keep** `version`, `kind`, `stack`, `git`, `review`, `ci`, `components`, `labels.types`
  and `board.priorities`/`columns` (replaced by the real board block below).
- **Drop** `identity` (a personal default, never copied into a repo) and
  `labels.area_presets` (only the preset matching the kind is proposed, then edited).
- **Add** `project` (the project's name) and `labels.areas` (the confirmed `area:` list, e.g.
  `["gameplay", "ui"]`).
- Set `components` to match what the repo really has (an upgrade should not switch on a
  component whose files it did not add).
- **`board`**: if a board exists, build the block from the board itself rather than by hand.
  Run this in **bash** (Git Bash on Windows), not PowerShell, because PowerShell's
  pipeline puts a BOM and re-encodes the text, so `json.load` fails:
  ```
  gh project field-list <number> --owner <owner> --format json \
    | python <skill>/scripts/board_json.py <owner> <number> <project_id> > board.json
  ```
  (`<project_id>` is the `PVT_...` id from `gh project view <number> --owner <owner> --format json`.)
  Put the result in `workflow.json` as `board`; do not reshape it. The script exits with a
  message if a Status option is missing (renamed columns). Delete the scratch file after.
- Write the file as UTF-8 without a BOM, LF line endings, and re-parse it.

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

## Upgrade mode (a repo that already has some of this)

For a repo that predates a template or was bootstrapped by an older version
(for example one with `docs/` holding only DECISIONS, DESIGN, GAMEPLAY and
HOW_TO_PLAY, and no `design-ideas.md`), or one that grew its own process
(its own CONTRIBUTING.md and hooks). Use it when the user asks to bring a
repo up to date, or when a session in such a repo finds the convention missing.

1. **Look, change nothing.** Run
   `python <skill>/scripts/upgrade_check.py <repo> [--kind <kind>]`.
   It is read-only. It reads `.claude/workflow.json` for the kind and components
   (else `--kind`, else it says no workflow.json was found and assumes `game`) and lists:
   - what is missing: whole files (including `.gitattributes` and `.editorconfig`), the
     "Game-specific process" section of CONTRIBUTING.md or, when the repo has that section,
     which of its `###` subsections (Game docs, Play-testing, ...) are missing, and the
     CLAUDE.md line that points stray design ideas at `docs/design-ideas.md`;
   - what it deliberately does not offer: the template's "Engine conventions" subsection is
     only a `{{ENGINE_CONVENTIONS}}` placeholder, so a repo with its own conventions,
     cross-platform or translatable-text headings is not offered it;
   - older project-level copies of the merge-gate and cwd-guard hooks (in
     `.claude/settings.json`, `.claude/settings.local.json` or `tools/hooks/`) and the doc
     lines that mention them. Detection is by name, so read the hits before acting.
2. **Show the user the report and ask which pieces to add.** Anything the repo
   already has is left alone, even if it differs from the template: the repo's
   own wording wins.
3. **Add only what was approved, and only what is missing.** A missing file is
   rendered from its template (step 2 of the order above). A missing section, subsection
   or line is *appended* to the existing file (`kinds/game/contributing-extra.md` to
   CONTRIBUTING.md, `kinds/game/claude-extra.md` to CLAUDE.md); never rewrite or
   reorder existing content. Append a missing subsection on its own, not the whole
   template. **Drop the "Engine conventions" subsection** (just the `{{ENGINE_CONVENTIONS}}`
   placeholder) whenever the repo already has its own conventions: never append a
   literal `{{...}}`. Match the file's line endings (see the line-endings note in the
   table above: LF in the index with CRLF in the working tree on Windows is normal, and no
   renormalize is needed; check with `git ls-files --eol`). Show the diff first.
4. **Old project hooks, before writing `workflow.json`.** The plugin's hooks switch on as
   soon as `.claude/workflow.json` exists, so any older project copy of the merge gate or
   cwd guard would then run *twice* (two merge checks, two denials). If the report lists
   any: show them and **offer to remove** the `hooks` entries from `.claude/settings.json`
   (only those entries; leave unrelated hooks and settings) and the scripts under
   `tools/hooks/` (delete only after a yes; `git rm`, so history keeps them). Then list the
   doc lines from the report that point at the old scripts (CONTRIBUTING.md, CLAUDE.md,
   README, `docs/`) and offer to reword each to say the audaxtech-workflow plugin provides
   the hook. If the user keeps an old copy, say plainly that it will run twice, and
   consider `components.merge_gate_hook` / `cwd_guard_hook: false` instead.
5. **Write `.claude/workflow.json` if it is missing** (see "The workflow.json file" above
   for the keys to keep and drop and for building the `board` block with `board_json.py`).
6. **GitHub-side pieces** (new board, labels) are not part of an upgrade unless the
   user asks; the step 1 confirmation rule still applies if they do. An *existing* board
   only needs its block in `workflow.json`.
7. **Hand-off.** Do not commit or push without asking; propose a branch such as
   `chore/bootstrap-upgrade`. Once approved, commit with a Conventional Commit, push and
   open the PR (`gh pr create`) from the repo's PR template. The template says to link
   the issue (`Closes #N`); an upgrade usually has none. Either file a small issue for it
   first (and put it on the board if there is one) so the PR can close it, or, if the user
   declines, replace that line with "No tracking issue: bootstrap upgrade, requested
   directly by <owner>" rather than leaving the placeholder or inventing a number. It is a
   docs/config change, so the lighter docs-only PR description applies (see `pr-check`);
   run `pr-check` before calling it ready.

## Notes / known limits
- Hooks assume `bash` and `python` on PATH (true under Git Bash on Windows).
- The merge-gate hook only covers `gh pr merge` from Claude Code sessions, not
  the GitHub UI; free-plan private repos can't enforce required checks. State
  this honestly in CONTRIBUTING.md (the template already does).
- No stack-specific CI/test templates yet. If a stack recurs (Godot, Node,
  Python), add `templates/stacks/<stack>/` with ready CI steps and testing
  text rather than rewriting them each time. Related skills worth building
  next: a toolchain-run generator and a release pipeline.
