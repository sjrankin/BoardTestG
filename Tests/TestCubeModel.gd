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
	var Gravities: Array[Vector3] = [Vector3.DOWN, Vector3(0.3, -0.9, 0.2), Vector3(-0.7, -0.5, 0.5), Vector3(0, -0.6, 0.8), Vector3(1, 0, 0), Vector3(0.1, 1, 0.1)]
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
			var Gravity := Gravities[Round % Gravities.size()]
			var Moves := Model.Drop(Gravity)
			Check(FullAndUnique(Model), "after clear %d every cell is full for %s (gravity %s)" % [Round, Size, Gravity])
			for Move in Moves:
				var Path: Array = Move["Path"]
				Check(Path.size() >= 1, "a moved piece has a path")
				Check(Path.size() >= 2 or Move["Spawned"], "only a new piece may stay where it starts")
				Check(Model.GetPiece(Path.back()) == Move["Piece"], "a path ends where its piece is for %s" % Size)
				for Index in range(1, Path.size()):
					var Step: Vector3i = Path[Index] - Path[Index - 1]
					Check(absi(Step.x) + absi(Step.y) + absi(Step.z) == 1, "path steps are one cell")
					Check(Vector3(Step).dot(Gravity.normalized()) > -0.02, "path steps never go uphill")
		Check(Model.Score == Clears, "score counts cleared pieces for %s" % Size)


func TestFlow() -> void:
	# With gravity straight down, a gap in the middle of the front face is filled by the piece above it falling.
	var Model := CubeModel.new(7, 7, 7, 5, 3)
	var Above := Model.GetPiece(Vector3i(3, 4, 6))
	Model.SetPiece(Vector3i(3, 3, 6), null)
	Model.Drop()
	Check(Model.GetPiece(Vector3i(3, 3, 6)) == Above, "the piece above a gap on the front falls into it")
	# A gap at the top of the front face (nothing above it) is filled by a new piece; the rest stay put.
	var Beside := Model.GetPiece(Vector3i(2, 6, 6))
	Model.SetPiece(Vector3i(3, 6, 6), null)
	var Before := Model.GetPiece(Vector3i(3, 5, 6))
	var Moves := Model.Drop()
	Check(Model.GetPiece(Vector3i(3, 6, 6)) != null and Model.GetPiece(Vector3i(3, 5, 6)) == Before, "a gap at the top is filled by a new piece and nothing else moves")
	Check(Moves.size() == 1 and Moves[0]["Spawned"], "the new piece is the only one that moved")
	Check(Model.GetPiece(Vector3i(2, 6, 6)) == Beside, "a gap beside it does not move its neighbour")
	# A gap in the middle of the top face has nothing above it either: a new piece, nothing slides sideways on a level face.
	var Next := Model.GetPiece(Vector3i(3, 6, 2))
	Model.SetPiece(Vector3i(3, 6, 3), null)
	Moves = Model.Drop()
	Check(Model.GetPiece(Vector3i(3, 6, 3)) != null and Model.GetPiece(Vector3i(3, 6, 2)) == Next, "a gap on the top face is filled by a new piece")
	Check(Moves.size() == 1 and Moves[0]["Spawned"], "only the new piece moved on the top face")
	# Turned so that gravity runs along +Z, pieces on a face fall that way.
	var Turned := CubeModel.new(7, 7, 7, 5, 3)
	var Behind := Turned.GetPiece(Vector3i(3, 6, 2))
	Turned.SetPiece(Vector3i(3, 6, 3), null)
	Turned.Drop(Vector3(0, -0.3, 1))
	Check(Turned.GetPiece(Vector3i(3, 6, 3)) == Behind, "on a face tilted toward +Z the piece behind a gap falls forward into it")


## New pieces enter only at the top, however the cube is turned: every new piece starts in a cell that faces the sky (the tests empty a
## good part of the cube, undersides included, at random turns).
func TestNewPiecesEnterAtTheTop() -> void:
	var Rng := RandomNumberGenerator.new()
	Rng.seed = 21
	for Trial in 40:
		var Model := CubeModel.new(9, 7, 11, 5, Trial + 1)
		var Down := Vector3(Rng.randf_range(-1, 1), Rng.randf_range(-1, 1), Rng.randf_range(-1, 1)).normalized()
		if Trial % 8 == 0:
			Down = Vector3.DOWN
		for Cell in Model.SurfaceCells:
			if Rng.randf() < 0.4:
				Model.SetPiece(Cell, null)
		var Moves := Model.Drop(Down)
		Check(FullAndUnique(Model), "a half-empty cube is full again (trial %d)" % Trial)
		for Move in Moves:
			if Move["Spawned"]:
				Check(Model.IsExposed(Move["Path"][0], -Down.normalized()), "a new piece starts facing the sky: %s for gravity %s (trial %d)" % [Move["Path"][0], Down, Trial])


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
	TestNewPiecesEnterAtTheTop()
	TestShuffle()
	print("ALL PASS" if Failures == 0 else "%d FAILURES" % Failures)
	quit(Failures)
