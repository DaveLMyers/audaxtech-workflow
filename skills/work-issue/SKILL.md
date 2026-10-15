---
name: work-issue
description: >-
  Takes a GitHub issue from Ready to ready-to-merge by following the project's
  workflow end to end, so the user never has to spell it out: check repo state,
  read the issue and CONTRIBUTING, move the board card to In Progress, branch,
  implement with tests, let the user try it before anything is pushed, open the PR,
  run pr-check, and hand back for the merge decision. Use whenever the user says
  to work, start, pick up, tackle or implement an issue ("work issue #90",
  "let's start on #12", "pick up the confetti issue") in a project that has
  .claude/workflow.json or a CONTRIBUTING.md. It never merges without an explicit yes.
---

# Work an issue

The user will usually say one sentence, such as "work issue #90". This file is
everything they would otherwise have to say. **The project's CONTRIBUTING.md is
canonical** for project rules (branch and commit format, docs rules, testing);
this skill orchestrates and defers to it. Run the helper scripts from this
skill's base directory (`scripts/`).

## 0. Is this the right job?
- Needs an issue number, or a title that matches exactly one open issue
  (`gh issue list --search`). If several match, ask which.
- A `type:research` issue produces a written finding, not feature code: do the
  investigation, put the finding where the issue says, and ask before filing follow-ups.
- Closed issue: ask before reopening the idea.

## 1. Pre-flight (read-only; stop at any red flag)
1. **Where am I.** `git -C <repo> status -sb`, `branch --show-current`,
   `worktree list`. The user may run concurrent sessions: if the tree is dirty,
   or the branch is neither the base branch nor this issue's own branch, stop and ask.
2. **Is it already in progress?** `gh issue view N --json state,assignees,labels,title,body`
   and `gh pr list --search "#N in:body" --state open`. An open PR or an existing
   branch for it means ask whether to continue that work.
3. **Read:** the issue, `.claude/workflow.json`, the whole CONTRIBUTING.md, CLAUDE.md,
   the project's `run` skill, and any doc the issue links. Check `docs/DECISIONS.md`
   for anything that already settles the question.
4. **Say your plan in about five lines:** what you will build, the acceptance
   criteria, where it likely touches, anything unclear. **Proceed unless** there are
   no acceptance criteria, an open design question, a conflict with DECISIONS.md,
   or a choice that is the owner's taste. Then ask those specific questions in one batch.

## 2. Start
1. Bring the base branch current: `git -C <repo> fetch`, `checkout <base>`, `pull --ff-only`.
2. **Move the card to In Progress:** `python scripts/board_status.py N in_progress`.
   It adds the issue to the board if it is missing, uses the ids in `workflow.json`,
   and reads the status back. A non-zero exit means stop and report it; do not
   carry on assuming the board is right. No board configured: skip and say so.
3. **Branch:** `python scripts/branch_name.py --title "<issue title>" --labels "<labels>" --number N --pattern "<git.branch_pattern>"`,
   then `git -C <repo> checkout -b <name>`. Use `git -C`, never a lingering `cd`.

## 3. Implement
- Follow CONTRIBUTING and the stack conventions. **Follow the acceptance criteria
  literally, including the "no X" lines** (for example "no GAMEPLAY.md change").
- Logic with branching or edge cases gets tests in the same change; prefer a pure
  function. Run the suite and the boot/import check using the project's `run` skill.
- Commits: Conventional Commits, scope from the area label, reference `(#N)`, small
  and logical, with the attribution trailer the environment specifies. **Stage files by
  name** (`git add <paths>`), not `git add -A`, so nothing unintended is included. Never
  commit to the base branch; never force-push.
- Apply the docs rules the issue and CONTRIBUTING state (a DECISIONS entry for a
  judgment call, and so on).
- Something out of scope turns up (a bug, a gap, follow-up work): note it and file it as
  its own issue; fix it inline only if this change introduced it.
- **A stray design idea from the user** (a future feature or tweak that is not part of this
  issue) is not an out-of-scope defect, so do not file an issue for it. Check for
  `docs/design-ideas.md`:
  - **It exists:** log the idea there in the user's own words with status `raw`, putting your
    own analysis under "Context", as its own small docs change (not folded into the current
    PR). File an issue only when the user says to, or once the idea is `adopted`.
  - **It does not exist:** say so and offer to add it (`project-bootstrap`'s upgrade mode
    adds the missing game docs). Do not quietly file an issue instead.
  This matches the line in the game CLAUDE.md template: stray design thoughts go in
  `docs/design-ideas.md`, not into the design docs and not straight into the backlog.
- Read your own diff before moving on.

## 4. Gate 1: the user tries it before anything is pushed
Tests and the boot check must be green first. Then:
- **Player-facing change:** launch it (check for an already-running instance
  first, per the `run` skill), tell the user exactly what to try, and wait.
- **Otherwise:** say what you verified and how.
Either way, **ask before pushing.** Do not decide a change is too simple to need
the ask. If the user says to skip playing and push, do that.

**Visual or feel changes** (an effect, animation, layout, timing, anything judged by
eye) almost always take several rounds, so plan for that up front instead of one knob
per launch:
- **Ask for all the feedback at once.** After each launch ask about everything that
  could need changing (size, duration, speed, direction, color, anything else?), not
  just the thing you guessed was wrong.
- **Keep the tunables easy to name.** Put them as named constants in one obvious block
  and name them to the user, so "bump PIECE_SIZE" is a complete instruction.
- **Relaunch carefully.** Check for an already-running instance before every relaunch
  (the `run` skill says how). The window closing, or a "game closed" notification, is
  not approval or rejection: it only means the session ended. Wait for the user's
  actual answer.
- **Call out what was not re-played.** Any change made after the user's last play-test
  (even a "behavior-neutral" review fix) is either offered for a final replay or named in
  the PR body as not re-played.

## 5. Open the PR
- **Run each git step as its own simple command**: `git add <paths>`, then
  `git commit -F <message-file>`, then `git push -u origin <branch>`. Never chain them, and
  never bundle them with reads such as fetching the PR template: a compound command is
  harder for a permission layer to judge and harder for the user to approve.
- **If the permission layer blocks a step** (for example an auto-mode classifier denial
  that gives no reason), that is not this plugin: its hooks always say why they denied.
  Stop. State exactly which command was blocked and that nothing ran, give the user the
  exact commands to approve or run themselves, and wait. Do not retry variants, do not
  route around it (another tool, a script, a different shell), and do not change
  permission settings yourself. The user's yes at Gate 1 is not seen by the permission
  layer, so a push can still be refused after it.
- Push with `-u`. Write the **PR body to a file** (never inline in a shell command:
  backticks and quotes get eaten, and the merge-gate hook reads command text). Use the
  repo's PR template: what changed, why (`Closes #N`), how it was verified (be
  specific, including what the user tried), what was not verified, checklist.
- If the session has PR tools (`get_status`, `bind_pr`), bind the PR and read CI
  through them. **Do not poll CI** in a loop or with repeated `gh` calls, but **do look**:
  read the status (`get_status`, or one `gh pr checks`) at the start of every turn while a
  PR is open, and act on what it says. "Do not poll" never means "do not look".
- **Waiting for CI.** Offer the app's PR monitor (auto-fix) once: it wakes the session with a
  `<ci-monitor-event>` when CI fails, so there is nothing to poll. With it off, the user's
  next message is the wake-up: check status then. Pending CI is not a reason to tell the
  user you are stuck; say it is pending and what happens next.
- **A standing instruction such as "merge once CI is green"** is the user's yes for that PR
  (Gate 2 still applies to any other PR). On each wake-up check status: green means merge
  and do the section 8 cleanup; red means report it (or fix it, if auto-fix is on) and do
  not merge; pending means say so and wait.
- A background-task or "game closed" notification is not an answer from the user. Do not
  act on it as approval, rejection or a reply to your question.
- The card should now read In Review (a built-in workflow does it). Check with
  `python scripts/board_status.py N --read`; if it did not move, set `in_review`.

## 6. pr-check
Run the `pr-check` skill on the PR. Fix what it finds in this PR; defer only with a
reason and, where it needs a decision, an issue. Update the PR body with the results
(again from a file), then **re-read the live body** to be sure nothing was garbled.

## 7. Gate 2: the merge decision
Report: the PR link, CI state, what `pr-check` found and how each finding was
handled, what remains unverified, and exactly what merging will do. **Ask.** A yes
in an earlier turn, or for a different PR, is not a yes for this one.

## 8. After an explicit yes
1. `gh pr merge N --squash`. (The plugin's merge gate checks CI; do not work around a denial.)
2. **Verify:** PR is MERGED, the issue is closed, and the card is Done
   (`board_status.py N --read`; set `done` if the automation missed, which it has before).
3. Back to the base branch: `checkout`, `pull --ff-only`, delete your local branch
   (`-D`: a squash merge is not an ancestor), and confirm the remote branch is gone with
   `git ls-remote --heads origin <branch>` (remote-tracking refs can be stale, so do
   not trust `git branch -r`). `git fetch --prune`.
4. Turn off auto-fix if it was on. Report the follow-ups filed and what is next.

## Never
Merge without an explicit yes. Push to or commit on the base branch. Force-push.
Skip Gate 1. Work around a permission block. Touch another issue's card. Change repo settings. Delete a branch you
did not create. Leave a `cd` into another repo (use `git -C`).

## Sharp edges, learned from real incidents
- `gh issue create` does not put the issue on the board; `board_status.py` does.
- `gh project item-list` paginates and lags: never use it to find an item.
- A JSON file you edit (`workflow.json`) must stay valid: a typo once silently
  disabled the hooks. Validate it after any edit.
- Windows LF/CRLF warnings are noise. Stale remote-tracking refs are not remote branches.
- Several sessions can share one working folder: whichever branch is checked out is what every session in it sees, and uncommitted work belongs to the session that made it. Never touch another session's branch or changes.
- Without `.claude/workflow.json`, skip the board steps, say so, and rely on CONTRIBUTING.md.
