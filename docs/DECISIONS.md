# Design Decisions Log

An append-only, chronological record of judgment calls for this project -
scope, design, and process decisions that aren't just "do the obvious
thing." Entries are never rewritten or deleted when superseded; a later
decision that changes an earlier one gets its own new entry that says so
and links back, so the history stays intact.

**When to add an entry:** the same PR (or triage session) that makes a real
judgment call adds the entry - not a follow-up cleanup task. If it's not
worth writing down when the decision happens, it won't get written later.

**Entry format:** a dated heading, then Context / Decision / Why, and
Related links. Keep it terse - link to the issue/PR/commit that has the
full detail rather than re-explaining it here.

---

## 2026-10-14 - Adopted the standard project workflow

**Context:** New project, bootstrapped with the `project-bootstrap` skill.

**Decision:** GitHub Flow, Conventional Commits, every change tracked as an
issue on the project board, independent code review + CI green before merge.

**Why:** Process that's already in place costs nothing solo and doesn't
need renegotiating when collaborators join.

**Related:** CONTRIBUTING.md
