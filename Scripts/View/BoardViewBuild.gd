class_name BoardViewBuild
extends BoardViewTurning

## Building the board: pieces, Blockers, joins, shape and veil.

# MARK: Game lifecycle
func NewGame(Width: int, Height: int, Colors: int, Blockers: int, PresetBlockers: Array[Vector3i] = [], Gaps: Array[Vector3i] = [], PresetPieces: Array[Dictionary] = [], NewFlow: FlowField = null) -> void:
	for Child in get_children():
		Child.queue_free()
	PieceNodes.clear()
	BlockerLights.clear()
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
	Model = BoardModel.new(Width, Height, Colors, Blockers, 0, PresetBlockers, Gaps, PresetPieces, NewFlow)
	Hint.Clear()
	MovingIds.clear()
	Joins.Model = Model
	Joins.Styles = Styles
	Joins.PieceNodes = PieceNodes
	Hint.Model = Model
	Hint.Styles = Styles
	Hint.PieceNodes = PieceNodes
	Hint.IdleTime = 0.0
	# The specks that make Godot compile the hint's shaders now, just behind the middle of the board.
	Hint.WarmUp(self, Vector3(0, 0, -0.6))
	position = Vector3(0, Height / 2.0 + 0.5, 0)
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
	for Col in Model.Width:
		for Row in Model.Height:
			if Model.IsBlocker(Col, Row):
				AddBlockerLight(Col, Row, false)
				continue
			var Piece := Model.GetPiece(Col, Row)
			if Piece != null:
				AddPieceNode(Piece, CellPosition(Col, Row))


## A Blocker's light in a cell; `Grow` makes it swell in from nothing (a Blocker that has just moved there).
func AddBlockerLight(Col: int, Row: int, Grow: bool) -> void:
	var Light := BlockerLight.Create(Styles, CellPosition(Col, Row))
	Light.ZapsEnabled = BlockerZapsEnabled
	add_child(Light)
	BlockerLights.append(Light)
	if Grow:
		# Not quite nothing: a collider with a zero scale makes the physics engine complain.
		Light.scale = Vector3.ONE * 0.01
		Light.create_tween().tween_property(Light, "scale", Vector3.ONE, 0.4).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


## Malicious: moves the Blockers (see `BoardModel.RelocateBlockers`): the pieces they land on vanish, the old lights go, new ones
## swell in. The drop that follows fills the cells they left.
func RelocateBlockers() -> void:
	if Model.BlockerCount <= 0:
		return
	Hint.Clear()
	var Result := Model.RelocateBlockers()
	for Entry in Result["Gone"]:
		var Piece: BoardModel.PieceData = Entry["Piece"]
		var Node: Node3D = PieceNodes.get(Piece.Id)
		if Node != null:
			Joins.Strip(Node)
			Node.queue_free()
		PieceNodes.erase(Piece.Id)
	for Light in BlockerLights:
		if is_instance_valid(Light):
			Light.queue_free()
	BlockerLights.clear()
	for Cell in Result["New"]:
		AddBlockerLight(Cell.x, Cell.y, true)


## Malicious: lowers a colored filter (`Veil`) over the whole board that blacks out every piece of color `Kind`.
func VeilOn(Kind: int) -> void:
	VeilOff()
	VeilKind = Kind
	VeilSheet = Veil.ForBoard(Styles.Shown[Kind], Vector2(Model.Width, Model.Height) * BlockStyles.Pitch, BlockStyles.BlockSize / 2.0)
	add_child(VeilSheet)


func VeilOff() -> void:
	VeilKind = -1
	if is_instance_valid(VeilSheet):
		VeilSheet.Lift()
	VeilSheet = null


## A node for one piece standing on the board. It carries a static collider so flying pieces bounce off it.
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
	if Piece.Count > 0:
		AddCountLabel(Node, Piece.Count)
	return Node


## The number on a piece that has a countdown: white with a black outline, always facing the camera, in front of the piece.
func AddCountLabel(Node: Node3D, Count: int) -> void:
	var Label := Label3D.new()
	Label.name = "CountLabel"
	Label.text = str(Count)
	Label.font_size = 96
	Label.pixel_size = 0.0065
	Label.outline_size = 24
	Label.outline_modulate = Color.BLACK
	Label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	Label.shaded = false
	Label.double_sided = true
	Label.no_depth_test = true
	Label.render_priority = 5
	Label.position = Vector3(0, 0, BlockStyles.BlockSize / 2.0 + 0.05)
	Node.add_child(Label)


## Shows a piece's new countdown.
func UpdateCountLabel(Piece: BoardModel.PieceData) -> void:
	var Node: Node3D = PieceNodes.get(Piece.Id)
	if Node == null:
		return
	var Label := Node.get_node_or_null("CountLabel") as Label3D
	if Label != null:
		Label.text = str(Piece.Count)


## Recomputes the joins: after a shape change (so a new joined shape gets its joins, and a plain one loses them).
func RefreshJoins() -> void:
	if Model != null:
		Joins.Update(MovingIds)


## Turns the Blockers' plasma zaps on or off.
func SetBlockerZaps(On: bool) -> void:
	BlockerZapsEnabled = On
	for Light in BlockerLights:
		if is_instance_valid(Light):
			Light.ZapsEnabled = On


## Changes the shape of every piece on the board and of every piece dealt from now on.
func SetBlockShape(NewShape: int) -> void:
	Hint.Clear()
	call_deferred("RefreshJoins")
	Styles.CurrentShape = clampi(NewShape, 0, BlockStyles.Shapes.size() - 1)
	for Id in PieceNodes:
		var Node: Node3D = PieceNodes[Id]
		Styles.ApplyShape(Node, Styles.CurrentShape)
		((Node.get_child(2) as StaticBody3D).get_child(0) as CollisionShape3D).shape = Styles.ColliderShape()
