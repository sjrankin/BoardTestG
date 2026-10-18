class_name BoardView
extends Node3D
## Draws a `BoardModel` as pieces standing in a vertical grid, taps and turns, and animates falls, refills and shuffles.
## Removed pieces are handed to a `FlyerSystem`; how pieces look comes from a `BlockStyles`.
##
## In the board's own space the board lies in the XY plane (z = 0), Row 0 at the top, centered on the node's origin.
## The node sits at the board's middle and turns about it.

signal ScoreChanged(NewScore: int)
signal BoardRebuilt

const FallDuration := 0.35
## Auto Rotate: the turn about the vertical per second, and how far (and how fast) the board rocks to and fro.
const AutoYawRate := 0.3
const AutoTiltSwing := 0.55
const AutoTiltRate := 0.45
const ShuffleDuration := 0.7
## How long lightning crackles across a group before its pieces fly out.
const LightningLead := 0.2
## How far toward the camera a shuffling piece arcs at the middle of its flight.
const ShuffleLift := 2.0

var Model: BoardModel
var Styles := BlockStyles.new()
var Flyers: FlyerSystem
## How fast removed pieces leave, as a multiple of the base launch speed. Set from the controls.
var RemovalSpeed: float = 1.0:
	set(Value):
		RemovalSpeed = Value
		if Flyers != null:
			Flyers.RemovalSpeed = Value
## The board turns about its own middle: `Yaw` about the world's vertical, then `Tilt` about the board's own
## horizontal axis (so no part of it ever dips below the floor). Gravity stays world-down whatever the angle.
var Yaw: float = 0.0
var Tilt: float = 0.0
var AutoRotate: bool = false
var AutoClock: float = 0.0
## Which way is down for the user: the camera's screen-down, in world space. Set every frame by the scene.
var UserDown: Vector3 = Vector3.DOWN
## Whether lightning plays across a group as it is cleared. Set from the controls.
var LightningEnabled: bool = true
## Counts new games, so something waiting (the lightning) can tell the board it was waiting on has gone.
var GameNumber: int = 0
## Whether the Blockers throw off plasma zaps. Set from the controls.
var BlockerZapsEnabled: bool = true
var BlockerLights: Array[BlockerLight] = []
var Busy: bool = false
var PieceNodes: Dictionary = {}
var WaitingForVacate: bool = false
var VacateClock: float = 0.0
var PendingTweens: int = 0
var PendingShuffles: int = 0


# MARK: Game lifecycle

func NewGame(Width: int, Height: int, Colors: int, Blockers: int) -> void:
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
	GameNumber += 1
	Model = BoardModel.new(Width, Height, Colors, Blockers)
	position = Vector3(0, Height / 2.0 + 0.5, 0)
	ApplyRotation()
	BuildNodes()
	Busy = false
	ScoreChanged.emit(0)
	BoardRebuilt.emit()


func BuildNodes() -> void:
	for Col in Model.Width:
		for Row in Model.Height:
			if Model.IsBlocker(Col, Row):
				var Light := BlockerLight.Create(Styles, CellPosition(Col, Row))
				Light.ZapsEnabled = BlockerZapsEnabled
				add_child(Light)
				BlockerLights.append(Light)
				continue
			var Piece := Model.GetPiece(Col, Row)
			if Piece != null:
				AddPieceNode(Piece, CellPosition(Col, Row))


## The board-space position of a cell's center; also correct for cells just off the board, where new pieces queue.
func CellPosition(Col: int, Row: int) -> Vector3:
	return Vector3((Col - (Model.Width - 1) / 2.0) * BlockStyles.Pitch, (Model.Height / 2.0 - Row - 0.5) * BlockStyles.Pitch, 0.0)


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
	return Node


## Turns the Blockers' plasma zaps on or off.
func SetBlockerZaps(On: bool) -> void:
	BlockerZapsEnabled = On
	for Light in BlockerLights:
		if is_instance_valid(Light):
			Light.ZapsEnabled = On


## Changes the shape of every piece on the board and of every piece dealt from now on.
func SetBlockShape(NewShape: int) -> void:
	Styles.CurrentShape = clampi(NewShape, 0, BlockStyles.Shapes.size() - 1)
	for Id in PieceNodes:
		var Node: Node3D = PieceNodes[Id]
		Styles.ApplyShape(Node, Styles.CurrentShape)
		((Node.get_child(2) as StaticBody3D).get_child(0) as CollisionShape3D).shape = Styles.ColliderShape()


# MARK: Input

## A tap on the board along a camera ray.
func HandleTapRay(WorldOrigin: Vector3, WorldDirection: Vector3) -> void:
	if Busy or Model == null:
		return
	# The ray in the board's own space, where the board is the plane z = 0 however it is turned.
	var ToBoard := global_transform.affine_inverse()
	var Origin := ToBoard * WorldOrigin
	var Direction := ToBoard.basis * WorldDirection
	if absf(Direction.z) < 0.0001:
		return
	var T := -Origin.z / Direction.z
	if T < 0.0:
		return
	var Point := Origin + Direction * T
	var Col := floori(Point.x / BlockStyles.Pitch + Model.Width / 2.0)
	var Row := floori(Model.Height / 2.0 - Point.y / BlockStyles.Pitch)
	TapCell(Col, Row)


func TapCell(Col: int, Row: int) -> void:
	if Busy or Model == null:
		return
	var Group := Model.GroupAt(Col, Row)
	if Group.size() < BoardModel.MinimumGroupSize:
		return
	Busy = true
	var Removed := Model.Remove(Group)
	ScoreChanged.emit(Model.Score)
	var Leaving: Array[Dictionary] = []
	for Entry in Removed:
		var Piece: BoardModel.PieceData = Entry["Piece"]
		var Node: Node3D = PieceNodes.get(Piece.Id)
		PieceNodes.erase(Piece.Id)
		if Node != null:
			Leaving.append({"Node": Node, "Kind": Piece.Kind})
	if LightningEnabled and not Leaving.is_empty():
		await CrackleLightning(Leaving)
	SendFlying(Leaving)


## Lightning arcs across the pieces about to leave, while they are still in place; returns when it is time for them to go.
func CrackleLightning(Leaving: Array[Dictionary]) -> void:
	var Game := GameNumber
	var Points: Array[Vector3] = []
	for Entry in Leaving:
		Points.append((Entry["Node"] as Node3D).global_position)
	var Tint := Color(0.55, 0.75, 1.0).lerp(Styles.Palette[Leaving[0]["Kind"]], 0.3)
	LightningEffect.Play(get_parent(), Points, Tint)
	await get_tree().create_timer(LightningLead).timeout
	# A new game started while the lightning played: the pieces it was about are gone.
	if Game != GameNumber:
		Leaving.clear()


## Drops the removed pieces and starts waiting for them to leave their cells.
func SendFlying(Leaving: Array[Dictionary]) -> void:
	for Entry in Leaving:
		var Node: Node3D = Entry["Node"]
		if not is_instance_valid(Node):
			continue
		Flyers.Launch(Entry["Kind"], Node.global_position)
		Node.queue_free()
	WaitingForVacate = true
	VacateClock = 0.0


## Clears a random playable group - used by Attract Mode.
func AttractStep() -> void:
	if Busy or Model == null:
		return
	var Groups := Model.PlayableGroups()
	if Groups.is_empty():
		return
	var Group: Array = Groups[randi() % Groups.size()]
	TapCell(Group[0].x, Group[0].y)


# MARK: Turning the board

func ApplyRotation() -> void:
	basis = Basis(Vector3.UP, Yaw) * Basis(Vector3.RIGHT, Tilt)


func RotateBy(DeltaYaw: float, DeltaTilt: float) -> void:
	Yaw = wrapf(Yaw + DeltaYaw, -PI, PI)
	Tilt = wrapf(Tilt + DeltaTilt, -PI, PI)
	ApplyRotation()


## Turns the board back to face the camera, the short way round.
func Recenter() -> void:
	Yaw = wrapf(Yaw, -PI, PI)
	Tilt = wrapf(Tilt, -PI, PI)
	var Turn := create_tween()
	Turn.tween_method(RecenterStep.bind(Yaw, Tilt), 0.0, 1.0, 0.5).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)


func RecenterStep(Progress: float, StartYaw: float, StartTilt: float) -> void:
	Yaw = lerpf(StartYaw, 0.0, Progress)
	Tilt = lerpf(StartTilt, 0.0, Progress)
	ApplyRotation()


func _process(Delta: float) -> void:
	if AutoRotate:
		AutoClock += Delta
		Yaw = wrapf(Yaw + AutoYawRate * Delta, -PI, PI)
		Tilt = sin(AutoClock * AutoTiltRate) * AutoTiltSwing
		ApplyRotation()


func _physics_process(Delta: float) -> void:
	# The refill waits until every removed piece has left its cell (or a timeout), on the pieces' own clock.
	if WaitingForVacate:
		VacateClock += Delta * RemovalSpeed
		if Flyers.AllVacated() or VacateClock > FlyerSystem.VacateTimeout:
			WaitingForVacate = false
			StartDrop()


# MARK: Falling and refilling

## Gravity on the board is down as the user sees it, whatever way the board is turned: the camera's screen-down,
## taken into the board's own space and rounded to the nearest of the four grid directions.
func GravityFromUser() -> Vector2i:
	var Local := global_basis.inverse() * UserDown
	if maxf(absf(Local.x), absf(Local.y)) < 0.05:
		return Model.GravityDir
	if absf(Local.y) >= absf(Local.x):
		return Vector2i(0, 1) if Local.y < 0.0 else Vector2i(0, -1)
	return Vector2i(1, 0) if Local.x > 0.0 else Vector2i(-1, 0)


func StartDrop() -> void:
	Model.GravityDir = GravityFromUser()
	var Moves := Model.Drop()
	if Moves.is_empty():
		FinishDrop()
		return
	# Every piece falls at the same speed - the longest drop takes `FallDuration` - so pieces that start touching
	# stay touching, and a shorter drop takes proportionally less time.
	var Longest := 0.0
	for Move in Moves:
		Longest = maxf(Longest, PathLength(Move["Path"]))
	var Speed := maxf(Longest, 1.0) / FallDuration
	for Move in Moves:
		AnimateMove(Move["Piece"], Move["Path"], Speed)
	if PendingTweens == 0:
		FinishDrop()


func PathLength(Path: Array) -> float:
	var Total := 0.0
	for Index in range(1, Path.size()):
		Total += Vector2(Path[Index] - Path[Index - 1]).length() * BlockStyles.Pitch
	return Total


func AnimateMove(Piece: BoardModel.PieceData, Path: Array, Speed: float) -> void:
	var Node: Node3D = PieceNodes.get(Piece.Id)
	var IsNew := Node == null
	if IsNew:
		Node = AddPieceNode(Piece, CellPosition(Path[0].x, Path[0].y))
		Node.scale = Vector3.ONE * 0.7
	var Walk := create_tween()
	for Index in range(1, Path.size()):
		var Step: Vector2i = Path[Index]
		var Length := Vector2(Path[Index] - Path[Index - 1]).length() * BlockStyles.Pitch
		Walk.tween_property(Node, "position", CellPosition(Step.x, Step.y), Length / Speed)
	PendingTweens += 1
	Walk.finished.connect(OnMoveFinished)
	if IsNew:
		var Grow := create_tween()
		Grow.tween_property(Node, "scale", Vector3.ONE, PathLength(Path) / Speed)


func OnMoveFinished() -> void:
	PendingTweens -= 1
	if PendingTweens <= 0:
		PendingTweens = 0
		FinishDrop()


func FinishDrop() -> void:
	if Model.HasPlayableGroup():
		Busy = false
		return
	Recover()


# MARK: Shuffling

## No group of three left: shuffle what is there (up to three tries), then deal again.
func Recover() -> void:
	var Result := Model.Shuffle()
	if Result["Redealt"]:
		for Id in PieceNodes:
			PieceNodes[Id].queue_free()
		PieceNodes.clear()
		for Col in Model.Width:
			for Row in Model.Height:
				var Piece := Model.GetPiece(Col, Row)
				if Piece != null:
					var Node := AddPieceNode(Piece, CellPosition(Col, Row))
					Node.scale = Vector3.ONE * 0.01
					create_tween().tween_property(Node, "scale", Vector3.ONE, 0.4)
		get_tree().create_timer(0.45).timeout.connect(func() -> void: Busy = false)
		return
	AnimateShuffle(Result["Moves"])


## Every piece flies to its new cell in an arc toward the camera, turning once on the way and landing upright.
func AnimateShuffle(Moves: Array) -> void:
	PendingShuffles = 0
	for Move in Moves:
		var Node: Node3D = PieceNodes.get(Move["Piece"].Id)
		if Node == null:
			continue
		var To: Vector2i = Move["To"]
		var Axis := Vector3(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)).normalized()
		var Flight := create_tween()
		PendingShuffles += 1
		Flight.tween_method(ShuffleStep.bind(Node, Node.position, CellPosition(To.x, To.y), Axis), 0.0, 1.0, ShuffleDuration) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		Flight.tween_callback(OnShuffleLanded.bind(Node))
	if PendingShuffles == 0:
		Busy = false


func ShuffleStep(Progress: float, Node: Node3D, Start: Vector3, End: Vector3, Axis: Vector3) -> void:
	if not is_instance_valid(Node):
		return
	Node.position = Start.lerp(End, Progress) + Vector3(0, 0, ShuffleLift * sin(PI * Progress))
	Node.basis = Basis(Axis, TAU * Progress)


func OnShuffleLanded(Node: Node3D) -> void:
	if is_instance_valid(Node):
		Node.basis = Basis.IDENTITY
	PendingShuffles -= 1
	if PendingShuffles <= 0:
		PendingShuffles = 0
		Busy = false


## The Shuffle button: moves the pieces already on the board to other cells (never recoloring them where they sit).
func ShuffleNow() -> void:
	if Busy or Model == null:
		return
	Busy = true
	Recover()
