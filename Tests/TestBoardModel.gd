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
## Every open cell holds a piece, except cells a Blocker seals off from above (those may wait for a neighbor) - checked
## in the virtual frame, where gravity points toward higher rows whichever way the board's gravity really points.
func EveryFillableCellFull(Model: BoardModel) -> bool:
	for VCol in Model.VirtualWidth():
		for VRow in Model.VirtualHeight():
			if Model.VBlocker(VCol, VRow):
				continue
			if Model.VGet(VCol, VRow) == null and not Model.ColumnSealed(VCol, VRow):
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


func TestDropAndRefill(BlockerCount: int, Seed: int, Direction: Vector2i = Vector2i(0, 1)) -> void:
	var Model := BoardModel.new(11, 11, 5, BlockerCount, Seed)
	Model.GravityDir = Direction
	var Tag := "seed %d, gravity %s" % [Seed, Direction]
	var BlockerLayout := Model.Blockers.duplicate(true)
	Check(Model.HasPlayableGroup(), "the first deal has a playable group (%s)" % Tag)
	for Step in 60:
		var Groups := Model.PlayableGroups()
		if Groups.is_empty():
			var Result := Model.Shuffle()
			Check(Model.HasPlayableGroup(), "recovery leaves a playable group (%s)" % Tag)
			Check(Model.Blockers == BlockerLayout, "Blockers never move on a shuffle or redeal")
			continue
		var Picked: Array[Vector2i] = []
		Picked.assign(Groups[Model.Rng.randi_range(0, Groups.size() - 1)])
		var Removed := Model.Remove(Picked)
		Check(Removed.size() == Picked.size(), "everything in the group is removed")
		var Moves := Model.Drop()
		Check(EveryFillableCellFull(Model), "every refillable cell is filled after a drop (%s step %d)" % [Tag, Step])
		Check(Model.Queue.is_empty(), "no piece is left queued off the board (%s)" % Tag)
		for Move in Moves:
			var Path: Array = Move["Path"]
			var Last: Vector2i = Path[Path.size() - 1]
			Check(Model.GetPiece(Last.x, Last.y) == Move["Piece"], "a path ends where its piece is (%s)" % Tag)
			var Across := Vector2i(absi(Direction.y), absi(Direction.x))
			for Index in range(1, Path.size()):
				var Delta: Vector2i = Path[Index] - Path[Index - 1]
				var Along := Delta.x * Direction.x + Delta.y * Direction.y
				var Sideways := Delta.x * Across.x + Delta.y * Across.y
				Check(Along == 1 and absi(Sideways) <= 1, "every step goes one cell with gravity and at most one across (%s)" % Tag)
		Check(Model.Blockers == BlockerLayout, "Blockers stay put through a drop")
		if BlockerCount == 0:
			Check(CountPieces(Model) == 121, "a board with no Blockers stays full (%d, %s)" % [CountPieces(Model), Tag])
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
	for Direction in [Vector2i(0, 1), Vector2i(0, -1), Vector2i(1, 0), Vector2i(-1, 0)]:
		for Seed in [11, 22]:
			TestDropAndRefill(0, Seed, Direction)
		for Seed in [44, 55]:
			TestDropAndRefill(8, Seed, Direction)
	TestBlockerColumn()
	if Failures == 0:
		print("ALL PASS")
	else:
		print("FAILURES: ", Failures)
	quit(Failures)
