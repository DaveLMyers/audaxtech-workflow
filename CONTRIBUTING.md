# Contributing to audaxtech-workflow

How work flows through this repo: branching, commits, issues, reviews. It
applies solo today and is meant to keep working unchanged once other people
join - the goal is not having to renegotiate process later.

## Backlog & issue tracking

All work is tracked as GitHub Issues on the [project board](https://github.com/users/DaveLMyers/projects/4) -
**no exceptions for small work.** A one-line docs fix gets a one-line issue,
not a skipped one. The point isn't ceremony: anyone (a collaborator, or
future-you) can see what's in flight and why without reading git log. Board
columns:

- **Backlog** - captured, not yet refined or ready to pick up.
- **Ready** - scoped enough that someone could start it right now.
- **In Progress** - actively being worked on.
- **In Review** - PR open, awaiting review/merge.
- **Done** - merged to `main`.

### Labels

- `type:feature`, `type:bug`, `type:chore`, `type:docs`, `type:research` - what kind of work.
- `area:skills`, `area:hooks`, `area:agents`, `area:bootstrap` - which part of the plugin it touches (`area:bootstrap` is the `project-bootstrap` skill and its templates and board script).
- `priority:p1` (now), `priority:p2` (soon), `priority:p3` (later) - rough
  urgency, not a commitment.

Every issue gets one `type:` and at least one `area:` label. Priority is
optional at Backlog; add it when an issue moves to Ready.

### Scripting the board

GitHub Projects v2 board (project number `4`, owner
`DaveLMyers`, project id `PVT_kwHOAGjIOM4BnFh8`). Things the CLI's help doesn't tell
you (see also the global `github-projects-workflow` skill):

- **`gh issue create` does not add the issue to the board.** Follow it with
  `gh project item-add 4 --owner DaveLMyers --url <issue-url>`.
- **`gh project item-list` defaults to a 30-item page** and silently returns
  "not found" past that. Pass `--limit 200`.
- **No built-in "work started" workflow.** Moving a card to In Progress is a
  manual step (the person or agent starting the work does it).
- **"Pull request merged -> Done" can silently fail to fire.** Treat any
  drift between the board and real issue/PR state as a signal to fix by hand.
- Field ids for `gh project item-edit`:
  Status field `PVTSSF_lAHOAGjIOM4BnFh8zhlrwac` (Backlog `2924f90d`, Ready
  `2f1d6169`, In Progress `16d7cb92`, In Review
  `84dfbd04`, Done `1bf2fa9f`); Priority field
  `PVTSSF_lAHOAGjIOM4BnFh8zhlrwhM` (P1 `859f7471`, P2 `ba9db066`, P3 `f8dc6f1b`).
  An item's own `PVTI_...` id comes from `gh project item-list 4
  --owner DaveLMyers --limit 200 --format json`, matched on
  `.items[].content.number`.

### Writing issues

Use the issue templates. A good issue names the observable outcome, not the
mechanism - "the report downloads as a CSV" rather than "write exportCsv()".

## Branching model

**GitHub Flow.** `main` is always working (buildable, bootable).

- Branch off `main` for every change, named `<type>/<short-description>`,
  e.g. `feature/work-issue-ci-guidance`, `fix/board-status-repo-flag`.
- Open a PR against `main` early if you want feedback; draft PRs are fine.
- Merge via **squash merge** - one commit per logical change on `main`.
  Delete the branch after merge.
- Solo, a PR for something trivial can be pure overhead - use judgment, but
  default to a PR for anything nontrivial so the habit is already in place.

## Commit messages

[Conventional Commits](https://www.conventionalcommits.org/):

```
<type>(<scope>): <short summary>

<optional body - the why, not the what>
```

Types: `feat`, `fix`, `chore`, `docs`, `refactor`, `test`. Scope is optional
and usually matches an `area:` label.

## Line endings

Text files use **LF** in the repo and in the working tree (`.gitattributes` and
`.editorconfig` enforce it; only Windows-only scripts such as `*.ps1` are CRLF). Add to
a doc with your editor or the Edit tool, not by hand-typing carriage returns, and check
`git diff` shows only the lines you meant. A file that predates this and is still CRLF
keeps CRLF for appends until a separate `git add --renormalize .` commit converts it.

## Writing docs

Write for two readers: a person skimming, and an AI session starting cold in this repo (or
another project reading it). Both need the same things.

- **Put in what is expensive to rediscover:** why a decision was made, constraints that are
  not obvious from the code, what is and is not trustworthy, and where things live.
- **Leave out what goes stale or can be read from the source:** test counts, file lists,
  command output. Link to the code or CI instead.
- **Lead with the answer.** A README starts with what this is, how to use it and what to rely
  on; a PR description starts with what changed and why. Detail follows only if a reader needs it.
- **Say what is not verified,** plainly, in a short list.
- **Length follows need.** If a section only restates the code or another doc, link to it.

## Releasing

Installed copies compare `version` in `.claude-plugin/plugin.json`: projects receive changes
only when it changes, however many commits land on `main` (CI checks it is valid semver).
Merging without a bump ships nothing.

- Release in its own small PR: bump the version (patch for fixes, minor for new skills or
  behaviour; stay on 0.x while the README lists unverified flows), merge on green CI, then tag
  the merge commit `vX.Y.Z`.
- Then update installed copies: `claude plugin marketplace update audaxtech`, then
  `claude plugin update audaxtech-workflow@audaxtech`, and restart open sessions.

## Pull requests

- Reference the issue it closes (`Closes #12`) - **required**. If work
  started without one, open the issue before the PR, even if it's opened and
  closed in the same minute.
- Describe what changed and, if not obvious, why.
- If the PR makes a real judgment call (design, scope, process), add an
  entry to [docs/DECISIONS.md](docs/DECISIONS.md) **in the same PR**. Most
  PRs need none - only genuine judgment calls do.
- Include a screenshot or clip for anything visual.
- Self-review your own diff first.
- Run an independent code review (`/code-review`) before calling a PR ready
  to merge - a standing step, not something to ask for each time.
  Self-review catches "did I do what I meant to"; independent review catches
  "is what I meant to do correct." Address findings or note why one is
  deferred. **Calibrate effort to the change, both directions:** deeper for
  large/risky/wide changes, medium by default for real logic, lighter (or a
  quick sanity check) for doc-only edits, one-line typing fixes, config
  values, comments.
- A **docs-only** PR (the `pr-check` skill defines it and has a script that checks) may use a
  one-paragraph description and a quick read-through in place of the full review. Every
  tracked step still applies: the issue, the board, the branch, green CI, and the owner's
  yes to merge. A skill, template, `CLAUDE.md` or script is never docs-only.
- Before calling any PR ready to merge, run the `pr-check` skill (from the
  audaxtech-workflow plugin; it reads `.claude/workflow.json` and this file).
- CI (`.github/workflows/ci.yml`) runs the five suites in `tests/` on Linux
  and Windows for every PR and push to `main`; macOS runs only on request
  (`gh workflow run CI -f macos=true`), e.g. before a release. It is not yet configured
  as a *required* check in GitHub, so a red run is a hard "don't merge" on the
  honor system; this repo uses its own plugin's merge-gate hook (active
  because `.claude/workflow.json` exists), which enforces it for any Claude
  Code session by denying `gh pr merge` unless every check is green. It
  doesn't stop a merge clicked in the GitHub UI.
- Once collaborators join: require at least one approval and turn on required
  status checks and branch protection (free on a public repo).

## Testing

```
bash tests/run-hook-tests.sh        # the merge gate and cwd guard (fake gh, throwaway repos)
bash tests/run-toolchain-tests.sh   # the toolchain-run generator (fake tool served from localhost)
bash tests/run-workissue-tests.sh   # work-issue's helper scripts (fake gh)
bash tests/run-bootstrap-tests.sh   # project-bootstrap's upgrade check (throwaway repos)
bash tests/run-saferm-tests.sh      # the delete guard the suites use
claude plugin validate .            # manifest and layout
```

The suites are self-contained and clean up after themselves; CI runs the
five scripts on every OS. A change to a hook, a generator or a helper script
needs a case in the matching suite in the same PR. Skills, agents and
templates are prose: they are verified by actually using them (bootstrap a
scratch repo, run `work-issue` on a scratch issue), and the PR says what was
tried.

- If a change adds logic with real branching/edge cases, add or update tests
  in the same PR. Pure glue code doesn't need tests just to have tests.
- Prefer testing pure logic (inputs -> outputs, no environment) over anything
  needing a running app - faster, and doesn't break from unrelated changes.
- **Separation of duties for meaningfully complex logic:** whoever writes the
  implementation shouldn't be the sole author of the tests that grade it - a
  wrong mental model gets encoded twice and passes cleanly. Before calling
  tests done, run a blind check: a reviewer with *only* the spec writes what
  they'd expect tested, and another tries to build a subtly-wrong
  implementation that still passes every existing test. Close the gaps.
- A failing test blocks merge.

## Definition of done

Merged to `main`; the five test suites pass and `claude plugin validate .` is clean; tests pass and cover what the
change added; an independent review was run and its findings addressed or
explicitly deferred; the linked issue's acceptance criteria are met. "Done"
does not require polish beyond what the issue asked for - track follow-up
polish as its own issue.

## Plugin conventions

- **Hooks are inert without the marker.** Every hook must check
  `.claude/workflow.json` (via `hooks/_project_enabled.py`) and do nothing
  when it is absent or the component is switched off. A new hook needs a
  test for both the "enabled" and "inert" cases.
- **Nothing outward-facing without asking.** Skills that create things on
  GitHub (repo, board, labels) or on disk must say what they will do and wait
  for a yes first; keep that wording intact when editing them.
- **Scripts stay LF.** CRLF after a shebang breaks bash, and the hooks and test suites
  are bash (see "Line endings").
- **Test suites delete only through `safe_rm`.** `tests/_safe_rm.sh` refuses any
  delete outside the throwaway folders a suite registered with `safe_rm_allow`. Never
  call `rm` directly in a suite: an earlier helper deleted real files from the working
  tree that way.
- **Skills and docs describe each other.** The README table, a skill's
  SKILL.md and the templates it renders must agree. A change to one updates
  the others in the same PR, and a leftover template placeholder in rendered
  output is a bug.
- **Say what is verified.** The README's "What is verified, and what is not"
  section is part of the product; move an item out of "not yet verified" only
  when it has been run.

