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

---

## 2026-10-14 - CI on three OSes, and a timeout fallback in the merge gate

**Context:** The plugin had only been tested on Windows with Git Bash. The repo is public, so Actions minutes are free.

**Decision:** CI runs the three suites in `tests/` on Linux, macOS (Apple Silicon) and Windows. The first run found that the merge-gate hook needed GNU `timeout`, which macOS lacks, so it denied every merge there. The hook now uses `timeout`, then `gtimeout`, then a small shell watchdog; the watchdog does not kill the command's child processes. The merge gate stays live on this repo itself (it has a `.claude/workflow.json`).

**Why:** An unverified claim of cross-platform support was the README's biggest open item, and a gate that blocks every merge on a platform is worse than none. Not required by Claude Code: the watchdog costs ~15 lines but avoids a hard dependency on coreutils.

**Related:** PR #9, issue #8

---

## 2026-10-14 - Upgrade mode is a read-only check plus owner-approved additions

**Context:** Older repos (critter-wars before its docs were added) drift from the templates, and issue #3 asked for an upgrade mode that never overwrites anything.

**Decision:** `project-bootstrap` upgrade mode starts with `scripts/upgrade_check.py`, a read-only report of what is missing, and the skill then asks which pieces to add and appends only those. A missing section or line is appended to the existing file; existing content is never rewritten, even where it differs from the template.

**Why:** The risky part is deciding what is missing, so that is a testable script run against throwaway repos. Writing stays with the skill, where the owner is asked first.

**Related:** #3

---

## 2026-10-14 - Test suites delete only through a guard

**Context:** While working #3, a helper in a new test suite ran `rm -rf` on relative paths before it had changed into its throwaway repo, and deleted tracked files from the real working tree on every test run. Nothing was lost (git restored them), but it would have been easy to lose uncommitted work.

**Decision:** Every delete in `tests/` goes through `safe_rm` (`tests/_safe_rm.sh`), which resolves the path and refuses anything outside the throwaway folders the suite registered with `safe_rm_allow`. The guard has its own suite.

**Why:** A structural check beats remembering to pin the working directory. Deleting inside temp folders stays possible, because the suites need it to clean up.

**Related:** PR #14
