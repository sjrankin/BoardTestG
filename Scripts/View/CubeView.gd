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
## How far outside a piece's middle a bolt's end sits (the piece reaches about 0.46).
const BoltLift := 0.6
## Attract Mode turns the cube slowly about each of its three axes in turn: each axis takes its own sweeps, each a random angle
## (radians) over a random time (seconds), eased at both ends, so it is never fast (at most about 0.3 radians a second on average).
const SpinAngle := Vector2(0.5, 1.5)
const SpinDuration := Vector2(6.0, 14.0)
## A new piece falls in from this many cells above the cell it is created in, if that cell looks up at least this much (the dot of the
## cell's outward direction with up).
const ArrivalHeight := 4.0
const ArrivalMinUpward := 0.2
## How long a new piece with nothing to fall from takes to grow into place.
const GrowTime := 0.3
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
## The cube turns about its own middle: `Yaw` about the world's vertical, then `Tilt` about the cube's own X axis, then `Roll`
## about its own Z axis (the way it faces). Dragging turns yaw and tilt; roll is only turned by Attract Mode (and put back by Recenter).
var Yaw: float = 0.0
var Tilt: float = 0.0
var Roll: float = 0.0
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
## One sweep in progress per axis (yaw, tilt, roll): {Delta, Duration, Elapsed, Applied}.
var Sweeps: Array[Dictionary] = []


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
	Roll = 0.0
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
		# Just outside the piece's face, so the bolt runs over the surface; the blocks hide it everywhere else.
		Points.append((Entry["Node"] as Node3D).global_position + global_basis * (Entry["Out"] as Vector3) * BoltLift)
	var Tint := Color(0.55, 0.75, 1.0).lerp(Styles.Palette[Leaving[0]["Kind"]], 0.3)
	LightningEffect.Play(get_parent(), Points, Tint, true)
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


## Attract Mode's move: a face chosen at random from the six - among those with a playable group touching them - then the largest
## such group on it (a random one among equals). Over time every side gets played, not just the one that has the biggest groups.
func AttractStep() -> void:
	if Busy or Model == null:
		return
	var Groups := Model.PlayableGroups()
	var Faces: Array[int] = []
	for Face in 6:
		for Group in Groups:
			if Group.any(func(Cell: Vector3i) -> bool: return Model.OnFace(Cell, Face)):
				Faces.append(Face)
				break
	if Faces.is_empty():
		return
	var Face: int = Faces[randi() % Faces.size()]
	var Best: Array = []
	var BestSize := 0
	for Group in Groups:
		if not Group.any(func(Cell: Vector3i) -> bool: return Model.OnFace(Cell, Face)):
			continue
		if Group.size() > BestSize:
			Best = [Group]
			BestSize = Group.size()
		elif Group.size() == BestSize:
			Best.append(Group)
	var Chosen: Array = Best[randi() % Best.size()]
	TapCell(Chosen[0])


# MARK: Turning the cube

func ApplyRotation() -> void:
	basis = Basis(Vector3.UP, Yaw) * Basis(Vector3.RIGHT, Tilt) * Basis(Vector3.BACK, Roll)


## A drag turns the cube with the pointer, in screen space, whatever way it is turned: sideways about the world's vertical, up and down
## about the screen's horizontal (the camera looks along -Z, so that is the world's X axis) - so a piece on the face you see follows the
## mouse or finger. (Yaw, tilt and roll are then read back from the turned cube.)
func RotateBy(DeltaYaw: float, DeltaTilt: float) -> void:
	var Turned := Basis(Vector3.UP, DeltaYaw) * Basis(Vector3.RIGHT, DeltaTilt) * basis
	var Angles := Turned.orthonormalized().get_euler(EULER_ORDER_YXZ)
	Tilt = Angles.x
	Yaw = Angles.y
	Roll = Angles.z
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
	Roll = wrapf(Roll, -PI, PI)
	Turn.tween_method(RecenterStep.bind(Yaw, Tilt, FaceTurns[Face], Roll), 0.0, 1.0, 0.5).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)


func RecenterStep(Progress: float, StartYaw: float, StartTilt: float, Target: Vector2, StartRoll: float) -> void:
	Roll = StartRoll + angle_difference(StartRoll, 0.0) * Progress
	Yaw = StartYaw + angle_difference(StartYaw, Target.x) * Progress
	Tilt = StartTilt + angle_difference(StartTilt, Target.y) * Progress
	ApplyRotation()


## Starts a new sweep of one axis: a random direction, angle and time.
func NewSweep() -> Dictionary:
	var Direction := 1.0 if randf() < 0.5 else -1.0
	return {"Delta": Direction * randf_range(SpinAngle.x, SpinAngle.y), "Duration": randf_range(SpinDuration.x, SpinDuration.y), "Elapsed": 0.0, "Applied": 0.0}


## Attract Mode's slow turning: each axis follows its own sweeps, added to whatever the cube is doing (a drag still turns it).
func SpinStep(Delta: float) -> void:
	if Sweeps.is_empty():
		for Axis in 3:
			Sweeps.append(NewSweep())
	var Turns := [0.0, 0.0, 0.0]
	for Axis in 3:
		var Sweep := Sweeps[Axis]
		Sweep["Elapsed"] += Delta
		var Progress := clampf(Sweep["Elapsed"] / Sweep["Duration"], 0.0, 1.0)
		var Eased: float = smoothstep(0.0, 1.0, Progress) * Sweep["Delta"]
		Turns[Axis] = Eased - Sweep["Applied"]
		Sweep["Applied"] = Eased
		if Progress >= 1.0:
			Sweeps[Axis] = NewSweep()
	Yaw = wrapf(Yaw + Turns[0], -PI, PI)
	Tilt = wrapf(Tilt + Turns[1], -PI, PI)
	Roll = wrapf(Roll + Turns[2], -PI, PI)
	ApplyRotation()


func _process(Delta: float) -> void:
	if AttractActive and not AutoRotate and Model != null:
		SpinStep(Delta)
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
	var Moves := Model.Drop(Gravity())
	if Moves.is_empty():
		FinishDrop()
		return
	# Every piece moves at the same speed - the longest path takes `FallDuration` - so pieces that start touching stay touching.
	var Walks: Array[Array] = []
	var Longest := 0.0
	for Move in Moves:
		var Points := PathPoints(Move["Path"], Move["Spawned"], Move["Depth"])
		Walks.append(Points)
		Longest = maxf(Longest, PointsLength(Points))
	var Speed := maxf(Longest, 1.0) / FallDuration
	for Index in Moves.size():
		AnimateMove(Moves[Index]["Piece"], Walks[Index], Speed)
	if PendingTweens == 0:
		FinishDrop()


## Gravity in the cube's own space: world-down, however the cube is turned right now.
func Gravity() -> Vector3:
	return (global_basis.inverse() * Vector3.DOWN).normalized()


## The cube-space points a piece walks through for a path of cells. A new piece (created in the cell the path starts at) first falls
## along gravity from above the cube to that cell - higher for each round it was created later, so a column of them arrives one behind
## another - when its face looks up enough to be reached from above; a face turned away from above has nothing to fall from, so the
## piece just grows into place there (a one-point walk).
func PathPoints(Path: Array, Spawned: bool, Depth: int) -> Array[Vector3]:
	var Points: Array[Vector3] = []
	for Cell in Path:
		Points.append(CellPosition(Cell))
	if not Spawned:
		return Points
	var Up := -Gravity()
	if Up.dot(Model.OutwardAt(Path[0])) < ArrivalMinUpward:
		return Points
	Points.insert(0, Points[0] + Up * (ArrivalHeight + Depth) * Pitch)
	return Points


func PointsLength(Points: Array[Vector3]) -> float:
	var Total := 0.0
	for Index in range(1, Points.size()):
		Total += Points[Index].distance_to(Points[Index - 1])
	return Total


func AnimateMove(Piece: BoardModel.PieceData, Points: Array[Vector3], Speed: float) -> void:
	var Node: Node3D = PieceNodes.get(Piece.Id)
	var IsNew := Node == null
	if IsNew:
		Node = AddPieceNode(Piece, Points[0])
		Node.scale = Vector3.ONE * 0.7
	var Walk := create_tween()
	var Duration := PointsLength(Points) / Speed
	if Points.size() < 2:
		# Nothing to fall from: it grows where it is.
		Node.scale = Vector3.ONE * 0.01
		Duration = GrowTime
		Walk.tween_interval(GrowTime)
	for Index in range(1, Points.size()):
		Walk.tween_property(Node, "position", Points[Index], Points[Index].distance_to(Points[Index - 1]) / Speed)
	PendingTweens += 1
	Walk.finished.connect(OnMoveFinished)
	if IsNew:
		var Grow := create_tween()
		Grow.tween_property(Node, "scale", Vector3.ONE, Duration)


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
