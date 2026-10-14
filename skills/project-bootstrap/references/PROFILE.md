# Workflow profile

Your personal defaults for `project-bootstrap` (and the skills it calls).
Optional: with no profile, the skill uses the defaults below and asks.

- **Location:** `~/.claude/workflow-profile.json` (user-level, not in any repo).
  Copy `profile.example.json` there and edit. Omit any key to take its default.
- **First run with no profile:** the skill asks the short set of questions,
  then offers to save the answers here.

## Resolution order (later wins)

1. Skill defaults (the values in the table below)
2. `~/.claude/workflow-profile.json`
3. Answers given in this project's interview

The resolved result is written to **`.claude/workflow.json` in the project**.
That file, not your profile, is the project's source of truth afterwards:
collaborators, CI and fresh sessions never need your profile. Generated docs
(CONTRIBUTING.md etc.) are rendered from it. The profile is read once, at
bootstrap time.

## Keys

| Key | Default | Notes |
|---|---|---|
| `kind` | `game` | The project kind: `game` (the default and best-supported path), `web`, `library`, or `other`. Drives the area preset and which kind-specific templates and process sections are added (see `templates/kinds/<kind>/`). Asked first in the interview. |
| `stack` | asked | The engine/language stack, e.g. `godot-gdscript` (see `templates/stacks/`). Supplies engine conventions, the testing section, CI steps and `.gitignore` lines. A profile default only makes sense if you mostly use one engine. |
| `identity.github_owner` | asked | Never guessed from the machine. |
| `identity.default_visibility` | `private` | Applies when the skill creates the repo. |
| `git.merge_method` | `squash` | `squash` \| `merge` \| `rebase`. Drives CONTRIBUTING text and repo settings. |
| `git.commit_convention` | `conventional` | `conventional` \| `none`. |
| `git.branch_pattern` | `{type}/{slug}` | `{type}` = feat/fix/chore/docs..., `{slug}` = short kebab description. |
| `git.delete_branch_on_merge` | `true` | |
| `board.enabled` | `true` | `false` skips the board and all board text/ids. |
| `board.title` | `{project} backlog` | `{project}` = project name. |
| `board.columns` | the five shown | **Roles -> display names.** Instructions reference roles ("move to in_progress"); only the board shows the display name. All five roles are required; rename freely. |
| `board.priorities` | `P1,P2,P3` | Also creates matching `priority:` labels. |
| `labels.types` | feature,bug,chore,docs | Add e.g. `research`. Each gets a `type:` label and issue-template support. |
| `labels.area_presets` | `game`, `web`, `library`, `other` | Keyed by `kind`; the matching preset is proposed, then edited in the interview. Add your own kinds. |
| `review.independent_review_required` | `true` | Governs the CONTRIBUTING "standing step" wording and pr-check step 3. |
| `review.default_effort` | `medium` | Starting point for the effort-calibration guidance. |
| `ci.os` | `["ubuntu-latest"]` | A list of runners; more than one produces a matrix. |
| `components.*` | all `true` | See below. |

## Components

Each is independently skippable; the rest must still work. When one is off,
omit its files **and** the doc sentences/links that mention it.

| Component | Produces |
|---|---|
| `issue_and_pr_templates` | `.github/ISSUE_TEMPLATE/*`, `PULL_REQUEST_TEMPLATE.md` |
| `game_docs` | DESIGN.md, GAMEPLAY.md, HOW_TO_PLAY.md and the "Game-specific process" CONTRIBUTING section. Only meaningful for `kind: game`; default `true` there, `false` otherwise. |
| `decisions_log` | `docs/DECISIONS.md` and the "add an entry in the same PR" rule |
| `pr_check_skill` | No files: the plugin owns `pr-check`. When on, CONTRIBUTING.md/CLAUDE.md require it as the standing pre-merge step. |
| `run_skill_and_toolchain` | via `toolchain-run`: pin file, setup scripts, `run` skill |
| `ci` | `.github/workflows/ci.yml` |
| `merge_gate_hook` | No files: the plugin's hook, active in this project because `workflow.json` exists. `false` switches it off here. Needs `ci`. |
| `cwd_guard_hook` | No files: same mechanism as above. |

## The project's `.claude/workflow.json`

The resolved config, written at bootstrap. Same shape as the profile, with
every key filled in, plus the resolved board ids once a board exists:

```json
{
  "version": 1,
  "project": "My Project",
  "git": { "...": "..." }, "board": { "number": 3, "project_id": "PVT_...", "...": "..." },
  "labels": { "...": "..." }, "review": { "...": "..." }, "ci": { "...": "..." },
  "components": { "...": true }
}
```

**Its existence is the opt-in.** The audaxtech-workflow plugin is enabled globally,
but its hooks do nothing in a project without this file, and each
`components.<name>_hook: false` switches that hook off for just this project.
Commit it - collaborators and CI see the same configuration.

## Deliberately NOT configurable (stated opinions, not options)

Every change gets an issue; PRs reference the issue they close; a PR is not
"done" without CI green and the review step (when `independent_review_required`).
These are the point of the workflow. If someone doesn't want them, they don't
want this workflow.

## Stays out of the profile

Behavioral preferences (confirmation pacing, subagent model choice, local-vs-
cloud recommendations) live in `~/.claude/CLAUDE.md`. They are about how
Claude works with you, not what a project contains.
