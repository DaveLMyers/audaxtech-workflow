#!/usr/bin/env python
"""Derive a branch name from an issue: <type>/<short-slug>.

Usage:
  branch_name.py --title "feat(board): a swappable pop effect ..." \
                 --labels "type:feature,area:board" [--pattern "{type}/{slug}"] [--number 90]

Rules (deterministic, so two sessions name the same issue the same way):
  type  <- the issue's `type:` label: feature -> feature, bug -> fix,
           chore -> chore, docs -> docs, research -> research. No type label -> chore.
  slug  <- the title with its conventional prefix ("feat(board):") and any
           parenthesised text removed, lower-cased, split on non-alphanumerics,
           small stop words dropped, first 5 words joined with "-", max 40 chars.
           Nothing left -> "issue-<number>".
  The pattern (from .claude/workflow.json git.branch_pattern) may use
  {type}, {slug} and {number}.
"""
import argparse
import re
import sys

TYPE_MAP = {"feature": "feature", "bug": "fix", "chore": "chore", "docs": "docs", "research": "research"}
STOP = {"a", "an", "the", "and", "or", "of", "on", "to", "for", "in", "with", "every", "each", "is", "be", "it", "its", "that", "this", "when", "so"}


def branch_type(labels):
    for label in labels:
        label = label.strip()
        if label.startswith("type:"):
            return TYPE_MAP.get(label[5:], "chore")
    return "chore"


def slug(title, number=None):
    t = re.sub(r"^\s*[a-zA-Z]+(\([^)]*\))?!?:\s*", "", title)   # "feat(board):" / "research:"
    t = re.sub(r"\([^)]*\)", " ", t)                              # parenthesised asides
    words = [w for w in re.split(r"[^a-z0-9]+", t.lower()) if w and w not in STOP]
    s = "-".join(words[:5])[:40].strip("-")
    if not s:
        return "issue-%s" % number if number else "change"
    return s


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--title", required=True)
    ap.add_argument("--labels", default="")
    ap.add_argument("--pattern", default="{type}/{slug}")
    ap.add_argument("--number", default="")
    a = ap.parse_args()
    labels = [l for l in a.labels.split(",") if l.strip()]
    print(a.pattern.format(type=branch_type(labels), slug=slug(a.title, a.number or None), number=a.number))


if __name__ == "__main__":
    sys.exit(main())
