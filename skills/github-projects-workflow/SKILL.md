---
name: github-projects-workflow
description: >-
  Working patterns and gotchas for GitHub Projects v2 (the "Projects" board attached to a repo or user/org, driven via `gh project` / `gh issue`), learned the hard way on a real project's board. Use whenever a task involves creating issues that should land on a project board, moving cards between statuses, scripting board changes via `gh project item-edit`, or debugging why a board doesn't reflect reality. Triggers on: "project board," "gh project," "Projects v2," "move this to In Progress/Done," "add this issue to the board," or any GitHub Projects automation question.
---

# GitHub Projects v2 workflow patterns

This is a project-agnostic distillation of specific incidents on the
an earlier project board (see that repo's Claude memory for the full
incident history and that board's actual field/option IDs — those IDs are
per-board and won't transfer). What transfers is the *shape* of the
gotchas: Projects v2's automation is thinner than it looks, and its CLI
has sharp edges that fail silently rather than loudly.

## Board membership is not automatic

`gh issue create` does **not** add the new issue to any project board,
even if the repo has exactly one board and it seems like the obvious
place for it to land. Always follow issue creation with an explicit add,
in the same batch of actions, not as an afterthought:

```
gh issue create ...
gh project item-add <project-number> --owner <owner> --url <issue-url>
```

Verify this in a new repo/board before assuming it's true universally —
it was confirmed on an earlier project by two issues that went missing
from `gh project item-list` output despite being real, open issues.

## `gh project item-list` silently paginates

It defaults to a 30-item page and returns "not found" for anything past
that — no error, no warning, just an empty-looking result. If a lookup
for a specific (especially recently-added) item comes back empty, don't
trust that as proof the item is missing — retry with an explicit high
`--limit` (e.g. `--limit 200`) before concluding something went wrong.

## There is no built-in "work started" trigger

Projects v2's built-in workflows (Settings → Workflows in the project UI)
are limited to a small fixed set — as of this writing: Item added to
project, Item closed, Auto-close issue, Auto-add sub-issues, Pull request
linked to issue (→ typically In Review), Pull request merged (→ typically
Done). There is no API to create/enable/disable a workflow — confirmed
via GraphQL introspection, only a `deleteProjectV2Workflow` mutation
exists. Critically, there's no built-in event for "someone started
working on this" (branch created, issue assigned, etc.) — if a board
should reflect "In Progress," something outside Projects v2's automation
has to set that status explicitly (a person, or an agent instructed to do
so when it picks up the work):

```
gh project item-edit --project-id <PVT_...> --id <PVTI_...> \
  --field-id <status-field-id> --single-select-option-id <option-id>
```

Field/option IDs are per-board — get them once with:
```
gh project field-list <project-number> --owner <owner> --format json
```
and an item's `PVTI_...` id (different from the issue number) from
`gh project item-list` matched on `.items[].content.number`.

## Don't trust a workflow's recorded on/off state — verify by observing

A workflow believed disabled (or enabled) based on an earlier check can
be wrong. On an earlier project, "Auto-close issue" was recorded as off,
then turned out to actually be active — closing an issue the moment its
Status was manually set to Done, discovered only because that's what
actually happened to two issues in practice. If a workflow's state
matters to a decision, verify by observing real behavior rather than
trusting a prior note (your own or someone else's).

## "Pull request merged → Done" can silently miss

Even when correctly configured (issue linked via a `Closes #N` PR
keyword, item already on the board before merge), the built-in workflow
can just fail to fire for a given item with no error surfaced anywhere.
Don't assume "the automation is set up right" guarantees the board stays
accurate — for boards where this matters, consider a periodic
reconciliation pass (script or scheduled agent) that diffs real
issue/PR state against the board's Status field and flags or corrects
drift, rather than trusting the workflow silently forever.

## Practical defaults for an agent operating a board

- Move a card to whatever status represents "started" yourself, at the
  moment work begins (e.g. right after creating the feature branch,
  before writing code) — don't leave it to automation that doesn't exist.
- After creating an issue, immediately add it to the board in the same
  action batch.
- When checking board state for a specific item, always pass an explicit
  high `--limit`.
- Periodically verify workflow on/off assumptions against actual
  behavior rather than a cached belief.
