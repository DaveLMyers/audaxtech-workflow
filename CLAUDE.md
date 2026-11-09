@AGENTS.md

## Claude Code

The session guide is in AGENTS.md (imported above); shared rules go there, and only what
is specific to Claude Code goes here.

- **The plugin's cwd-guard hook is a backstop for the `git -C` rule.** It denies
  git-mutating commands run outside this repo.
- **This repo uses its own workflow.** The plugin's hooks are live here
  because `.claude/workflow.json` exists. Don't edit `hooks/` or the skills
  from a cached plugin copy under `~/.claude/plugins`; change this repo.
- **Hooks must stay inert in projects without the marker** - see
  "Plugin conventions" in CONTRIBUTING.md.
