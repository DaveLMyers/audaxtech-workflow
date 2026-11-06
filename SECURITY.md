# Security policy

## Reporting a vulnerability

Please report security problems privately, not in a public issue or pull request.

Use GitHub's private reporting: open this repository's **Security** tab, choose
**Report a vulnerability**, and describe the problem and how to reproduce it.
Only the maintainers can see the report.

If the **Report a vulnerability** button is missing, private reporting has not
been switched on for the repository yet. In that case open a public issue that
says only "I have a security report, please enable private reporting", with no
details, and the maintainer will follow up.

## What counts

This plugin runs shell scripts, Python helpers and Claude Code hooks on your
machine, and it can create things on GitHub through the `gh` command line tool.
The most useful reports are about:

- a hook or script that can be made to run something unintended, or to read or
  delete files outside the project it was asked to work in
- the merge gate or wrong-repository guard failing to block when it should
- a script or template that writes a secret or personal data somewhere public

## What to expect

This is a one-person project, so replies are best effort and no response time
is promised. A confirmed problem is fixed on `main` and shipped in the next
release, and you are credited if you want that.

## Supported versions

Only the latest released version (see `version` in
`.claude-plugin/plugin.json`) receives fixes.
