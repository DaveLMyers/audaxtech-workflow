<!-- Docs-only change (pr-check's docs_only.py says so)? One paragraph is enough: what, why
     with Closes #N, that it is docs-only, and what you read through. Delete the sections below. -->

## What

<!-- What changed, in plain terms. -->

## Why

<!-- Link the issue: Closes #__ -->

## How it was verified

<!-- What you ran/tried, what the code review found and how it was resolved,
     what was deferred and why. "Tests pass" alone isn't the story. -->

## Checklist

- [ ] `bash tests/run-hook-tests.sh`, `run-toolchain-tests.sh`, `run-workissue-tests.sh`, `run-bootstrap-tests.sh` and `run-saferm-tests.sh` pass, and `claude plugin validate .` is clean
- [ ] Matches the linked issue's acceptance criteria
- [ ] Tests added/updated for any real logic
- [ ] Self-reviewed the diff; independent review run (see pr-check)
- [ ] Docs updated if behavior or workflow changed
