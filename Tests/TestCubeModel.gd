extends SceneTree
## Headless checks of the 3D cube's rules. Run:
##   /Applications/Godot.app/Contents/MacOS/Godot --headless --path . --script res://Tests/TestCubeModel.gd

var Failures: int = 0


func Check(Condition: bool, Message: String) -> void:
	if not Condition:
		Failures += 1
		print("FAIL: ", Message)


func ExpectedSurface(Width: int, Height: int, Depth: int) -> int:
	return Width * Height * Depth - (Width - 2) * (Height - 2) * (Depth - 2)


## Every surface cell holds a piece, and no piece sits in two cells.
func FullAndUnique(Model: CubeModel) -> bool:
	var Ids := {}
	for Cell in Model.SurfaceCells:
		var Piece := Model.GetPiece(Cell)
		if Piece == null or Ids.has(Piece.Id):
			return false
		Ids[Piece.Id] = true
	return Model.Cells.size() == Model.SurfaceCells.size()


func TestShape() -> void:
	for Size in [Vector3i(3, 3, 3), Vector3i(11, 11, 11), Vector3i(15, 3, 15), Vector3i(4, 7, 5)]:
		var Model := CubeModel.new(Size.x, Size.y, Size.z, 5, 1)
		Check(Model.SurfaceCells.size() == ExpectedSurface(Size.x, Size.y, Size.z), "surface count for %s" % Size)
		Check(FullAndUnique(Model), "a new deal fills every cell for %s" % Size)
		Check(Model.HasPlayableGroup(), "a new deal has a playable group for %s" % Size)
		# Every face's board covers exactly the cells on its plane, once each.
		for Face in 6:
			var Seen := {}
			for Col in Model.FaceCols(Face):
				for Row in Model.FaceRows(Face):
					var Cell := Model.FaceCell(Face, Col, Row)
					Check(Model.IsSurface(Cell) and Model.OnFace(Cell, Face), "face %d cell %s is on the face" % [Face, Cell])
					Check(not Seen.has(Cell), "face %d lists %s once" % [Face, Cell])
					Seen[Cell] = true
			var OnPlane := 0
			for Cell in Model.SurfaceCells:
				if Model.OnFace(Cell, Face):
					OnPlane += 1
			Check(Seen.size() == OnPlane, "face %d board has every cell on its plane for %s" % [Face, Size])


func TestGroupsCrossEdges() -> void:
	var Model := CubeModel.new(5, 5, 5, 5, 1)
	for Cell in Model.SurfaceCells:
		Model.SetPiece(Cell, Model.NewPiece(0))
	# Paint a group of four that bends over the front-top edge, and everything else with colours that do not touch it.
	var Group: Array[Vector3i] = [Vector3i(2, 3, 4), Vector3i(2, 4, 4), Vector3i(2, 4, 3), Vector3i(2, 4, 2)]
	for Cell in Model.SurfaceCells:
		Model.SetPiece(Cell, Model.NewPiece(1 + (Cell.x + Cell.y * 2 + Cell.z * 3) % 3))
	for Cell in Group:
		Model.SetPiece(Cell, Model.NewPiece(0))
	var Found := Model.GroupAt(Vector3i(2, 3, 4))
	Check(Found.size() == 4, "a group bends over an edge: %d" % Found.size())
	# Two pieces on an edge are no group of three.
	var Small := CubeModel.new(5, 5, 5, 5, 1)
	for Cell in Small.SurfaceCells:
		Small.SetPiece(Cell, Small.NewPiece(1 + (Cell.x + Cell.y * 2 + Cell.z * 3) % 3))
	Small.SetPiece(Vector3i(2, 4, 4), Small.NewPiece(0))
	Small.SetPiece(Vector3i(3, 4, 4), Small.NewPiece(0))
	Check(Small.Remove(Small.GroupAt(Vector3i(2, 4, 4))).is_empty(), "two pieces do not clear")
	# A corner piece counts once.
	Small.SetPiece(Vector3i(4, 4, 4), Small.NewPiece(0))
	Check(Small.GroupAt(Vector3i(3, 4, 4)).size() == 3, "an edge run into a corner is three")


func TestDropFillsEverything() -> void:
	for Size in [Vector3i(3, 3, 3), Vector3i(7, 7, 7), Vector3i(11, 11, 11), Vector3i(15, 3, 15), Vector3i(3, 15, 5)]:
		var Model := CubeModel.new(Size.x, Size.y, Size.z, 5, 7)
		var Clears := 0
		for Round in 60:
			var Groups := Model.PlayableGroups()
			if Groups.is_empty():
				Model.Shuffle()
				continue
			var Group: Array = Groups[randi() % Groups.size()]
			var Removed := Model.Remove(Group)
			Clears += Removed.size()
			var Moves := Model.Drop()
			Check(FullAndUnique(Model), "after clear %d every cell is full for %s" % [Round, Size])
			Check(Model.Queue.is_empty(), "the queue is empty after a drop")
			for Move in Moves:
				var Path: Array = Move["Path"]
				Check(Path.size() >= 2, "a moved piece has a path")
				Check(Model.GetPiece(Path.back()) == Move["Piece"], "a path ends where its piece is for %s" % Size)
				for Index in range(1, Path.size()):
					Check((Path[Index] - Path[Index - 1]).abs().x + (Path[Index] - Path[Index - 1]).abs().y + (Path[Index] - Path[Index - 1]).abs().z == 1, "path steps are one cell")
		Check(Model.Score == Clears, "score counts cleared pieces for %s" % Size)


func TestFlow() -> void:
	# A gap in the middle of the front face is filled from above: the piece above it falls down.
	var Model := CubeModel.new(7, 7, 7, 5, 3)
	var Above := Model.GetPiece(Vector3i(3, 4, 6))
	Model.SetPiece(Vector3i(3, 3, 6), null)
	Model.Drop()
	Check(Model.GetPiece(Vector3i(3, 3, 6)) == Above, "the piece above a gap on the front falls into it")
	# A gap in the middle of the top face is filled from behind: the piece behind it moves toward the front.
	var Behind := Model.GetPiece(Vector3i(3, 6, 2))
	Model.SetPiece(Vector3i(3, 6, 3), null)
	Model.Drop()
	Check(Model.GetPiece(Vector3i(3, 6, 3)) == Behind, "the piece behind a gap on the top moves forward into it")
	# And on the bottom, the piece in front of a gap moves toward the back.
	var InFront := Model.GetPiece(Vector3i(3, 0, 4))
	Model.SetPiece(Vector3i(3, 0, 3), null)
	Model.Drop()
	Check(Model.GetPiece(Vector3i(3, 0, 3)) == InFront, "the piece in front of a gap on the bottom moves back into it")


func TestShuffle() -> void:
	var Model := CubeModel.new(6, 5, 7, 6, 11)
	var Before := {}
	for Cell in Model.SurfaceCells:
		Before[Model.GetPiece(Cell).Id] = Model.GetPiece(Cell).Kind
	var Result := Model.Shuffle()
	Check(FullAndUnique(Model), "a shuffle keeps every cell full")
	if not Result["Redealt"]:
		for Cell in Model.SurfaceCells:
			var Piece := Model.GetPiece(Cell)
			Check(Before.get(Piece.Id, -1) == Piece.Kind, "a shuffle does not recolour")
		Check(Model.HasPlayableGroup(), "a shuffle leaves a playable group")


func _init() -> void:
	TestShape()
	TestGroupsCrossEdges()
	TestDropFillsEverything()
	TestFlow()
	TestShuffle()
	print("ALL PASS" if Failures == 0 else "%d FAILURES" % Failures)
	quit(Failures)
