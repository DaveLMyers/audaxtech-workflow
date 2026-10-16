# audaxtech-workflow - Design Ideas Log

A running list of raw design thoughts, captured as they come up. Nothing here is
a decision or a commitment. It is deliberately separate from DECISIONS.md so loose
ideas don't get mistaken for settled calls.

**How to use it:** add new entries at the top. Keep the original thought in the
owner's words. Anything added later by Claude goes under "Context", clearly
separate from the idea itself. Status is one of: `raw`, `exploring`, `adopted`,
`dropped`. When an idea is adopted, the decision goes in DECISIONS.md and the
work gets its own issue; the entry here stays, with its status updated.

---

## 2026-10-16 - Enterprise-style standards across projects

**Status:** exploring (tracked by #29, which stays open as the pointer)

**Thought:** "I want to leverage enterprise-level things where it makes sense. I'm also
working on efforts where I'm not a solo developer, so I want to be able to enforce, or come
up with, a standard way of working."

**Context (from Claude, not part of the idea):**
- **What enterprises build and what they buy.** Distribution, enforcement and audit come out
  of the box; the standards themselves are always written in-house. Claude Code side (from the
  [org plugin docs](https://code.claude.com/docs/en/plugins/org)): managed settings can register
  a marketplace and force-enable plugins (`extraKnownMarketplaces`, `enabledPlugins`),
  a repo's committed `.claude/settings.json` can require plugins per project, `autoUpdate` can be
  set per marketplace, and two marketplaces on different refs give release channels. Auto-update
  is off by default for third-party marketplaces such as `audaxtech`. A marketplace can be pinned
  to a tag with `#ref`.
- **Enforcement should be a gate, not a prompt.** The merge-gate hook only covers merges made
  from Claude Code. Branch protection or rulesets with required status checks also cover the
  GitHub UI. This repo is public, so they are available; CONTRIBUTING says required checks are
  not switched on yet.
- **Drift is the part nothing out of the box covers for a project's own files.** The plugin
  never rewrites a project's CONTRIBUTING, templates or CI. Template tools (Copier, cruft,
  Backstage-style templates) record the template version and can re-apply updates; upgrade mode
  is a small bespoke version of that.
- **Centralise instead of syncing where possible.** For example CI as a reusable workflow that
  projects reference by pinned version, so a CI fix needs no PR in every project. Not checked
  in detail yet.

**Candidates, none started** (file a separate issue for any the owner picks):
1. Required status checks / rulesets on this repo.
2. CI as a reusable workflow referenced by version.
3. Record `plugin_version` and a separate `process_version` (bumped only when project-facing
   files change; CI would enforce the bump) in `workflow.json`; a quiet session-start line when a
   project is behind; a changelog per `process_version`; one command to report drift across a
   folder of projects. Session-start hooks are assumed to exist and need checking first.
4. Turn on marketplace auto-update (a setting in `/plugin`, owner's machine).
5. Dogfood the plugin on itself. A CI step could run `upgrade_check.py` on this repo and fail if
   anything is missing. Running it by hand on 2026-10-16 found nothing missing, but a manual
   comparison found this repo's CONTRIBUTING.md lacks the template's "Line endings" section: the
   check only looks at file presence and the game subsections, so it cannot see that. Extending it
   to compare every `##` section of the CONTRIBUTING template would catch this kind of drift.
6. Deferred: automatic upgrade PRs, a per-project CI gate on drift, release channels.

**Open decisions:** one version number or two (Claude leans two); how the drift report finds
projects (scan a folder vs a list in the profile); how loud the session-start line should be.
