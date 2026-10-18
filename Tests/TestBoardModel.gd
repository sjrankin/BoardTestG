extends SceneTree
## Headless checks of the board rules. Run:
##   /Applications/Godot.app/Contents/MacOS/Godot --headless --path . --script res://Tests/TestBoardModel.gd

var Failures: int = 0


func Check(Condition: bool, Message: String) -> void:
	if not Condition:
		Failures += 1
		print("FAIL: ", Message)


func CountPieces(Model: BoardModel) -> int:
	var Total := 0
	for Col in Model.Width:
		for Row in Model.Height:
			if Model.GetPiece(Col, Row) != null:
				Total += 1
	return Total


## Every open cell holds a piece, except cells a Blocker seals off from above (those may wait for a neighbor).
func EveryFillableCellFull(Model: BoardModel) -> bool:
	for Col in Model.Width:
		for Row in Model.Height:
			if Model.IsBlocker(Col, Row):
				continue
			if Model.GetPiece(Col, Row) == null and not Model.ColumnSealed(Col, Row):
				return false
	return true


func NothingAboveBoard(Model: BoardModel) -> bool:
	for Col in Model.Width:
		for Row in range(-Model.Pad, 0):
			if Model.GetPiece(Col, Row) != null:
				return false
	return true


func TestGroups() -> void:
	var Model := BoardModel.new(5, 5, 5, 0, 1)
	for Col in 5:
		for Row in 5:
			Model.SetPiece(Col, Row, Model.NewPiece((Col + Row * 2) % 5))
	# Two touching pieces of kind 0 only: too small to clear.
	Model.SetPiece(0, 0, Model.NewPiece(7))
	Model.SetPiece(1, 0, Model.NewPiece(7))
	Check(Model.GroupAt(0, 0).size() == 2, "a pair is a group of 2")
	Check(Model.Remove(Model.GroupAt(0, 0)).is_empty(), "a pair does not clear")
	Check(Model.Score == 0, "score unchanged by a refused clear")
	# Add a third: now it clears.
	Model.SetPiece(2, 0, Model.NewPiece(7))
	var Group := Model.GroupAt(0, 0)
	Check(Group.size() == 3, "three in a row form a group of 3")
	Check(Model.Remove(Group).size() == 3, "a group of 3 clears")
	Check(Model.Score == 3, "score is 1 per piece")
	# Diagonal neighbors are not connected.
	Model.SetPiece(0, 4, Model.NewPiece(6))
	Model.SetPiece(1, 3, Model.NewPiece(6))
	Check(Model.GroupAt(0, 4).size() == 1, "diagonal pieces do not connect")


func TestDropAndRefill(BlockerCount: int, Seed: int) -> void:
	var Model := BoardModel.new(11, 11, 5, BlockerCount, Seed)
	var BlockerLayout := Model.Blockers.duplicate(true)
	Check(Model.HasPlayableGroup(), "the first deal has a playable group (seed %d)" % Seed)
	for Step in 60:
		var Groups := Model.PlayableGroups()
		if Groups.is_empty():
			var Result := Model.Shuffle()
			Check(Model.HasPlayableGroup(), "recovery leaves a playable group (seed %d)" % Seed)
			Check(Model.Blockers == BlockerLayout, "Blockers never move on a shuffle or redeal")
			continue
		var Picked: Array[Vector2i] = []
		Picked.assign(Groups[Model.Rng.randi_range(0, Groups.size() - 1)])
		var Removed := Model.Remove(Picked)
		Check(Removed.size() == Picked.size(), "everything in the group is removed")
		var Moves := Model.Drop()
		Check(EveryFillableCellFull(Model), "every refillable cell is filled after a drop (seed %d step %d)" % [Seed, Step])
		Check(NothingAboveBoard(Model), "no piece is left queued above the board (seed %d)" % Seed)
		for Move in Moves:
			var Path: Array = Move["Path"]
			var Last: Vector2i = Path[Path.size() - 1]
			Check(Model.GetPiece(Last.x, Last.y) == Move["Piece"], "a path ends where its piece is")
			for Index in range(1, Path.size()):
				var From: Vector2i = Path[Index - 1]
				var To: Vector2i = Path[Index]
				Check(To.y == From.y + 1, "every step goes down one row")
				Check(absi(To.x - From.x) <= 1, "every step moves at most one column")
				if To.x != From.x:
					var BlockerBelow := Model.IsBlocker(From.x, From.y + 1)
					var Sealed := Model.ColumnSealed(To.x, To.y)
					Check(BlockerBelow or Sealed, "a diagonal step has a reason (Blocker below, or a sealed column)")
		Check(Model.Blockers == BlockerLayout, "Blockers stay put through a drop")
		if BlockerCount == 0:
			Check(CountPieces(Model) == 121, "an empty-of-Blockers board stays full (%d)" % CountPieces(Model))
	Check(Model.Score > 0, "playing scores")


func TestBlockerColumn() -> void:
	# A Blocker on row 0 of a column: nothing is ever created for that column.
	var Model := BoardModel.new(4, 4, 4, 0, 3)
	Model.Blockers[1][0] = true
	Model.ClearCells()
	for Col in 4:
		for Row in 4:
			if not Model.IsBlocker(Col, Row):
				Model.SetPiece(Col, Row, Model.NewPiece((Col * 7 + Row * 3) % 4))
	Model.SetPiece(1, 2, null)
	Model.SetPiece(1, 3, null)
	Model.Drop()
	Check(Model.GetPiece(1, 0) == null, "no piece is created in a column with a Blocker on row 0")
	Check(Model.GetPiece(1, 3) != null, "a gap sealed under a Blocker is filled by a neighbor falling in diagonally")


func _init() -> void:
	TestGroups()
	for Seed in [11, 22, 33]:
		TestDropAndRefill(0, Seed)
	for Seed in [44, 55, 66]:
		TestDropAndRefill(8, Seed)
	TestBlockerColumn()
	if Failures == 0:
		print("ALL PASS")
	else:
		print("FAILURES: ", Failures)
	quit(Failures)
