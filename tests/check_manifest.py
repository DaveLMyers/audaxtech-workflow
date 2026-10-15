#!/usr/bin/env python
"""CI check: the plugin manifest has a semver version and the marketplace lists the same plugin.

Installed copies update only when plugin.json's version changes, so a missing or malformed
version would either ship every commit or ship nothing. Run: python tests/check_manifest.py
"""
import json
import pathlib
import re
import sys

root = pathlib.Path(__file__).resolve().parent.parent
plugin = json.loads((root / ".claude-plugin" / "plugin.json").read_text(encoding="utf-8"))
market = json.loads((root / ".claude-plugin" / "marketplace.json").read_text(encoding="utf-8"))
errors = []
version = plugin.get("version")
if not isinstance(version, str) or not re.fullmatch(r"\d+\.\d+\.\d+", version):
    errors.append("plugin.json: version must be semver like 0.1.0, got %r" % (version,))
if plugin.get("name") not in [p.get("name") for p in market.get("plugins", [])]:
    errors.append("marketplace.json does not list the plugin %r" % plugin.get("name"))
if errors:
    print("\n".join(errors))
    sys.exit(1)
print("manifest ok: %s %s" % (plugin["name"], version))
