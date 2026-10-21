extends SceneTree
## Headless checks of the 3D cube's view: how a tap ray finds a piece, and how a recenter turns a face to the camera. Run:
##   /Applications/Godot.app/Contents/MacOS/Godot --headless --path . --script res://Tests/TestCubeView.gd

var Failures: int = 0


func Check(Condition: bool, Message: String) -> void:
	if not Condition:
		Failures += 1
		print("FAIL: ", Message)


func MakeView(Width: int, Height: int, Depth: int) -> CubeView:
	var View := CubeView.new()
	root.add_child(View)
	View.LightningEnabled = false
	View.NewGame(Width, Height, Depth, 5)
	return View


## Colours the cube so that `Cell` and two cells beside it are the only ones of colour 0 that touch.
func PaintGroup(View: CubeView, Cell: Vector3i) -> Array[Vector3i]:
	var Model := View.Model
	for Other in Model.SurfaceCells:
		Model.SetPiece(Other, Model.NewPiece(1 + (Other.x + Other.y * 2 + Other.z * 3 + Other.x * Other.z) % 4))
	var Group: Array[Vector3i] = [Cell]
	for Offset in CubeModel.Neighbors:
		if Group.size() < 3 and Model.IsSurface(Cell + Offset) and Model.GetPiece(Cell + Offset) != null:
			var Candidate := Cell + Offset
			Group.append(Candidate)
	for Member in Group:
		Model.SetPiece(Member, Model.NewPiece(0))
	return Group


func TestTaps() -> void:
	var View := MakeView(6, 5, 7)
	for Turn in [Vector2(0, 0), Vector2(0.7, 0.4), Vector2(-2.0, 1.0), Vector2(3.0, -0.8)]:
		View.Yaw = Turn.x
		View.Tilt = Turn.y
		View.ApplyRotation()
		for Cell in [Vector3i(2, 2, 6), Vector3i(0, 2, 3), Vector3i(3, 4, 3), Vector3i(3, 0, 2), Vector3i(5, 3, 3), Vector3i(2, 2, 0), Vector3i(0, 0, 0), Vector3i(5, 4, 6)]:
			var Group := PaintGroup(View, Cell)
			if Group.size() < 3:
				continue
			View.Busy = false
			var Target := View.to_global(View.CellPosition(Cell))
			var Out := (View.global_basis * Vector3(View.Model.FaceNormals[0]) * 0.0) + View.global_basis * View.Model.OutwardAt(Cell)
			var Direction := -Out.normalized()
			View.HandleTapRay(Target - Direction * 30.0, Direction)
			Check(View.Busy, "a tap along the outward ray at %s (turn %s) hits a piece" % [Cell, Turn])
			Check(View.Model.GetPiece(Cell) == null, "the tapped cell %s is cleared (turn %s)" % [Cell, Turn])
			View.Model.Score = 0
			View.WaitingForVacate = false
	# A ray that misses the cube does nothing.
	View.Busy = false
	View.HandleTapRay(Vector3(50, 50, 50), Vector3(1, 0, 0))
	Check(not View.Busy, "a ray that misses does nothing")
	View.queue_free()


func TestFaceTurns() -> void:
	var View := MakeView(6, 5, 7)
	for Face in 6:
		View.Yaw = View.FaceTurns[Face].x
		View.Tilt = View.FaceTurns[Face].y
		View.ApplyRotation()
		var Normal := View.global_basis * Vector3(CubeModel.FaceNormals[Face])
		Check(Normal.distance_to(Vector3.BACK) < 0.001, "face %s turns to face the camera: %s" % [CubeModel.FaceNames[Face], Normal])
	# A long thin box shows its big face.
	var Thin := MakeView(15, 3, 15)
	Check(Thin.BestFace() == CubeModel.Faces.Top or Thin.BestFace() == CubeModel.Faces.Bottom, "a flat box shows its big face")
	View.queue_free()
	Thin.queue_free()


## Runs on the first frame, when the scene tree is ready (nodes need it for their global transforms).
## Attract Mode plays every side of the cube, not just one.
func TestAttractUsesAllFaces() -> void:
	var View := MakeView(7, 7, 7)
	var Touched := {}
	for Round in 150:
		View.Busy = false
		View.WaitingForVacate = false
		View.Model.Deal()
		var Before := {}
		for Cell in View.Model.SurfaceCells:
			Before[Cell] = View.Model.GetPiece(Cell)
		View.AttractStep()
		for Cell in View.Model.SurfaceCells:
			if View.Model.GetPiece(Cell) == null and Before[Cell] != null:
				for Face in 6:
					if View.Model.OnFace(Cell, Face):
						Touched[Face] = true
	Check(Touched.size() == 6, "attract mode clears pieces on all six faces: %s" % [Touched.keys()])
	View.queue_free()


## Attract Mode's spin turns all three axes, and never fast.
func TestAttractSpin() -> void:
	var View := MakeView(5, 5, 5)
	View.AttractActive = true
	var Start := Vector3(View.Yaw, View.Tilt, View.Roll)
	var Moved := Vector3.ZERO
	var FastestStep := 0.0
	var Last := Start
	for Frame in 3600:
		View.SpinStep(1.0 / 60.0)
		var Now := Vector3(View.Yaw, View.Tilt, View.Roll)
		for Axis in 3:
			var Step := absf(angle_difference(Last[Axis], Now[Axis]))
			Moved[Axis] += Step
			FastestStep = maxf(FastestStep, Step * 60.0)
		Last = Now
	for Axis in 3:
		Check(Moved[Axis] > 1.0, "axis %d turned during a minute of attract mode (%f)" % [Axis, Moved[Axis]])
	Check(FastestStep < 0.8, "the spin is slow: %f radians a second at most" % FastestStep)
	View.queue_free()


## A drag turns the face you see with the pointer, in every orientation: the nearest piece moves down when the mouse moves down, and
## right when it moves right.
func TestDragFollowsPointer() -> void:
	var View := MakeView(5, 5, 5)
	var Turns: Array[Vector3] = [Vector3(0, 0, 0), Vector3(PI, 0, 0), Vector3(PI / 2.0, 0, 0), Vector3(-PI / 2.0, 0.3, 0), Vector3(0, PI / 2.0, 0), Vector3(0.5, -PI / 2.0, 1.0), Vector3(2.5, 0.7, -1.2), Vector3(-1.0, -0.4, 2.0)]
	for Turn in Turns:
		for Direction in 2:
			View.Yaw = Turn.x
			View.Tilt = Turn.y
			View.Roll = Turn.z
			View.ApplyRotation()
			# The piece nearest the camera (in the world, relative to the cube's middle), and where it is in the cube.
			var Nearest := Vector3.ZERO
			var NearestZ := -INF
			for Cell in View.Model.SurfaceCells:
				var World := View.global_basis * View.CellPosition(Cell)
				if World.z > NearestZ:
					NearestZ = World.z
					Nearest = World
			var Local := View.global_basis.inverse() * Nearest
			if Direction == 0:
				View.RotateBy(0.0, 0.05)
				Check((View.global_basis * Local).y < Nearest.y - 0.01, "dragging down moves the nearest piece down at turn %s" % [Turn])
			else:
				View.RotateBy(0.05, 0.0)
				Check((View.global_basis * Local).x > Nearest.x + 0.01, "dragging right moves the nearest piece right at turn %s" % [Turn])
	View.queue_free()


func _process(_Delta: float) -> bool:
	TestTaps()
	TestFaceTurns()
	TestAttractUsesAllFaces()
	TestAttractSpin()
	TestDragFollowsPointer()
	print("ALL PASS" if Failures == 0 else "%d FAILURES" % Failures)
	quit(Failures)
	return true
