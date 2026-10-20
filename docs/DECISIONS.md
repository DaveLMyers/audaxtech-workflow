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

## 2026-10-20 - macOS on request is the standard for every project the plugin sets up

**Context:** The entry below covered only this repo's own `ci.yml` and said so. Projects the plugin bootstraps still got macOS on every PR, and Phoenix, which queued 8+ minutes on it, had to be fixed by hand (its issue #92).

**Decision:** macOS on request is part of the workflow, not a per-repo choice. The bootstrap CI template renders a `workflow_dispatch` trigger with a boolean `macos` input and builds the job matrix from it (`{{CI_MATRIX_ALWAYS}}` without macOS entries, `{{CI_MATRIX_WITH_MACOS}}` with them); entries whose `os` starts with `macos` are the on-request ones. `ci.matrix` still names everything CI can run. `upgrade_check.py` reports a workflow that triggers on `pull_request` and names a macOS runner without that input, as `macos_every_pr`, and upgrade mode offers the change.

**Why:** Same reason as the entry below: PR feedback should not wait on a runner queue, and macOS minutes cost ten times as much. A matrix built from the trigger leaves no check at all when macOS is not asked for, so the merge-gate hook (which denies anything but pass or skipping) needs no change; a job-level `if` cannot read the matrix and would leave a skipped check. No `workflow.json` switch was added: the owner wants this everywhere, and a switch can come later if someone needs macOS on every PR.

**Trade-off:** a macOS-only break can merge until someone asks for that run. Detection is by text (`pull_request` plus a `macos-` runner, comments ignored), so a workflow built another way can be missed or flagged wrongly; upgrade mode says to read the file first.

**Related:** #39, supersedes the scope note in #37

---

## 2026-10-20 - macOS CI runs only on request

**Context:** The macOS runner regularly queued for ~10 minutes, holding up every PR.

**Decision:** CI runs Linux and Windows on every PR and push to `main`. The macOS job runs only via manual `workflow_dispatch` with `macos=true`, e.g. before a release.

**Why:** Faster PR feedback; macOS-only breaks (like the `timeout` one above) are rare and are caught at release time instead. Trade-off: a macOS regression can now merge unnoticed until someone asks for that run.

**Related:** issue #37

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

---

## 2026-10-15 - board_status.py: --repo takes a folder or owner/name

**Context:** Issue #5: the script found the project's `.claude/workflow.json` only by searching up from the current folder, but `work-issue` told sessions to run it from the skill's own folder, which is not inside the project.

**Decision:** `--repo` accepts either the project's folder or `owner/name` (a value that is an existing folder is the project; otherwise it must contain a `/`). `--project-dir` stays as the same thing under its older name. The skill now passes `--repo <path to the project>`, and the "no workflow.json" error names the folders it searched and suggests `--repo`.

**Why:** Overloading `--repo` matches how the issue asked for it and keeps the old `owner/name` form working; a folder is unambiguous because a real folder wins. Anything that is neither a folder nor a strict `owner/name` (an owner starts with a letter or digit, then exactly one `/`) is rejected, so a mistyped path such as `../projx` fails clearly instead of becoming a GitHub 404. An explicit folder that does not exist is an error rather than a search from its nearest existing parent.

**Related:** #5

---

## 2026-10-15 - New projects keep LF in the repo and in the working tree

**Context:** Issue #6: a Windows-first project (critter-wars) had a CRLF `docs/DECISIONS.md`, so appending an entry needed hand-built CRLF text, every new file produced "LF will be replaced by CRLF" warnings, and different tools handled the endings differently, risking mixed endings in one file.

**Decision:** `project-bootstrap` writes `.gitattributes` with `* text=auto eol=lf` (LF in the repo and in the working tree on every OS), CRLF only for `*.ps1`, `*.bat` and `*.cmd`, and binaries untouched; and an `.editorconfig` with charset, LF, final newline and trimmed whitespace but no indentation rules (those depend on the language, e.g. GDScript uses tabs). The CONTRIBUTING template gets a short Line endings section. Existing repos are offered the files through upgrade mode and never overwritten. A repo whose files are already CRLF keeps CRLF for appends until a separate `git add --renormalize .` commit converts them.

**Why:** One ending everywhere means an editor, a shell append and a tool all produce the same bytes, which is the whole fix; LF is also the only ending bash scripts tolerate. The cost is that Windows-only tools which insist on CRLF need an explicit rule, which the CRLF entries cover. This is the same rule this repo already uses.

**Related:** #6

---

## 2026-10-15 - Docs-only PRs get a lighter description and review, never a lighter process

**Context:** Issue #7: a single new 33-line markdown file went through the full issue, board, branch, commit, push, PR, review, merge and cleanup sequence, and CONTRIBUTING says there are no exceptions for small work. The owner chose the middle path.

**Decision:** Every tracked step stays (issue, board move, branch, PR, green CI, the owner's explicit yes to merge). For a docs-only change, `pr-check` and `work-issue` use a one-paragraph PR description and a quick read-through of the diff in place of the full description and `/code-review`. "Docs-only" is decided by a script (`skills/pr-check/scripts/docs_only.py`), not by feel: every changed file must be prose under `docs/` or a root README, CONTRIBUTING, CHANGELOG or LICENSE. A skill's `SKILL.md`, an agent, a template, `CLAUDE.md`, a script, a test or any config is never docs-only, even when it is Markdown, because it changes what runs or what Claude does. When unsure, the full process applies.

**Why:** The tracking steps are what the no-exceptions rule protects; the savings are in the description and the review. A script keeps "docs-only" from becoming a judgment call that quietly widens.

**Related:** #7

---

## 2026-10-15 - Docs are written for a human skim and a cold-start AI session

**Context:** The docs this workflow produces (READMEs, PR descriptions, DECISIONS entries) had grown long in the wrong places, such as per-suite test counts that went stale within a day, and the owner asked what a reader, human or AI, actually needs.

**Decision:** CONTRIBUTING (this repo's and the bootstrap template's) gets a short "Writing docs" section: put in what is expensive to rediscover (why, non-obvious constraints, what is and is not trustworthy, where things live); leave out what goes stale or can be read from the source (counts, file lists, command output) and link instead; lead with the answer; say what is not verified; length follows need. `pr-check`'s docs step repeats the "no copied counts" rule and bootstrap's README guidance names what a README starts with. Skills and CLAUDE.md files are not covered by this: they load into every session, so they stay short on their own terms.

**Why:** A reader has little time and an AI session has only the files; both are served by the reasons and the honest gaps, and both are hurt by facts that quietly become wrong.

**Related:** #21

---

## 2026-10-15 - The plugin has a version, starting at 0.1.0

**Context:** Earlier the version was left empty "for now". With no version, installed copies treat every commit on `main` as a new version, there is no way to hold a bad commit back, and a project cannot tell which copy it has. Three projects now depend on the plugin.

**Decision:** `plugin.json` carries a `version`, starting at 0.1.0 (0.x while the README lists unverified flows). Projects get changes only when it is bumped, in a small release PR followed by a `vX.Y.Z` tag. CI fails if the version is missing or not semver. This replaces the earlier "no version".

**Why:** The bump is a deliberate release gate, so a bad commit on `main` reaches no project until a release. The cost is that a fix merged without a bump ships nothing, which CONTRIBUTING says plainly. A project still cannot stay on an older version while others take a newer one.

**Related:** #23

---

## 2026-10-20 - Project-specific PR checks live in CONTRIBUTING.md, never in a copy of pr-check

**Context:** Phoenix had its own `.claude/skills/pr-check`, written before the plugin existed. It won the plain `pr-check` name, so the plugin's later steps (docs-only path, blind-check agents, `workflow.json` toggles) never ran there, and it drifted. It existed because a project's own checks (cross-platform and translatable-text habits, feel tests) had nowhere to go but a fork. The upgrade check reported "nothing missing" with the copy in place.

**Decision:** `pr-check` reads the project's own checks from its CONTRIBUTING.md: the items under a `### Project PR checks` subsection, plus any line that begins with bold `PR check:` next to the rule it enforces (the Godot stack modules use these). Each names the step it belongs to and adds to the six standard steps, never replaces one. A project-level copy of a plugin skill is unsupported, and `upgrade_check.py` lists one under `shadowing_skills` so an upgrade can offer to move what is project-specific into CONTRIBUTING.md and remove the copy.

**Why:** The plugin stays the single owner of the process, so an improvement made while working on one project reaches all of them on the next release; project rules stay with the project's other rules. The cost: a project check is prose that `pr-check` follows, not something a script enforces, and a project cannot override or skip a standard step (use `components.*` for that).

**Related:** #33
