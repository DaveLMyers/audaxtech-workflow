# audaxtech-workflow

A Claude Code plugin: an opinionated project workflow, packaged.

| Piece | What it does |
|---|---|
| `project-bootstrap` skill | Scaffolds a repo's process: CONTRIBUTING, DECISIONS log, issue/PR templates, CI skeleton, CLAUDE.md, a GitHub Projects v2 board with columns, priority field and labels. |
| Stack modules (`skills/project-bootstrap/templates/stacks/`) | Engine/language conventions, testing section, CI steps and ignore rules, chosen at bootstrap. Today: `godot-gdscript` (with optional cross-platform and translatable-text modules). Games are the default kind; add a stack per engine. |
| `toolchain-run` skill | Generates a pinned, repo-local toolchain setup (version pin, setup scripts, a `run` skill). |
| `pr-check` skill | The pre-merge checklist: boots it, tests, independent review, live verification, docs. |
| `github-projects-workflow` skill | Gotchas for driving a Projects v2 board with `gh`. |
| `blind-spec-reviewer` agent | Lists what should be tested, from the spec alone. |
| `test-saboteur` agent | Finds wrong implementations the existing tests would accept. |
| Hooks | Deny `gh pr merge` unless CI is green; deny git-mutating commands run outside the session's repo. **Inert** in any project without `.claude/workflow.json`. |

Personal defaults live in `~/.claude/workflow-profile.json`; see
`skills/project-bootstrap/references/PROFILE.md`.

## Try it locally

```
claude --plugin-dir <path-to>/audaxtech-workflow
```
`/reload-plugins` picks up edits in a running session. Skills are then
`/audaxtech-workflow:project-bootstrap` etc. Validate with
`claude plugin validate <path-to>/audaxtech-workflow`.

Requires `bash`, `python` and `gh` on PATH (Git Bash on Windows). Tested on
Windows only so far.
