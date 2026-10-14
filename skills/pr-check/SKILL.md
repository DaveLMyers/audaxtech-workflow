---
name: pr-check
description: Verifies a PR or backlog issue is actually ready to merge - not just "the code looks right." Runs an independent code review, checks that tests enforce the spec rather than mirror the implementation (using the blind-spec-reviewer and test-saboteur agents for complex logic), confirms the change was verified by actually running it, and checks docs stay current. Use before EVER telling the user a PR or issue is "done," "ready," or "ready to merge" in a project that has .claude/workflow.json or a CONTRIBUTING.md workflow - run it automatically as a standing step, not only when asked. Also trigger on "run pr-check," "is this PR ready," or "check this before we merge."
---

# PR readiness check

Self-review alone misses real bugs: the same mental model that wrote the code
is bad at spotting its own blind spots. This skill makes the separate checks
repeatable and lets them survive past any one conversation.

It is a thin orchestrator. **The project's CONTRIBUTING.md is canonical** for
everything project-specific (commands, doc rules, label scheme, definition of
done). If this file and CONTRIBUTING.md disagree about the project, the
project wins.

## Before you start

- Read `.claude/workflow.json` if present: it says which parts of the workflow
  this project uses (`components.decisions_log`, `review.independent_review_required`,
  `review.default_effort`, ...). Skip a step only when its component is off,
  never because the change looks simple.
- Read the project's CONTRIBUTING.md if you haven't this session, and the
  project's own `run` skill for how to boot and test it.
- Identify the PR (`gh pr view`) and the issue it closes.

## When to run

Before saying a PR, issue, or backlog item is done, ready, or ready to merge.
Whether or not the user asked.

## The checklist (in order; each catches a different failure mode)

### 1. It runs
Boot or run the project using its `run` skill / README. For anything with a
runtime, prefer the real thing over a headless sanity check at least once per
PR - some failures only show up in the real environment. Then check CI is
actually green on the PR (`gh pr checks`), not just that it passed locally. A
red run is a "don't merge"; the plugin's merge hook enforces this for
`gh pr merge` in sessions where it is active.

### 2. Tests pass, and test the right thing
Run the suite. Then decide whether the change has **meaningfully complex
logic** (real branching, an algorithm, rules that interact, math, spawn/
scoring/selection logic - not a getter or glue code). If it does, and the
implementation and its tests were written by the same author (you, in most
cases), run the blind check:

1. **Spec-only pass.** Spawn the `blind-spec-reviewer` agent. Give it ONLY the
   spec text (issue body, acceptance criteria, the relevant design-doc excerpt)
   pasted into the prompt - never the implementation, never the tests. It
   returns what *should* be tested.
2. **Compare.** Check that list against the actual tests. Every gap is either a
   missing test or a spec ambiguity to resolve.
3. **Saboteur pass.** Spawn the `test-saboteur` agent with paths to the spec,
   the implementation and the tests. It returns subtly wrong implementations
   the current tests would still accept, each with the test that would catch it.
4. **Close the gaps.** Add the missing tests (and fix real bugs they expose).
   Re-run the suite.

Set the agents' model deliberately by task: both are reasoning-heavy, so keep
them at full capability. Skip this step only for logic with no real decision
points, and say you skipped it and why.

### 3. Independent code review
Run `/code-review` on the PR, unless `review.independent_review_required` is
false. Calibrate effort to the *kind* of change - does it have decision logic
to get wrong - not a feeling about diff size: `review.default_effort`
(medium unless set) for real logic; deeper for large, risky or wide changes;
lighter for doc-only edits, config values, comments, one-line typing fixes.
Fix findings in code this PR itself introduced; file a separate issue only when
a finding needs its own design decision or overlaps future work. If you defer
something, say why in the issue and in a code comment at the site.

### 4. Verified live, not just read
For anything user-facing, actually run and exercise it - click it, call it,
read its output - rather than reasoning from the code. Reading proves what you
intended; running proves what happens. Where a human could sanity-check it
hands-on, **ask whether they want to verify it first** before push/merge. Don't
self-exempt a change from that ask because it looks simple.

### 5. Docs stay current
If the PR changes anything a doc describes (README status, CONTRIBUTING
workflow, behavior docs), update it in the same PR. If it made a real judgment
call and `components.decisions_log` is on, add an entry to `docs/DECISIONS.md`
in the same PR. Follow any extra doc rules in the project's CONTRIBUTING.md.

### 6. The PR description tells the whole story
What changed, why (link the issue with `Closes #N`), and *how it was verified*:
what was run, what the review and the blind check found and how each finding
was resolved, what was deferred and why. A reader should be able to trust the
PR was checked, not just be told so.

## Only after all six

Then it is fair to tell the user the PR is ready to merge, and to surface the
merge decision. If you're unsure whether a step applies, do it - the cost of an
unnecessary check is small, and the cost of a merged bug a check would have
caught is what this skill exists to avoid.
