#!/usr/bin/env python
"""Block until every CI check on a pull request has finished, then print the verdict and exit.

Usage:
  wait_for_ci.py <pr-number> [--repo PATH|owner/name] [--interval SECONDS] [--max-wait SECONDS]

Run it with the shell tool's run_in_background and then end the turn. The app delivers one
notification when it exits, so the session wakes on a green run as well as a red one, with no
message from the owner. No model runs while it waits and nothing is sent anywhere but GitHub:
the cost is one wake-up, not one per poll. It only runs while the session is open.

  --repo PATH        the project's folder (gh is asked from there)
  --repo owner/name  the GitHub repo
  --interval         seconds between polls (default 30)
  --max-wait         give up after this many seconds (default 1800); this is what stops it
                     waiting forever on a repo with no workflows, where gh reports no checks

A PR with no checks yet reports an empty list, so an empty list counts as "not started",
not "done". `gh pr checks` exits non-zero when checks are pending or failing, so the exit
code is ignored and the JSON on stdout is what counts.

Prints one line: "green: ...", "red: ...", "timeout: ..." or "error: ...", then (for green and
red) the failing check names. On wake, read the status once (get_status or one `gh pr checks`)
and act; do not trust this line alone.

Exit codes: 0 all checks passed (skipped checks count as passed) | 1 at least one failed or
was cancelled | 2 bad usage | 3 gh kept failing | 4 timed out with checks still pending or none
"""
import json
import os
import re
import shlex
import shutil
import subprocess
import sys
import time

OWNER_NAME = re.compile(r"^[A-Za-z0-9][A-Za-z0-9-]*/[A-Za-z0-9_.-]+$")
MAX_GH_ERRORS = 5  # consecutive polls where gh gave no usable JSON


def gh_command():
    """How to invoke gh. AUDAX_GH overrides it (a command, may include arguments); the
    tests use it to substitute a fake. Otherwise resolve gh through PATH/PATHEXT."""
    override = os.environ.get("AUDAX_GH")
    if override:
        return shlex.split(override)
    return [shutil.which("gh") or "gh"]


def usage(msg):
    sys.stderr.write("wait_for_ci: " + msg + "\n")
    sys.exit(2)


def parse_args(argv):
    pr, repo, interval, max_wait = None, None, 30.0, 1800.0
    i = 0
    while i < len(argv):
        a = argv[i]
        if a in ("--repo", "--interval", "--max-wait"):
            if i + 1 >= len(argv):
                usage(a + " needs a value")
            v = argv[i + 1]
            i += 2
            if a == "--repo":
                repo = v
            else:
                try:
                    n = float(v)
                except ValueError:
                    usage(a + " needs a number, got " + repr(v))
                if n < 0:
                    usage(a + " cannot be negative")
                if a == "--interval":
                    interval = n
                else:
                    max_wait = n
        elif a.startswith("-"):
            usage("unknown option " + a)
        elif pr is None:
            pr = a
            i += 1
        else:
            usage("unexpected argument " + a)
    if pr is None or not pr.isdigit():
        usage("a pull request number is required")
    return pr, repo, interval, max_wait


def poll(pr, repo, cwd):
    """One look at the checks: a list of {name, bucket}, or None if gh gave no usable JSON."""
    args = ["pr", "checks", pr, "--json", "name,bucket"]
    if repo:
        args += ["--repo", repo]
    try:
        r = subprocess.run([*gh_command(), *args], capture_output=True, text=True, cwd=cwd)
        data = json.loads(r.stdout)
    except (OSError, ValueError):
        return None
    if not isinstance(data, list):
        return None
    return [c for c in data if isinstance(c, dict)]


def main(argv):
    pr, repo, interval, max_wait = parse_args(argv)
    cwd = None
    if repo and not OWNER_NAME.match(repo):
        if not os.path.isdir(repo):
            usage("--repo is neither owner/name nor a folder: " + repo)
        cwd, repo = repo, None

    start = time.monotonic()
    errors = 0
    last = []
    while True:
        checks = poll(pr, repo, cwd)
        if checks is None:
            errors += 1
            if errors >= MAX_GH_ERRORS:
                print("error: gh gave no usable answer %d times in a row" % errors)
                return 3
        else:
            errors = 0
            last = checks
            if checks and not any(c.get("bucket") == "pending" for c in checks):
                bad = [c.get("name", "?") for c in checks if c.get("bucket") in ("fail", "cancel")]
                if bad:
                    print("red: %d of %d checks did not pass" % (len(bad), len(checks)))
                    for name in bad:
                        print("  " + name)
                    return 1
                print("green: all %d checks passed" % len(checks))
                return 0
        if time.monotonic() - start >= max_wait:
            if last:
                pending = [c.get("name", "?") for c in last if c.get("bucket") == "pending"]
                print("timeout: still pending after %ds: %s" % (max_wait, ", ".join(pending)))
            else:
                print("timeout: no checks appeared after %ds" % max_wait)
            return 4
        time.sleep(interval)


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
