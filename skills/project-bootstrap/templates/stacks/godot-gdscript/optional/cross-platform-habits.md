
### Cross-platform habits

Use this module if the game ships on more than one platform. None of them is
"the" platform, and Windows-only (or macOS-only) assumptions are the ones that
slip in unnoticed on a single-OS dev machine. CI on Linux catches some. A
change that breaks one of these needs a reason in the PR and a DECISIONS.md
entry.

- **Paths:** use `res://` and `user://` and `path_join()`. No drive letters, no
  hand-built backslash paths, and never assume the install folder is writable
  or survives an update (a macOS app bundle, or a store install that gets
  replaced, may not be). Anything the game saves goes under `user://`.
- **OS calls:** keep `OS.execute()`, shell commands and `OS.get_name()` checks
  out of game code. If something truly differs by platform, put it behind one
  small function with a comment saying why, not scattered checks. Dev tooling
  in `tools/` may be per-platform (`.ps1`, `.sh`, `.cmd`); say in the script
  when a platform isn't covered.
- **File name case:** keep a resource's name identical in case everywhere it is
  referenced, and never have two files that differ only by case. Exported
  builds treat `Foo.png` and `foo.png` as different files; Windows and default
  macOS do not.
- **Renderer:** pick one deliberately and record it in DECISIONS.md along with
  the hardware floor it implies. Don't add a shader or effect that needs more
  than that renderer offers without a new entry saying what it costs in
  hardware you can run on.
- **Native extensions and platform-only dependencies:** prefer GDScript-only.
  An add-on that ships a native library per platform needs a DECISIONS.md
  entry first: it has to exist for every platform you ship.
- **Floating point:** results can differ slightly between machines and CPU
  types (x86 vs. Apple Silicon). Don't write code or tests that need
  bit-identical numbers across machines; compare with a tolerance, and treat a
  recorded replay or log as faithful only on the build that wrote it.
- **Input:** decide what input schemes you support and record it. If a scheme
  is intentionally unsupported (say, mouse-only), don't make a function
  reachable only through another (a keyboard shortcut should be a convenience
  next to something clickable; Ctrl and Cmd differ).
- **PR check:** (review) read the diff against this list. Look at what it touches:
  any `OS.` call, a path built by hand, a new add-on or shader, a test comparing
  floats exactly. A break needs a stated reason in the PR and a DECISIONS.md
  entry, and the PR description says the check was done.
