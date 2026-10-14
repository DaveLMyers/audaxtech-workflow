
## Game-specific process

### Game docs
- **`docs/DESIGN.md`** is intent (how the game is meant to work).
  **`docs/GAMEPLAY.md`** is builder-facing: how each system behaves as
  implemented, with code references. **`docs/HOW_TO_PLAY.md`** is
  player-facing, plain language.
- A PR that changes what a system actually does (not just how it is
  implemented) updates GAMEPLAY.md, and HOW_TO_PLAY.md too if the change is
  player-visible. A real design or scope judgment call also gets a
  `docs/DECISIONS.md` entry, in the same PR. Most PRs need none of these.
- If this game rebuilds or draws on an earlier one, say in DESIGN.md which
  parts are spec and which are only seeds, and record deliberate deviations
  in DECISIONS.md.

### Play-testing
"It compiles" is not evidence a game works. For anything player-facing,
launch the real game and exercise the change, and include a screenshot or
short clip in the PR for anything visual. Where a human can try it hands-on,
offer that before merging.

### Engine conventions
{{ENGINE_CONVENTIONS}}
