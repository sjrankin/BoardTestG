class_name Levels
extends RefCounted
## The list of levels (all 2D, all color removal: remove so many pieces of some of the board's colors). Level N has difficulty N. Blocker cells are chosen once, with a
## fixed seed per level (by a `BoardModel`, so they obey its rules: the open cells stay connected), so a level is the same
## every time.

const WidthRange := Vector2i(3, 15)
const HeightRange := Vector2i(3, 13)
const GroupsRange := Vector2i(10, 20)
## At most one Blocker for every this many cells of the board.
const CellsPerBlocker := 40
## Extra turns on top of the taps the goal needs, as a fraction of them: the most for the smallest board, the least for the largest.
const FudgeMostPieces := 0.25
const FudgeFewestPieces := 0.5
## Seconds per piece to remove, in Timed mode.
const SecondsPerPiece := 1.0
## The goal pieces a turn is expected to clear. A group is at least 3, but a turn often cannot be spent on a group of a goal color
## (there may be none to play), so this is well under 3: 1.6 is about what the difficulty test's bot managed (1.1 to 2.7 on the
## ten levels) less a margin.
const PiecesPerTurn := 1.6
## Colors the Blocker cells are worked out for (placement does not depend on them).
const ColorsForPlacement := 5

## One row per level, easiest first: [Width x Height, colors dealt (4 to 6), goals]. Each goal is Vector2i(color, pieces to
## remove); a color not listed is not part of the goal. Colors are numbered as in `BlockStyles.Palette` (0 red, 1 green, 2 blue,
## 3 cyan, 4 yellow, 5 magenta).
const Table: Array = [
	[Vector2i(7, 7), 4, [Vector2i(2, 12), Vector2i(3, 9)]],
	[Vector2i(9, 5), 4, [Vector2i(3, 15), Vector2i(0, 12)]],
	[Vector2i(11, 9), 5, [Vector2i(4, 20), Vector2i(1, 20)]],
	[Vector2i(6, 8), 5, [Vector2i(2, 18), Vector2i(4, 15)]],
	[Vector2i(15, 13), 5, [Vector2i(3, 30), Vector2i(2, 30), Vector2i(4, 25)]],
	[Vector2i(8, 10), 6, [Vector2i(5, 24), Vector2i(1, 24), Vector2i(3, 18)]],
	[Vector2i(12, 7), 6, [Vector2i(0, 30), Vector2i(5, 30)]],
	[Vector2i(4, 6), 4, [Vector2i(1, 20), Vector2i(3, 20), Vector2i(2, 15)]],
	[Vector2i(13, 11), 6, [Vector2i(4, 36), Vector2i(5, 36), Vector2i(2, 30), Vector2i(0, 30)]],
	[Vector2i(15, 3), 6, [Vector2i(1, 40), Vector2i(4, 40), Vector2i(5, 40)]],
]

## Where the difficulty test's results are kept between launches (one section per level).
const StatsPath := "user://LevelDifficulty.cfg"
## Difficulty is worked out from how many turns the test bot needed (its mean) against the turns the level allows: a ratio of
## `EasyRatio` or less is difficulty 1, `HardRatio` or more (the bot needs every turn the level allows, or more) is difficulty 10,
## and the ratios between spread evenly over 2 to 9.
const EasyRatio := 0.3
const HardRatio := 1.0

static var Cache: Array[LevelDefinition] = []


static func All() -> Array[LevelDefinition]:
	if Cache.is_empty():
		for Index in Table.size():
			Cache.append(Build(Index + 1, Table[Index][0], Table[Index][1], Table[Index][2]))
		LoadStats()
	return Cache


## The difficulty (1 easiest to 10 hardest) of a level that allows `AllowedTurns` and took the test bot `MeanTurns` on average.
static func DifficultyFor(MeanTurns: float, AllowedTurns: int) -> int:
	var Ratio := MeanTurns / maxf(float(AllowedTurns), 1.0)
	return clampi(roundi(1.0 + 9.0 * (Ratio - EasyRatio) / (HardRatio - EasyRatio)), 1, 10)


## Records a level's test result: the mean turns and win rate go in the table (`MeanTurns`, `WinRate`), the difficulty is
## updated from them, and all of it is saved for the next launch.
static func Record(Index: int, MeanTurns: float, WinRate: float) -> void:
	var Level := All()[Index]
	Level.MeanTurns = MeanTurns
	Level.WinRate = WinRate
	Level.Difficulty = DifficultyFor(MeanTurns, Level.TurnCount)
	var File := ConfigFile.new()
	File.load(StatsPath)
	var Name := "Level %d" % (Index + 1)
	File.set_value(Name, "MeanTurns", MeanTurns)
	File.set_value(Name, "WinRate", WinRate)
	File.set_value(Name, "Difficulty", Level.Difficulty)
	File.save(StatsPath)


## Puts the saved test results back into the levels. A result for a level whose turn count has since changed is ignored.
static func LoadStats() -> void:
	var File := ConfigFile.new()
	if File.load(StatsPath) != OK:
		return
	for Index in Cache.size():
		var Name := "Level %d" % (Index + 1)
		if File.has_section_key(Name, "MeanTurns"):
			Cache[Index].MeanTurns = float(File.get_value(Name, "MeanTurns"))
			Cache[Index].WinRate = float(File.get_value(Name, "WinRate", -1.0))
			Cache[Index].Difficulty = DifficultyFor(Cache[Index].MeanTurns, Cache[Index].TurnCount)


static func Count() -> int:
	return Table.size()


## Turns for a goal of `Pieces` pieces on a board with this many pieces (cells that are not Blockers): the taps it takes at an
## average of `PiecesPerTurn`, plus a fudge that grows as the board shrinks.
static func TurnsFor(Pieces: int, BoardPieces: int) -> int:
	var MinPieces := WidthRange.x * HeightRange.x
	var MaxPieces := WidthRange.y * HeightRange.y
	var Fraction := clampf(float(BoardPieces - MinPieces) / float(MaxPieces - MinPieces), 0.0, 1.0)
	var Base := ceili(Pieces / PiecesPerTurn)
	return Base + ceili(Base * lerpf(FudgeFewestPieces, FudgeMostPieces, Fraction))


static func Build(Number: int, Size: Vector2i, Colors: int, Goals: Array) -> LevelDefinition:
	var Width := Size.x
	var Height := Size.y
	var Level := LevelDefinition.new()
	Level.Difficulty = Number
	Level.ShapeType = LevelDefinition.ShapeTypes.TwoD
	Level.Dimensions = Vector3i(Width, Height, 0)
	var Cells := Width * Height
	var MostBlockers := Cells / CellsPerBlocker
	if MostBlockers > 0:
		var Rng := RandomNumberGenerator.new()
		Rng.seed = Number * 7919
		var Wanted := Rng.randi_range(maxi(1, MostBlockers / 2), MostBlockers)
		var Placer := BoardModel.new(Width, Height, ColorsForPlacement, Wanted, Number * 7919 + 1)
		for Col in Width:
			for Row in Height:
				if Placer.IsBlocker(Col, Row):
					Level.PresetBlockers.append(Vector3i(Col, Row, 0))
	Level.ColorCount = Colors
	var Total := 0
	for Goal in Goals:
		Level.ColorGoals.append(Goal)
		Total += Goal.y
	Level.TurnCount = TurnsFor(Total, Cells - Level.PresetBlockers.size())
	Level.TimeCount = Total * SecondsPerPiece
	return Level
