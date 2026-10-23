extends SceneTree
## Headless checks of the play modes. Run:
##   /Applications/Godot.app/Contents/MacOS/Godot --headless --path . --script res://Tests/TestGameSession.gd

var Failures: int = 0


func Check(Condition: bool, Message: String) -> void:
	if not Condition:
		Failures += 1
		print("FAIL: ", Message)


func NewSession(Mode: GameMode.Kinds) -> GameSession:
	var Session := GameSession.new()
	Session.Start(Mode, LevelDefinition.Default(false, Vector3i(11, 11, 0)))
	return Session


func _init() -> void:
	var Level := LevelDefinition.Default(true, Vector3i(5, 6, 7))
	Check(Level.ColorGoals == [Vector2i(0, 45)] and Level.TurnCount == 17 and Level.TimeCount == 45.0, "default level")
	Check(Level.ShapeType == LevelDefinition.ShapeTypes.ThreeD and Level.Dimensions == Vector3i(5, 6, 7), "3D level size")
	Level.Difficulty = 99
	Check(Level.Difficulty == 10, "difficulty is clamped")
	Check(GameMode.Default == GameMode.Kinds.Zen, "Zen is the default")

	# Zen: no limit, play goes on after the goal.
	var Zen := NewSession(GameMode.Kinds.Zen)
	for Index in 40:
		Zen.RecordRemoval(0 if Index % 2 == 0 else 1, 3)
	Check(Zen.Turns == 40 and Zen.Remaining[0] == 0, "Zen counts turns and red pieces")
	Check(Zen.GoalMet and Zen.CanPlay(), "Zen continues after the goal")

	# Turn: 15 red taps within 17 turns wins; four other taps spoil it.
	var Won := NewSession(GameMode.Kinds.Turn)
	for Index in 15:
		Won.RecordRemoval(0, 3)
	Check(Won.State == GameSession.States.Won and not Won.CanPlay(), "Turn: 15 red within 17 turns wins")
	var Lost := NewSession(GameMode.Kinds.Turn)
	for Index in 17:
		Lost.RecordRemoval(0 if Index % 5 != 0 else 2, 3)
	Check(Lost.State == GameSession.States.Lost and Lost.TurnsLeft() == 0, "Turn: out of turns loses")
	Lost.RecordRemoval(0, 3)
	Check(Lost.Turns == 17, "no turns after the game is over")

	# Timed: the clock starts at the first removal, waits while paused, and ends the game at 45 s.
	var Timed := NewSession(GameMode.Kinds.Timed)
	root.add_child(Timed)
	Timed._process(10.0)
	Check(Timed.Elapsed == 0.0, "clock waits for the first removal")
	Timed.RecordRemoval(0, 3)
	Timed.Paused = true
	Timed._process(10.0)
	Check(Timed.Elapsed == 0.0, "clock waits while paused")
	Timed.Paused = false
	Timed._process(44.0)
	Check(Timed.State == GameSession.States.Playing and ceili(Timed.TimeLeft()) == 1, "Timed: 1 s left")
	Timed._process(2.0)
	Check(Timed.State == GameSession.States.Lost and Timed.TimeLeft() == 0.0, "Timed: out of time loses")
	var Fast := NewSession(GameMode.Kinds.Timed)
	for Index in 15:
		Fast.RecordRemoval(0, 3)
	Check(Fast.State == GameSession.States.Won, "Timed: goal in time wins")

	# Color removal with several goal colors: a badge's count falls by the size of each group, never below 0.
	var Multi := GameSession.new()
	var Two := LevelDefinition.new()
	Two.ColorGoals.assign([Vector2i(1, 7), Vector2i(3, 4)])
	Multi.Start(GameMode.Kinds.Turn, Two)
	Multi.RecordRemoval(0, 5)
	Check(Multi.Remaining == {1: 7, 3: 4} and Multi.WantedKinds() == [1, 3], "other colors do not count")
	Multi.RecordRemoval(1, 5)
	Multi.RecordRemoval(3, 6)
	Check(Multi.Remaining == {1: 2, 3: 0} and Multi.WantedKinds() == [1] and not Multi.GoalMet, "a done color drops out")
	Multi.RecordRemoval(1, 3)
	Check(Multi.Remaining[1] == 0 and Multi.State == GameSession.States.Won, "all colors done wins")

	# The hint prefers the largest group of a wanted color.
	var Board := BoardModel.new(5, 5, 4, 0, 1)
	for Col in 5:
		for Row in 5:
			Board.SetPiece(Col, Row, Board.NewPiece((Col + Row * 2) % 4))
	for Row in 3:
		Board.SetPiece(0, Row, Board.NewPiece(2))
	for Col in 5:
		Board.SetPiece(Col, 4, Board.NewPiece(3))
	var Biggest := Board.LargestGroup()
	var OfBlue := Board.LargestGroup([2] as Array[int])
	Check(Board.GetPiece(Biggest[0].x, Biggest[0].y).Kind == 3, "unfiltered hint is the largest group")
	Check(Board.GetPiece(OfBlue[0].x, OfBlue[0].y).Kind == 2, "hint is for the wanted color")
	Check(not Board.LargestGroup([7] as Array[int]).is_empty(), "hint falls back when no wanted group exists")

	# The level list.
	var All := Levels.All()
	Check(All.size() == 10, "ten levels")
	for Index in All.size():
		var L := All[Index]
		var Cells := L.Dimensions.x * L.Dimensions.y
		var Tag := "level %d: " % (Index + 1)
		var Total := 0
		var Seen := {}
		for Goal in L.ColorGoals:
			Total += Goal.y
			Check(Goal.x >= 0 and Goal.x < L.ColorCount and not Seen.has(Goal.x) and Goal.y > 0, Tag + "goal color is one of the board's, once")
			Seen[Goal.x] = true
		Check(L.Difficulty == Index + 1 and L.ShapeType == LevelDefinition.ShapeTypes.TwoD, Tag + "difficulty and shape")
		Check(L.Dimensions.x >= 3 and L.Dimensions.x <= 15 and L.Dimensions.y >= 3 and L.Dimensions.y <= 13, Tag + "size in range")
		Check(L.ColorCount >= 4 and L.ColorCount <= 6 and L.ColorGoals.size() >= 1 and L.ColorGoals.size() <= L.ColorCount, Tag + "colors")
		Check(L.PresetBlockers.size() <= Cells / 40, Tag + "at most one Blocker per 40 cells")
		Check(L.TurnCount * 3 >= Total, Tag + "enough turns for the pieces")
		var Model := BoardModel.new(L.Dimensions.x, L.Dimensions.y, L.ColorCount, L.PresetBlockers.size(), 0, L.PresetBlockers)
		var Found := 0
		for Col in Model.Width:
			for Row in Model.Height:
				if Model.IsBlocker(Col, Row):
					Found += 1
		Check(Found == L.PresetBlockers.size(), Tag + "preset Blockers land on the board")
		Check(Model.OpenCellsConnected(), Tag + "open cells connected")
		print("L", L.Difficulty, " ", L.Dimensions.x, "x", L.Dimensions.y, " colors ", L.ColorCount, " goals ", L.ColorGoals, " turns ", L.TurnCount, " time ", L.TimeCount, " blockers ", L.PresetBlockers.size())
	Check(Levels.TurnsFor(45, 30) > Levels.TurnsFor(45, 150), "fewer pieces give more turns")
	Check(Levels.TurnsFor(90, 50) > Levels.TurnsFor(45, 50), "more pieces to remove give more turns")
	Check(Levels.All()[0].PresetBlockers == Levels.Build(1, Vector2i(7, 7), 4, [Vector2i(0, 12), Vector2i(1, 9)]).PresetBlockers, "levels are repeatable")

	if Failures == 0:
		print("ALL PASS")
	else:
		print("FAILURES: ", Failures)
	quit(Failures)
