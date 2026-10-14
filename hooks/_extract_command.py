#!/usr/bin/env python
# Shared by the plugin's PreToolUse hooks: reads a Bash-tool hook-input payload
# from stdin and prints tool_input.command, SANITIZED.
#
# Why sanitized: the hooks decide by regex whether a command "is" a `gh pr
# merge` or a mutating `git ...`. Matching raw text also matches commands that
# merely MENTION those words - a commit message, a PR body, an echo, a grep
# pattern - and wrongly denies them. So text that cannot execute is
# neutralized (the word after `gh`/`git` is glued on with `_`, so the regexes
# no longer see a command) before the hooks match.
#
# Inert (neutralized):  '...'   "..."   and heredoc bodies.
# Live (left intact, because the shell really runs it):
#   - a quoted span handed to a wrapper:  -c '...'  -Command '...'  eval '...'
#   - "..." containing $( ) or backticks (command substitution runs)
#   - a heredoc whose command is a shell/interpreter (bash <<EOF ...)
# Design rule: when unsure, leave it matchable. A false deny is an annoyance;
# a missed merge-gate is the failure this hook exists to prevent.
import json
import re
import sys

WRAPPER_BEFORE = re.compile(r"(?:^|[\s;&|(])(?:-c|-Command|-command|eval)\s*$")
INTERPRETER = re.compile(r"\b(?:ba|z|da|k|c)?sh\b|\beval\b|\bsource\b|\bpython3?\b|\bpowershell\b|\bpwsh\b|\bnode\b")
HEREDOC = re.compile(
    r"(?P<head><<-?[ \t]*(?P<q>['\"]?)(?P<tag>[A-Za-z_][A-Za-z0-9_]*)(?P=q)[^\n]*\n)"
    r"(?P<body>.*?)"
    r"(?P<tail>\n[ \t]*(?P=tag)[ \t]*(?=\n|$))",
    re.S,
)


def neutralize(text):
    """Stop `gh <x>` / `git <x>` inside inert text from reading as a command."""
    return re.sub(r"(?<![\w.-])(gh|git)\s+", lambda m: m.group(1) + "_", text)


def _heredocs(cmd):
    def repl(m):
        line_start = cmd.rfind("\n", 0, m.start()) + 1
        if INTERPRETER.search(cmd[line_start:m.start()]):
            return m.group(0)  # body is executed by an interpreter: keep live
        return m.group("head") + neutralize(m.group("body")) + m.group("tail")
    return HEREDOC.sub(repl, cmd)


def sanitize(cmd):
    cmd = _heredocs(cmd)
    out = []
    tail = ""  # recent output, used to see what precedes a quoted span
    i, n = 0, len(cmd)
    while i < n:
        c = cmd[i]
        if c == "\\" and i + 1 < n:
            out.append(cmd[i:i + 2]); tail = (tail + cmd[i:i + 2])[-40:]; i += 2
            continue
        if c in "'\"":
            j = i + 1
            while j < n:
                if cmd[j] == "\\" and c == '"' and j + 1 < n:
                    j += 2
                    continue
                if cmd[j] == c:
                    break
                j += 1
            if j >= n:  # unterminated quote: can't reason about it, leave as is
                out.append(cmd[i:])
                break
            span = cmd[i + 1:j]
            live = bool(WRAPPER_BEFORE.search(tail)) or (c == '"' and ("$(" in span or "`" in span))
            # A live span is code the shell will run: drop its quotes so the hooks'
            # "starts a command" regexes (which want whitespace or ; & | before
            # the word) can see it. An inert span keeps its quotes.
            piece = (" " + span + " ") if live else (c + neutralize(span) + c)
            out.append(piece); tail = (tail + piece)[-40:]
            i = j + 1
            continue
        out.append(c); tail = (tail + c)[-40:]; i += 1
    # `$(cmd)`, `(cmd)` and `cmd` in backticks all start a command, but the
    # hooks' regexes only recognise whitespace or ; & | before a command word.
    # Turn those openers into separators so such commands are matchable.
    return re.sub(r"\$\(|\(|`", " ; ", "".join(out))


def main():
    try:
        data = json.load(sys.stdin)
    except Exception:
        data = {}
    print(sanitize(data.get("tool_input", {}).get("command", "")))


if __name__ == "__main__":
    main()
