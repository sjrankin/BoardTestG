# BoardTestG

The 2D board of BoardTestRK (`../BoardTestRK`), reimplemented in Godot 4 (GDScript). If this works well, more of
BoardTestRK moves here. For now: the 2D board only, cubes only, Subtract mode (tap a group of 3 or more).

## Rules

The game rules are the same as BoardTestRK's. Read `../BoardTestRK/BoardTestRKRules.md` first. This project covers
its 2D-board parts: groups, removal, gravity, refill, Blockers, no-moves recovery, and the Fly Away effect
(here real rigid-body physics: pieces fall to the floor, bounce off the board and each other, then fade). Not yet
ported: Add mode (drag swaps), the idle hint, the rounded cube / diamond / ellipsoid / extruded-letter / joined shapes, sounds, the cube/sphere/solid boards. Block shapes done: Cube, Sphere, Cone, Cylinder, Glow, Rounded Cube, Joined Cubes / Joined Spheres (from BoardTestRK's Joined Squares / Circles) Joined Cylinders (new) and Joined Glow (new: streaks of light between same-colour neighbours) (`BuildShapes` in BoardView.gd; a shape is a mesh, a black-edge twin and a collider).

## Layout

Scripts are grouped by job, each file small and about one thing:

- `Scripts/Model/BoardModel.gd` - the rules, no nodes. Cells are (Col, Row), Row 0 at the top. Falling is worked out in
  a "virtual" frame where gravity always points to higher rows (`ToReal` maps back); `Queue` holds new pieces off the
  board. `Drop()` returns each moved piece with its path of real cells.
- `Scripts/Style/` - how things look and what they collide as. `BlockStyles.gd` (the shapes: mesh, black-edge twin,
  collider; the color and Glow materials; `MakeVisual`/`ApplyShape`), `BlockerLight.gd` (the pulsing indigo Blocker), `LightningEffect.gd` (jagged re-jittering bolts joining a cleared group, plus a flash; plays for `LightningLead` before the pieces fly out, toggle "Lightning"),
  `PhysicsLayers.gd` (collision layers).
- `Scripts/View/IdleHint.gd` - the idle hint (from BoardTestRK): after 20 s with no input, not in Attract Mode and not while busy, the largest playable group (ties: lowest on the board) gets a 5x5 black-and-white unlit checkerboard; a hint stays until a piece on the board is tapped (`BoardView.HandleTapRay` calls `Hint.Dismiss`); other input only restarts the idle clock (`Main._input` calls `Hint.RecordActivity`). Not shown for the Glow shape. `Scripts/View/JoinSystem.gd` - the joined shapes: same-colour neighbours that touch and are both at rest are joined (cubes grow to meet each other; spheres/cylinders get bridges), moving or removed pieces lose their joins, they come back on landing; `BoardView` calls `Joins.Update(MovingIds)` on tap, drop, landing and shuffle. `Scripts/View/BoardView.gd` - draws the model, taps and turns, animates drops (same speed for every piece; the longest
  drop takes 0.35 s), refills and shuffles. `Scripts/View/FlyerSystem.gd` - removed pieces as `RigidBody3D`s (launch,
  gravity, fade, the stand-ins that block a piece's own gap).
- `Scripts/App/` - `Main.gd` (wires it together; mouse input), `ControlBar.gd` (score/FPS, the gear button at the top right and the grouped, touch-sized Settings window it opens; reports by signals), `GearButton.gd` (the drawn gear), `CameraButton.gd` (Mac only, under the gear: `Main.TakeScreenshot` hides the controls and saves a PNG to ~/Pictures),
  `SceneSetup.gd` (sky, light, camera, floor), `GameSettings.gd` (what is remembered), `CaptureRunner.gd` (the
  `--capture` mode and the other startup options below; `--settings` opens the Settings window in a capture).
- `Tests/TestBoardModel.gd` - headless rule checks.

## Turning the board

`BoardView` is the board's pivot (its middle): `Yaw` about the world's vertical, then `Tilt` about the board's own
horizontal axis, so no part of it can dip below the floor. Gravity stays world-down. Cells are in the board's own
space (`CellPosition`), taps are ray-cast into that space, and removed pieces live in `FlyerSystem` (world space, a sibling
of the board) so they do not turn with it. A removed piece always falls straight down in the world - the way gravity pulls,
the shortest way to the floor, through whatever is beneath it - whatever way the board is turned. Gravity on the board is down *as the user sees it*, however the board is turned (unlike BoardTestRK, whose 2D board always falls along its own down): before each drop `GravityFromUser` takes the camera's screen-down into the board's space and rounds it to one of four grid directions (`BoardModel.GravityDir`); new pieces queue off the opposite edge.
Drag to turn (a press that moves more than a few pixels is a turn, not a tap), Recenter, or Auto Rotate.

**Removal rule (2D board only):** removed pieces pop out of the board's own front face (+Z) whichever way the board is turned, then fall under gravity. This is specific to the 2D board; a future 3D board in this project should launch each piece out of the face it was on, as BoardTestRK's 3D shapes do.

## iOS

`iOS/` holds the Godot iOS export as an Xcode project (product name XBoardTest, team 4BB235M4GL); see `iOS/README.md`. Run it
on a real iPhone, not the Simulator (the 4.7.2 template's simulator library has no arm64 code, which shows up as a missing
`_main`). The folder has a `.gdignore`; its big generated parts are git-ignored. On iOS the scene is drawn at the screen's own
size with 4x MSAA (`UpdateSuperSampling` in Main.gd), and the project is landscape. A phone/tablet starts with a 60 per second frame-rate limit (Settings > Performance; `Engine.max_fps`; 0 = no limit elsewhere), since an iPad Pro would otherwise run at 120 and run warm.

**Attract Mode picks** the largest playable group; ties go to the group closest on average to the bottom (as the user sees it), remaining ties at random (`BoardView.AttractStep`).

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
