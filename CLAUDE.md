# BoardTestG

The 2D board of BoardTestRK (`../BoardTestRK`), reimplemented in Godot 4 (GDScript). If this works well, more of
BoardTestRK moves here. For now: the 2D board only, cubes only, Subtract mode (tap a group of 3 or more).

## Rules

The game rules are the same as BoardTestRK's. Read `../BoardTestRK/BoardTestRKRules.md` first. This project covers
its 2D-board parts: groups, removal, gravity, refill, Blockers, no-moves recovery, and the Fly Away effect
(here real rigid-body physics: pieces fall to the floor, bounce off the board and each other, then fade). Not yet
ported: Add mode (drag swaps), the idle hint, the rounded cube / diamond / ellipsoid / extruded-letter / joined shapes, sounds, the cube/sphere/solid boards. Block shapes done: Cube, Sphere, Cone, Cylinder (`BuildShapes` in BoardView.gd; a shape is a mesh, a black-edge twin and a collider).

## Layout

- `Scripts/BoardModel.gd` - the rules, no nodes. Cells are (Col, Row), Row 0 at the top; `Pad` rows above the board
  hold queued new pieces. `Drop()` returns each moved piece with its path of cells.
- `Scripts/BoardView.gd` - draws the model, animates drops (same speed for every piece; the longest drop takes 0.35 s),
  launches removed pieces as `RigidBody3D`s, waits for them to leave before the refill drops.
- `Scripts/Main.gd` - builds the camera, light, floor and controls; also the `--capture` mode below.
- `Tests/TestBoardModel.gd` - headless rule checks.

## Naming and style

Same owner conventions as the other projects: PascalCase for everything that is not a Godot API name (functions,
variables, constants, classes, signals, files). Godot's own callbacks keep their names (`_ready`, `_process`,
`_unhandled_input`, `_physics_process`). Keep files reasonably short and split by responsibility.

## Running

Godot is `/Applications/Godot.app/Contents/MacOS/Godot` (4.7; the project targets 4.6).

```
G=/Applications/Godot.app/Contents/MacOS/Godot
$G --headless --path . --import                                   # once, after adding scripts (rebuilds the class cache)
$G --headless --path . --script res://Tests/TestBoardModel.gd      # rule tests; prints ALL PASS
$G --path . -- --capture=/some/dir                                 # plays itself in Attract Mode, saves screenshots, quits
```

A script error in a headless test run can still end in `ALL PASS`; read the whole output, not just the last line.
`node_3d.tscn` is the empty scene the Godot editor created with the project; it is not used.
