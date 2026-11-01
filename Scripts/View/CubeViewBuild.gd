class_name CubeViewBuild
extends CubeViewTurning

## Building the cube: pieces, joins, shape and veil.

# MARK: Game lifecycle
func NewGame(Width: int, Height: int, Depth: int, Colors: int) -> void:
	for Child in get_children():
		Child.queue_free()
	PieceNodes.clear()
	if Flyers == null:
		Flyers = FlyerSystem.new()
		Flyers.Styles = Styles
		Flyers.RemovalSpeed = RemovalSpeed
		get_parent().add_child(Flyers)
	Flyers.Reset()
	WaitingForVacate = false
	PendingTweens = 0
	InPlaceActive = 0
	GameNumber += 1
	Model = CubeModel.new(Width, Height, Depth, Colors)
	MovingIds.clear()
	Joins.Model = Model
	Joins.Styles = Styles
	Joins.PieceNodes = PieceNodes
	position = Vector3(0, Radius() + 0.5, 0)
	var Face := BestFace()
	Yaw = FaceTurns[Face].x
	Tilt = FaceTurns[Face].y
	Roll = 0.0
	VeilKind = -1
	if is_instance_valid(VeilSheet):
		VeilSheet.queue_free()
	VeilSheet = null
	if TurnLocked:
		Yaw = LockedYaw
		Tilt = 0.0
	ApplyRotation()
	BuildNodes()
	Joins.Update(MovingIds)
	Busy = false
	ScoreChanged.emit(0)
	BoardRebuilt.emit()


func BuildNodes() -> void:
	for Cell in Model.SurfaceCells:
		var Piece := Model.GetPiece(Cell)
		if Piece != null:
			AddPieceNode(Piece, CellPosition(Cell))


## A node for one piece standing on the cube. It carries a static collider so flying pieces bounce off it.
func AddPieceNode(Piece: BoardModel.PieceData, At: Vector3) -> Node3D:
	var Node := Styles.MakeVisual(Piece.Kind)
	var Collider := StaticBody3D.new()
	Collider.collision_layer = PhysicsLayers.Board
	Collider.collision_mask = 0
	var Shape := CollisionShape3D.new()
	Shape.shape = Styles.ColliderShape()
	Collider.add_child(Shape)
	Node.add_child(Collider)
	Node.position = At
	add_child(Node)
	PieceNodes[Piece.Id] = Node
	return Node


## Recomputes the joins: after a shape change (so a joined shape gets its joins, and a plain one loses them).
func RefreshJoins() -> void:
	if Model != null:
		Joins.Update(MovingIds)


## Changes the shape of every piece on the cube and of every piece dealt from now on.
func SetBlockShape(NewShape: int) -> void:
	call_deferred("RefreshJoins")
	Styles.CurrentShape = clampi(NewShape, 0, BlockStyles.Shapes.size() - 1)
	for Id in PieceNodes:
		var Node: Node3D = PieceNodes[Id]
		Styles.ApplyShape(Node, Styles.CurrentShape)
		((Node.get_child(2) as StaticBody3D).get_child(0) as CollisionShape3D).shape = Styles.ColliderShape()


func SetBlockerZaps(On: bool) -> void:
	BlockerZapsEnabled = On


## Malicious: lowers a colored filter (`Veil`) in front of the whole cube that blacks out every piece of color `Kind`.
func VeilOn(Kind: int) -> void:
	VeilOff()
	VeilKind = Kind
	VeilSheet = Veil.ForCube(Styles.Shown[Kind], self, Vector3(Model.Width, Model.Height, Model.Depth) * Pitch / 2.0, Radius())
	add_child(VeilSheet)


func VeilOff() -> void:
	VeilKind = -1
	if is_instance_valid(VeilSheet):
		VeilSheet.Lift()
	VeilSheet = null
