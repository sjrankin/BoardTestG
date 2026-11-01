extends SceneTree
## Headless checks of the level files and the piece countdown. Run:
##   /Applications/Godot.app/Contents/MacOS/Godot --headless --path . --script res://Tests/TestLevelFiles.gd

var Failures: int = 0


func Check(Condition: bool, Message: String) -> void:
	if not Condition:
		Failures += 1
		print("FAIL: ", Message)


## A level entry that is valid until a test breaks a part of it.
func Good() -> Dictionary:
	return {
		"Colors": 4,
		"Goals": [{"Group": 1, "Remove": 9}],
		"Legend": {"c": {"Group": 2, "Count": 3}, "r": {"Count": 2}},
		"Map": ["#c#r#", "#####", "..B##"],
	}


func Parse(Data: Dictionary) -> LevelDefinition:
	Levels.Problems = []
	return Levels.Parse(Data, "Test.json", 1, 1, "test")


func TestParse() -> void:
	var L := Parse(Good())
	Check(L != null and Levels.Problems.is_empty(), "a good level parses: %s" % str(Levels.Problems))
	Check(L.Dimensions == Vector3i(5, 3, 0) and L.PresetGaps.size() == 2 and L.PresetBlockers == [Vector3i(2, 2, 0)], "the map gives size, gaps and Blockers")
	Check(L.PresetPieces.size() == 2, "two pieces have their own Legend entries")
	Check(L.PresetPieces[0]["Kind"] == 2 and L.PresetPieces[0]["Count"] == 3 and L.PresetPieces[0]["Cell"] == Vector3i(1, 0, 0), "a fixed group with a countdown")
	Check(L.PresetPieces[1]["Count"] == 2 and L.PresetPieces[1]["Kind"] < 4, "a random group with a countdown")
	Check(L.TurnCount == Levels.TurnsFor(9, 12) and L.TimeCount == 9.0, "turns and time are worked out when the file leaves them out")
	Check(L.Shape == -1 and L.RemovalEffect == -1, "no shape or effect unless the level names one")
	var Named := Good()
	Named["Turns"] = 7
	Named["Time"] = 33
	Named["Shape"] = "joined glow"
	Named["RemovalEffect"] = "Explode"
	Named["Difficulty"] = 8
	L = Parse(Named)
	Check(L.TurnCount == 7 and L.TimeCount == 33.0 and L.Difficulty == 8, "turns, time and difficulty come from the file")
	Check(L.Shape == BlockStyles.Shapes.JoinedGlow and L.RemovalEffect == BoardView.RemovalEffects.Explode, "shape and effect are found by name, any case")
	var Short := Good()
	Short["Map"] = ["#####", "####", "#####"]
	Check(Parse(Short).PresetGaps == [Vector3i(4, 1, 0)], "a short row is finished with a gap")


func TestRejects() -> void:
	var Cases := {
		"too few colors": {"Colors": 2},
		"no goals": {"Goals": []},
		"goal group out of range": {"Goals": [{"Group": 4, "Remove": 3}]},
		"goal of nothing": {"Goals": [{"Group": 1, "Remove": 0}]},
		"no map": {"Map": []},
		"map too small": {"Map": ["##", "##"]},
		"unknown symbol": {"Map": ["#####", "##z##", "#####"]},
		"no three open cells touch": {"Map": ["#.#.#", ".....", "#.#.#"]},
		"flow loop": {"Map": ["###", "###", "###"], "Flow": ["v<<", "^<<", "<<<"]},
		"flow with a bad symbol": {"Flow": ["vvvvx"]},
		"flow row too long": {"Flow": ["vvvvvv"]},
		"link off the map": {"Links": [{"From": [0, 0], "To": [9, 9]}]},
		"link onto a gap": {"Links": [{"From": [0, 0], "To": [0, 2]}]},
		"link to itself": {"Links": [{"From": [0, 0], "To": [0, 0]}]},
		"link that loops": {"Flow": ["vvvvv", "vvvvv", "vvvvv"], "Links": [{"From": [0, 0], "To": [4, 1]}, {"From": [4, 1], "To": [0, 0]}]},
		"too few open cells": {"Map": ["B.B", "...", "B.B"]},
		"unknown shape": {"Shape": "Dodecahedron"},
		"unknown effect": {"RemovalEffect": "Melt"},
		"countdown on a Blocker": {"Legend": {"x": {"Type": "Blocker", "Count": 2}}},
		"legend group out of range": {"Legend": {"x": {"Group": 9}}},
		"long legend key": {"Legend": {"xy": {"Group": 1}}},
		"zero turns": {"Turns": 0},
	}
	for Name in Cases:
		var Data := Good()
		for Key in Cases[Name]:
			Data[Key] = Cases[Name][Key]
		Check(Parse(Data) == null and not Levels.Problems.is_empty(), "rejected: " + Name)


## Areas apart from each other and gaps in the middle are fine.
func TestRegions() -> void:
	var Apart := Good()
	Apart["Map"] = ["###.###", "###.###", "###.###"]
	var L := Parse(Apart)
	Check(L != null and L.PresetGaps.size() == 3, "two separate areas of play are a valid map: %s" % str(Levels.Problems))
	var Model := BoardModel.new(7, 3, 4, 0, 5, [], L.PresetGaps)
	Check(Model.RegionCount() == 2 and Model.LargestRegion() == 9, "two areas of nine cells")
	var Blocked := BoardModel.new(7, 3, 4, 3, 5, [], L.PresetGaps)
	Check(Blocked.RegionCount() == 2, "random Blockers do not split an area of play")


func FlowLevel(Rows: Array, Flow: Array, Links: Array = []) -> BoardModel:
	var Data := {"Colors": 4, "Goals": [{"Group": 1, "Remove": 5}], "Map": Rows, "Flow": Flow, "Links": Links}
	var L := Parse(Data)
	Check(L != null, "flow level parses: %s" % str(Levels.Problems))
	return BoardModel.new(L.Dimensions.x, L.Dimensions.y, 4, 0, 3, L.PresetBlockers, L.PresetGaps, [], L.Flow)


func TestFlow() -> void:
	# All or nothing: one cell without a direction and the whole flow is ignored.
	var Partial := Good()
	Partial["Flow"] = ["^....", ".....", "....."]
	var Half := Parse(Partial)
	Check(Half != null and Half.Flow == null, "a flow that leaves an open cell without a direction is ignored altogether")
	var Whole := Good()
	Whole["Flow"] = ["^^^^^", "^^^^^", "^^^^^"]
	Check(Parse(Whole).Flow != null, "a flow that covers every open cell (gaps and Blockers need none) is kept")
	var OnlyLink := Good()
	OnlyLink["Links"] = [{"From": [0, 0], "To": [4, 0]}]
	Check(Parse(OnlyLink).Flow == null, "a link alone does not cover the board either")
	# A column that flows up: the pieces below a hole move up, and the new piece comes in at the bottom.
	var Up := FlowLevel(["#####", "#####", "#####", "#####", "#####"], ["^vvvv", "^vvvv", "^vvvv", "^vvvv", "^vvvv"])
	var Low := Up.GetPiece(0, 3)
	for Row in 3:
		Up.SetPiece(0, Row, null)
	var Moves := Up.Drop()
	Check(CountOpen(Up) == 25, "an upward column is refilled")
	Check(Up.GetPiece(0, 0) == Low, "the piece below the hole flowed up to the top")
	var Entered := false
	for Move in Moves:
		var Path: Array = Move["Path"]
		for Index in range(1, Path.size()):
			Check(Path[Index] - Path[Index - 1] == Vector2i(0, -1), "every step in an upward column goes up")
		if Path[0] == Vector2i(0, 5):
			Entered = true
	Check(Entered, "new pieces enter an upward column from below")
	# A link: the bottom of column 0 feeds the top of column 4, so column 4 is not fed from above.
	var Linked := FlowLevel(["#####", "#####", "#####", "#####"], ["vvvvv", "vvvvv", "vvvvv", "vvvvv"], [{"From": [0, 3], "To": [4, 0]}])
	Linked.SetPiece(4, 3, null)
	var Jumped := false
	var Before := Linked.GetPiece(0, 3)
	for Move in Linked.Drop():
		var Path: Array = Move["Path"]
		if Move["Piece"] == Before:
			Jumped = Path.has(Vector2i(4, 0))
	Check(Jumped and CountOpen(Linked) == 20, "a piece goes through a link into another column and the board fills")
	# The flow overrides gravity: an upward column goes on flowing up however gravity points.
	var Sideways := FlowLevel(["#####", "#####", "#####"], ["^vvvv", "^vvvv", "^vvvv"])
	Sideways.GravityDir = Vector2i(1, 0)
	var Held := Sideways.GetPiece(0, 2)
	for Row in 2:
		Sideways.SetPiece(0, Row, null)
	Sideways.Drop()
	Check(Sideways.GetPiece(0, 0) == Held, "a flow does not turn with gravity")
	# Turned boards: every flow still fills.
	for Direction in [Vector2i(0, 1), Vector2i(0, -1), Vector2i(1, 0), Vector2i(-1, 0)]:
		PlayOut(Up, Direction, "up-flow board, gravity %s" % Direction)
		PlayOut(Linked, Direction, "linked board, gravity %s" % Direction)


func CountOpen(Model: BoardModel) -> int:
	var Total := 0
	for Col in Model.Width:
		for Row in Model.Height:
			if Model.GetPiece(Col, Row) != null:
				Total += 1
	return Total


## Removes groups from `Model` and drops, checking after each drop that every open cell is full and nothing sits in a gap or on a Blocker.
func PlayOut(Model: BoardModel, Direction: Vector2i, Tag: String) -> void:
	Model.GravityDir = Direction
	var Open := 0
	for Col in Model.Width:
		for Row in Model.Height:
			if Model.IsOpen(Col, Row):
				Open += 1
	for Step in 25:
		var Groups := Model.PlayableGroups()
		if Groups.is_empty():
			Model.Shuffle()
			continue
		var Picked: Array[Vector2i] = []
		Picked.assign(Groups[Model.Rng.randi_range(0, Groups.size() - 1)])
		Model.Remove(Picked)
		Model.Drop()
		Check(CountOpen(Model) == Open, "the board is full after a drop (%s, step %d)" % [Tag, Step])
		for Col in Model.Width:
			for Row in Model.Height:
				if not Model.IsOpen(Col, Row):
					Check(Model.GetPiece(Col, Row) == null, "nothing sits in a gap or on a Blocker (%s)" % Tag)


func TestCountdown() -> void:
	var Model := BoardModel.new(5, 5, 4, 0, 1)
	Model.ClearCells()
	for Col in 5:
		for Row in 5:
			Model.SetPiece(Col, Row, Model.NewPiece((Col + Row) % 2 + 2))
	# A group of kind 0 in the top-left corner: (0,0), (1,0), (0,1). Its neighbors with countdowns: (2,0) and (1,1) and (0,2).
	for Cell in [Vector2i(0, 0), Vector2i(1, 0), Vector2i(0, 1)]:
		Model.SetPiece(Cell.x, Cell.y, Model.NewPiece(0))
	var Touching := Model.GetPiece(1, 1)
	Touching.Count = 2
	var Fuse := Model.GetPiece(2, 0)
	Fuse.Count = 1
	var Far := Model.GetPiece(4, 4)
	Far.Count = 1
	var Removed := Model.Remove(Model.GroupAt(0, 0))
	Check(Removed.size() == 3, "the tapped group goes")
	Check(Touching.Count == 1 and Model.LastTicked.size() == 1, "a neighbor with a countdown goes down by one, once, though it touches two removed pieces")
	Check(Fuse.Count == 0 and Model.GetPiece(2, 0) == null and Model.LastExpired.size() == 1, "a countdown reaching 0 takes the piece off the board")
	Check(Far.Count == 1 and Model.GetPiece(4, 4) == Far, "a piece not touching the group is untouched")
	var Plain := Model.GetPiece(0, 2)
	Check(Plain != null and Plain.Count == 0, "a piece with no countdown never counts down")
	# Presets survive a deal, and a Blocker (not a piece) cannot count.
	var Preset: Array[Dictionary] = [{"Cell": Vector3i(1, 1, 0), "Kind": 3, "Count": 4}]
	var Fixed := BoardModel.new(5, 5, 4, 0, 2, [], [], Preset)
	var Placed := Fixed.GetPiece(1, 1)
	Check(Placed.Kind == 3 and Placed.Count == 4, "a preset piece has its group and countdown after the deal")
	var WithBlocker := BoardModel.new(5, 5, 4, 0, 3, [Vector3i(2, 2, 0)])
	Check(WithBlocker.IsBlocker(2, 2) and WithBlocker.GetPiece(2, 2) == null, "a Blocker is never a piece")
	# A session: expiry counts toward the goal but is not a turn.
	var Session := GameSession.new()
	var Level := LevelDefinition.new()
	Level.ColorGoals.append(Vector2i(1, 4))
	Session.Start(GameMode.Kinds.Turn, Level)
	Session.RecordExpired(1, 1)
	Check(Session.Turns == 0 and Session.Remaining[1] == 3 and not Session.ClockStarted, "an expired piece is not a turn")
	Session.RecordExpired(1, 3)
	Check(Session.State == GameSession.States.Won, "countdown removals can finish the goal")
	Session.free()


func TestFiles() -> void:
	Levels.Reload()
	Check(Levels.Problems.is_empty(), "the shipped files load without problems: %s" % str(Levels.Problems))
	var Seen := {}
	for L in Levels.All():
		Check(not Seen.has(L.Id), "level Ids are unique (%s)" % L.Id)
		Seen[L.Id] = true
	var Fuse: LevelDefinition = Levels.All().filter(func(L: LevelDefinition) -> bool: return L.Id == "Countdown 1")[0]
	Check(Fuse.Shape == BlockStyles.Shapes.RoundedCube and Fuse.PresetPieces.size() == 4, "the sample countdown level is read")
	for L in Levels.All():
		for Direction in [Vector2i(0, 1), Vector2i(0, -1), Vector2i(1, 0), Vector2i(-1, 0)]:
			PlayOut(BoardModel.new(L.Dimensions.x, L.Dimensions.y, L.ColorCount, L.PresetBlockers.size(), 4, L.PresetBlockers, L.PresetGaps, L.PresetPieces, L.Flow), Direction, "%s, gravity %s" % [L.Id, Direction])
	var Flows := Levels.All().filter(func(L: LevelDefinition) -> bool: return L.Source == "Flows.json")
	Check(Flows.size() == 3 and Flows[0].Flow != null and Flows[1].Flow == null and Flows[2].Flow.Links.size() == 2, "the sample flow levels are read")


func _init() -> void:
	TestParse()
	TestRejects()
	TestRegions()
	TestFlow()
	TestCountdown()
	TestFiles()
	if Failures == 0:
		print("ALL PASS")
	else:
		print("FAILURES: ", Failures)
	quit(Failures)
