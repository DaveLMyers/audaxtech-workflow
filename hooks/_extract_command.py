#!/usr/bin/env python
# Shared by the PreToolUse hooks under tools/hooks/: reads a Bash-tool
# PreToolUse hook-input payload from stdin and prints tool_input.command.
# Pulled out so the JSON-parsing logic lives in exactly one place instead
# of being copy-pasted into every hook that needs it.
import sys
import json


def main():
    try:
        data = json.load(sys.stdin)
    except Exception:
        data = {}
    print(data.get("tool_input", {}).get("command", ""))


if __name__ == "__main__":
    main()
