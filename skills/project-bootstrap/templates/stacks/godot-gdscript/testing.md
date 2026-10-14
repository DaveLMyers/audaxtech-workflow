[GUT](https://github.com/bitwes/Gut) (vendored under `addons/gut/`) is the
unit testing tool. Tests live under `test/unit/`, mirroring the path of what
they cover (`test/unit/test_world.gd` tests `scripts/world/world.gd`).

- Add or update tests for logic with real branching and edge cases (a match
  or selection algorithm, damage math, spawn rules, physics integration,
  scoring, level validation) in the same PR. UI wiring, scene composition and
  one-off glue code don't need tests just to have tests.
- **Prefer testing pure logic** (a method that computes a result from
  arguments and state, no scene-tree side effects) over anything that needs a
  running scene: faster to write and run, and unaffected by unrelated scene
  changes. Make the real code path and any preview of it call the *same*
  method, so a test is a test of real behavior and not a parallel
  reimplementation that can drift.
- **For physics and simulation, test the properties you care about, not the
  implementation.** For example: a launch goes along the aim direction at the
  given speed; a flat-ground shot lands near where the closed-form arc says
  (use a tolerance that scales with the step size); a body comes to rest below
  the rest threshold; results don't change with frame rate. Derive expected
  values from the tunables, never by copying numbers out of the code under
  test.
- Run the suite (see the `run` skill for how the pinned Godot is set up):
  ```
  .godot-bin/godot.cmd --headless -s addons/gut/gut_cmdln.gd -gconfig=res://.gutconfig.json   # Windows
  .godot-bin/godot --headless -s addons/gut/gut_cmdln.gd -gconfig=res://.gutconfig.json       # macOS/Linux
  ```
  Run it before opening a PR that touches tested code, the same way you'd boot
  the game to check it still runs.
