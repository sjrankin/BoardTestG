class_name CubeView
extends Node3D
## Draws a `CubeModel` as pieces standing over the surface of a box, taps and turns, and animates falls, refills and shuffles. The 3D
## counterpart of `BoardView`, with the same outside (signals, settings, `NewGame`, `HandleTapRay`, `AttractStep`, `ShuffleNow`, `Recenter`),
## so the scene can use either. Removed pieces go to a `FlyerSystem`, out of the face they were on; how pieces look comes from a `BlockStyles`.
##
## In the cube's own space it is centered on the node's origin, X right, Y up, Z toward the front. The node sits high enough that
## the cube clears the floor at any turn, and turns about its middle.

signal ScoreChanged(NewScore: int)
signal BoardRebuilt

const Pitch := BlockStyles.Pitch
const FallDuration := 0.35
const AutoYawRate := 0.3
const AutoTiltSwing := 0.55
const AutoTiltRate := 0.45
const ShuffleDuration := 0.7
const ShuffleLift := 2.0
const LightningLead := 0.2
## Which way the camera is (from the cube), roughly: a recenter turns a face toward it.
const CameraDirection := Vector3(0, 0.3, 1)
## The Yaw and Tilt that turn each face (in `CubeModel.Faces` order) to face the camera.
const FaceTurns: Array[Vector2] = [Vector2(0, 0), Vector2(PI, 0), Vector2(PI / 2.0, 0), Vector2(-PI / 2.0, 0), Vector2(0, PI / 2.0), Vector2(0, -PI / 2.0)]

var Model: CubeModel
var Styles := BlockStyles.new()
var Flyers: FlyerSystem
## How fast removed pieces leave, as a multiple of the base launch speed. Set from the controls.
var RemovalSpeed: float = 1.0:
	set(Value):
		RemovalSpeed = Value
		if Flyers != null:
			Flyers.RemovalSpeed = Value
## The cube turns about its own middle: `Yaw` about the world's vertical, then `Tilt` about the cube's own X axis.
var Yaw: float = 0.0
var Tilt: float = 0.0
var AutoRotate: bool = false
var AutoClock: float = 0.0
## Unused here (gravity on the cube is fixed per face); the scene sets it every frame for the 2D board.
var UserDown: Vector3 = Vector3.DOWN
var LightningEnabled: bool = true
var RemovalEffect: int = BoardView.RemovalEffects.FlyAway
var GameNumber: int = 0
## The cube has no Blockers, so there is nothing to zap.
var BlockerZapsEnabled: bool = true
var AttractActive: bool = false
var Busy: bool = false
var PieceNodes: Dictionary = {}
var WaitingForVacate: bool = false
var VacateClock: float = 0.0
var PendingTweens: int = 0
var PendingShuffles: int = 0


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
	GameNumber += 1
	Model = CubeModel.new(Width, Height, Depth, Colors)
	position = Vector3(0, Radius() + 0.5, 0)
	var Face := BestFace()
	Yaw = FaceTurns[Face].x
	Tilt = FaceTurns[Face].y
	ApplyRotation()
	BuildNodes()
	Busy = false
	ScoreChanged.emit(0)
	BoardRebuilt.emit()


func BuildNodes() -> void:
	for Cell in Model.SurfaceCells:
		var Piece := Model.GetPiece(Cell)
		if Piece != null:
			AddPieceNode(Piece, CellPosition(Cell))


## Half the cube's diagonal: how far from its middle any part of it reaches.
func Radius() -> float:
	return 0.5 * Vector3(Model.Width, Model.Height, Model.Depth).length() * Pitch


## How far the camera should stand back to see the whole cube, and where it should look.
func FrameDistance() -> float:
	return Radius() * 2.7


func FrameMiddle() -> Vector3:
	return position


## The cube-space position of a cell's center; also right for cells just off the cube, where new pieces queue.
func CellPosition(Cell: Vector3i) -> Vector3:
	return Vector3((Cell.x - (Model.Width - 1) / 2.0) * Pitch, (Cell.y - (Model.Height - 1) / 2.0) * Pitch, (Cell.z - (Model.Depth - 1) / 2.0) * Pitch)


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


## Changes the shape of every piece on the cube and of every piece dealt from now on. (The joined shapes look like their plain
## shape here: the cube does not join pieces.)
func SetBlockShape(NewShape: int) -> void:
	Styles.CurrentShape = clampi(NewShape, 0, BlockStyles.Shapes.size() - 1)
	for Id in PieceNodes:
		var Node: Node3D = PieceNodes[Id]
		Styles.ApplyShape(Node, Styles.CurrentShape)
		((Node.get_child(2) as StaticBody3D).get_child(0) as CollisionShape3D).shape = Styles.ColliderShape()


func SetBlockerZaps(On: bool) -> void:
	BlockerZapsEnabled = On


# MARK: Input

## A tap along a camera ray: the ray is taken into the cube's own space, where it meets the box's surface at the nearest face.
func HandleTapRay(WorldOrigin: Vector3, WorldDirection: Vector3) -> void:
	if Busy or Model == null:
		return
	var ToCube := global_transform.affine_inverse()
	var Origin := ToCube * WorldOrigin
	var Direction := ToCube.basis * WorldDirection
	var Size := Vector3(Model.Width, Model.Height, Model.Depth)
	var Half := Size * Pitch / 2.0
	var Near := -INF
	var Far := INF
	var NearAxis := -1
	for Axis in 3:
		if absf(Direction[Axis]) < 0.00001:
			if absf(Origin[Axis]) > Half[Axis]:
				return
			continue
		var T1: float = (-Half[Axis] - Origin[Axis]) / Direction[Axis]
		var T2: float = (Half[Axis] - Origin[Axis]) / Direction[Axis]
		if minf(T1, T2) > Near:
			Near = minf(T1, T2)
			NearAxis = Axis
		Far = minf(Far, maxf(T1, T2))
	if NearAxis < 0 or Near < 0.0 or Near > Far:
		return
	var Hit := Origin + Direction * Near
	var Index: Array[int] = [0, 0, 0]
	for Axis in 3:
		Index[Axis] = clampi(floori(Hit[Axis] / Pitch + Size[Axis] / 2.0), 0, int(Size[Axis]) - 1)
	Index[NearAxis] = 0 if Direction[NearAxis] > 0.0 else int(Size[NearAxis]) - 1
	var Cell := Vector3i(Index[0], Index[1], Index[2])
	if Model.GetPiece(Cell) != null:
		TapCell(Cell)


func TapCell(Cell: Vector3i) -> void:
	if Busy or Model == null:
		return
	var Group := Model.GroupAt(Cell)
	if Group.size() < CubeModel.MinimumGroupSize:
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
			Leaving.append({"Node": Node, "Kind": Piece.Kind, "Out": Model.OutwardAt(Entry["Cell"])})
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
	if Game != GameNumber:
		Leaving.clear()


## A basis for a launch out of a face: its Z is the way out, its Y as near to the world's up as that allows.
func LaunchBasis(Out: Vector3) -> Basis:
	var Z := Out.normalized()
	var UpHint := Vector3.UP if absf(Z.dot(Vector3.UP)) < 0.9 else Vector3.FORWARD
	var X := UpHint.cross(Z).normalized()
	return Basis(X, Z.cross(X), Z)


## Pops the removed pieces out of the faces they were on and starts waiting for them to leave their cells.
func SendFlying(Leaving: Array[Dictionary]) -> void:
	for Entry in Leaving:
		var Node: Node3D = Entry["Node"]
		if not is_instance_valid(Node):
			continue
		if RemovalEffect == BoardView.RemovalEffects.Explode:
			Flyers.Explode(Entry["Kind"], Node.global_position, randi_range(FlyerSystem.MinShardsPerPiece, FlyerSystem.MaxShardsPerPiece))
		elif RemovalEffect == BoardView.RemovalEffects.MiniMe:
			Flyers.MiniMe(Entry["Kind"], Node.global_position, randi_range(FlyerSystem.MinFragmentsPerPiece, FlyerSystem.MaxFragmentsPerPiece))
		else:
			# Out of the face the piece was on (between the faces, for an edge or corner), as the cube is turned right now.
			Flyers.Launch(Entry["Kind"], Node.global_position, LaunchBasis(global_basis * (Entry["Out"] as Vector3)))
			Flyers.AddOriginBlocker(self, Node.position)
		Node.queue_free()
	WaitingForVacate = true
	VacateClock = 0.0


## Attract Mode's move: the largest playable group; among equals, one at random.
func AttractStep() -> void:
	if Busy or Model == null:
		return
	var Best: Array = []
	var BestSize := 0
	for Group in Model.PlayableGroups():
		if Group.size() > BestSize:
			Best = [Group]
			BestSize = Group.size()
		elif Group.size() == BestSize:
			Best.append(Group)
	if Best.is_empty():
		return
	var Chosen: Array = Best[randi() % Best.size()]
	TapCell(Chosen[0])


# MARK: Turning the cube

func ApplyRotation() -> void:
	basis = Basis(Vector3.UP, Yaw) * Basis(Vector3.RIGHT, Tilt)


func RotateBy(DeltaYaw: float, DeltaTilt: float) -> void:
	Yaw = wrapf(Yaw + DeltaYaw, -PI, PI)
	Tilt = wrapf(Tilt + DeltaTilt, -PI, PI)
	ApplyRotation()


## The face to bring to the camera: the one holding the most pieces (so a long thin box shows its big face); among equals, the one
## already nearest the camera, so the cube turns as little as it can.
func BestFace() -> int:
	var Most := 0
	for Face in 6:
		Most = maxi(Most, Model.PieceCountOnFace(Face))
	var Best := 0
	var BestAlignment := -INF
	for Face in 6:
		if Model.PieceCountOnFace(Face) != Most:
			continue
		var Alignment := (global_basis * Vector3(CubeModel.FaceNormals[Face])).dot(CameraDirection.normalized()) if is_inside_tree() else 0.0
		if Alignment > BestAlignment:
			BestAlignment = Alignment
			Best = Face
	return Best


## Turns the cube so the face with the most pieces faces the camera, the short way round.
func Recenter() -> void:
	var Face := BestFace()
	Yaw = wrapf(Yaw, -PI, PI)
	Tilt = wrapf(Tilt, -PI, PI)
	var Turn := create_tween()
	Turn.tween_method(RecenterStep.bind(Yaw, Tilt, FaceTurns[Face]), 0.0, 1.0, 0.5).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)


func RecenterStep(Progress: float, StartYaw: float, StartTilt: float, Target: Vector2) -> void:
	Yaw = StartYaw + angle_difference(StartYaw, Target.x) * Progress
	Tilt = StartTilt + angle_difference(StartTilt, Target.y) * Progress
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

func StartDrop() -> void:
	Flyers.ClearOriginBlockers()
	var Moves := Model.Drop()
	if Moves.is_empty():
		FinishDrop()
		return
	# Every piece moves at the same speed - the longest path takes `FallDuration` - so pieces that start touching stay touching.
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
		Total += Vector3(Path[Index] - Path[Index - 1]).length() * Pitch
	return Total


func AnimateMove(Piece: BoardModel.PieceData, Path: Array, Speed: float) -> void:
	var Node: Node3D = PieceNodes.get(Piece.Id)
	var IsNew := Node == null
	if IsNew:
		Node = AddPieceNode(Piece, CellPosition(Path[0]))
		Node.scale = Vector3.ONE * 0.7
	var Walk := create_tween()
	for Index in range(1, Path.size()):
		var Length := Vector3(Path[Index] - Path[Index - 1]).length() * Pitch
		Walk.tween_property(Node, "position", CellPosition(Path[Index]), Length / Speed)
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
		for Cell in Model.SurfaceCells:
			var Piece := Model.GetPiece(Cell)
			if Piece != null:
				var Node := AddPieceNode(Piece, CellPosition(Cell))
				Node.scale = Vector3.ONE * 0.01
				create_tween().tween_property(Node, "scale", Vector3.ONE, 0.4)
		get_tree().create_timer(0.45).timeout.connect(func() -> void: Busy = false)
		return
	AnimateShuffle(Result["Moves"])


## Every piece flies to its new cell in an arc out from the cube, turning once on the way and landing upright.
func AnimateShuffle(Moves: Array) -> void:
	PendingShuffles = 0
	for Move in Moves:
		var Node: Node3D = PieceNodes.get(Move["Piece"].Id)
		if Node == null:
			continue
		var Axis := Vector3(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)).normalized()
		var Out := Model.OutwardAt(Move["From"])
		var Flight := create_tween()
		PendingShuffles += 1
		Flight.tween_method(ShuffleStep.bind(Node, CellPosition(Move["From"]), CellPosition(Move["To"]), Axis, Out), 0.0, 1.0, ShuffleDuration) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		Flight.tween_callback(OnShuffleLanded.bind(Node))
	if PendingShuffles == 0:
		Busy = false


func ShuffleStep(Progress: float, Node: Node3D, Start: Vector3, End: Vector3, Axis: Vector3, Out: Vector3) -> void:
	if not is_instance_valid(Node):
		return
	Node.position = Start.lerp(End, Progress) + Out * ShuffleLift * sin(PI * Progress)
	Node.basis = Basis(Axis, TAU * Progress)


func OnShuffleLanded(Node: Node3D) -> void:
	if is_instance_valid(Node):
		Node.basis = Basis.IDENTITY
	PendingShuffles -= 1
	if PendingShuffles <= 0:
		PendingShuffles = 0
		Busy = false


## The Shuffle button: moves the pieces already on the cube to other cells (never recoloring them where they sit).
func ShuffleNow() -> void:
	if Busy or Model == null:
		return
	Busy = true
	Recover()
