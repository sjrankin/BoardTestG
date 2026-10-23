class_name LevelDefinition
extends RefCounted
## Everything that defines a level. Which of `TurnCount` and `TimeCount` applies depends on the play mode (`GameMode`);
## Zen ignores both. Until real levels exist, `Default` is the one level every board uses.

enum ShapeTypes { TwoD, ThreeD }

const MinDifficulty := 1
const MaxDifficulty := 10
const DefaultRedPieces := 45
const DefaultTurnCount := 17
const DefaultTimeCount := 45.0
## The color (`Kind`) the default level's goal counts: red.
const RedKind := 0

## 1 (easiest) to 10 (hardest).
var Difficulty: int = MinDifficulty:
	set(Value):
		Difficulty = clampi(Value, MinDifficulty, MaxDifficulty)
var ShapeType: ShapeTypes = ShapeTypes.TwoD
## Width, Height, Depth. Depth is 0 for a 2D board.
var Dimensions := Vector3i(11, 11, 0)
## Pieces placed before play, each {Cell: Vector3i, Kind: int} (a 2D board uses Cell.x = Col, Cell.y = Row, Cell.z = 0).
## Cells not listed are filled at random.
var PresetPieces: Array[Dictionary] = []
## Cells that hold a Blocker (2D boards only), same cell convention.
var PresetBlockers: Array[Vector3i] = []
## Special pieces placed before play, each {Cell: Vector3i, Special: String}. The kinds are still to be decided.
var PresetSpecials: Array[Dictionary] = []
## Turns allowed in Turn mode (a turn is a tap that removes a group).
var TurnCount: int = DefaultTurnCount
## Seconds allowed in Timed mode.
var TimeCount: float = DefaultTimeCount
## How many colors the board is dealt (4 to 6 in the levels); 0 means whatever Settings > Board says.
var ColorCount: int = 0
## The goal (color removal): for each entry, remove that many pieces of that color - Vector2i(Kind, Count). Colors not listed
## are not part of the goal, so a level need not use every color on the board. The level is won when every entry is done.
var ColorGoals: Array[Vector2i] = []


## The level used on every board for now: remove 45 red pieces (15 groups of the smallest size), in 17 turns or 45 seconds.
static func Default(Is3D: bool, Size: Vector3i) -> LevelDefinition:
	var Level := LevelDefinition.new()
	Level.ShapeType = ShapeTypes.ThreeD if Is3D else ShapeTypes.TwoD
	Level.Dimensions = Size if Is3D else Vector3i(Size.x, Size.y, 0)
	Level.ColorGoals.append(Vector2i(RedKind, DefaultRedPieces))
	return Level
