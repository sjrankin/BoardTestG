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
func _process(_Delta: float) -> bool:
	TestTaps()
	TestFaceTurns()
	print("ALL PASS" if Failures == 0 else "%d FAILURES" % Failures)
	quit(Failures)
	return true
