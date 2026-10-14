- Follow the [official GDScript style guide](https://docs.godotengine.org/en/stable/tutorials/scripting/gdscript/gdscript_styleguide.html):
  `snake_case` for variables, functions and files; `PascalCase` for class
  and node names.
- **Keep scenes composable.** An `Enemy` scene shouldn't reach into `World`
  internals. Prefer, in this order:
  1. **A signal**, for an event a system doesn't need to react to
     synchronously (`World.tiles_cleared`).
  2. **An `Array[Callable]` extension point** (e.g. `World.spawn_blockers`)
     when several independent systems each need to contribute a check or
     behavior without one clobbering another.
  3. **A direct object reference**, only when the wiring itself lives in a
     composition root (e.g. `game_manager.gd`), never inside either scene
     being connected.
  Reach for an autoload only where a shared system is genuinely warranted
  (see the autoload rule below).
- **One script's responsibility should be guessable from its path**
  (`scripts/enemies/enemy.gd` owns enemy behavior, not world logic).
- **Set a node's configuration properties before `add_child()`**, not after
  (`grid_position`, `color_id`, `cell_size`, ...). A property can behave
  differently, or a setter can fire side effects, once the node is already in
  the scene tree
  ([Godot's logic-preferences guidance](https://docs.godotengine.org/en/stable/tutorials/best_practices/logic_preferences.html)).
  This exact bug is easy to hit more than once (a sizing computation that ran
  before a texture was assigned; a health value initialized after the node
  entered the tree) - treat it as a standing rule, not a case-by-case call.
- **An autoload may only grow fields within its own existing, named scope**
  (for example `GameState`: turn and target; `PlayerState`: player-facing
  stats). A new category of shared state gets its own autoload (only if
  genuinely wide-scoped) or is passed by reference some other way - never
  bolted onto an existing autoload just because it's already global and
  convenient to reach.
- **Static data stays as `const` Dictionary/Array literals in the owning
  script, not a `Resource`**, when it's ported from a reference or needs
  comments explaining *why* a number is what it is - the comments stay
  attached to the data instead of being split across a `.tres` and its
  loader. Reach for a `Resource` only when the data needs Inspector editing or
  save/load, not just because it's structured.
- **Don't commit `.godot/`** or other editor-generated cache; it belongs in
  `.gitignore`. If it creeps back in, that's a bug in the ignore rules, not
  something to work around per commit.
- **Exclude `addons/gut/` from broad repo searches** (Grep/Glob across
  everything): it's roughly a hundred vendored third-party files, almost never
  relevant, and sweeping them in is an avoidable token cost.
