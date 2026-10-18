class_name BoardView
extends Node3D
## Draws a `BoardModel` as cubes standing in a vertical grid, animates falls and refills, and sends removed pieces
## flying with real rigid-body physics so they fall to the floor, bounce off the board and each other, and fade.
##
## The board lies in the XY plane (z = 0), Row 0 at the top, its bottom row resting on the floor (y = 0).

signal ScoreChanged(NewScore: int)
signal BoardRebuilt

const Pitch := 1.0
const BlockSize := 0.92
const FallDuration := 0.35
const MaxFlyers := 24
## Collision layers: 1 is the floor and flying pieces, 2 is the pieces standing on the board.
const FloorLayer := 1
const BoardLayer := 2
## A flying piece ignores the board for this long after launch, so it can't jam against its neighbors on the way out.
const LaunchClearTime := 0.25
## A flying piece has left its cell once it is a full block away, or after this long regardless.
const VacateTimeout := 2.0
const FlyerFadeDuration := 0.5
const FlyerMaxAge := 4.0
const ShuffleDuration := 0.7
## How far toward the camera a shuffling piece arcs at the middle of its flight.
const ShuffleLift := 2.0
const FlyerRestAge := 1.2

## The piece shapes. Everything about a shape - its mesh, its black edge, its collider - is built in `BuildShapes`.
enum BlockShapes { Cube, Sphere, Cone, Cylinder }
const ShapeNames: Array[String] = ["Cube", "Sphere", "Cone", "Cylinder"]
## Points around a cone's base, for its convex collider.
const ConeSegments := 24

const Palette: Array[Color] = [
	Color(0.90, 0.20, 0.20),
	Color(0.20, 0.72, 0.30),
	Color(0.20, 0.42, 0.95),
	Color(0.10, 0.80, 0.85),
	Color(0.95, 0.85, 0.20),
	Color(0.85, 0.30, 0.80),
	Color(0.55, 0.35, 0.20),
	Color(0.95, 0.55, 0.15),
]

var Model: BoardModel
## How fast removed pieces leave, as a multiple of the base launch speed (1 = the base speed). Set from the controls.
var RemovalSpeed: float = 1.0
var Busy: bool = false
var PieceNodes: Dictionary = {}
var BlockerNodes: Array[Node3D] = []
var Flyers: Array[Dictionary] = []
var WaitingForVacate: bool = false
var VacateClock: float = 0.0
var PendingTweens: int = 0
var PendingShuffles: int = 0
var Materials: Array[StandardMaterial3D] = []
var OutlineMaterial: StandardMaterial3D
## One entry per `BlockShapes` value.
var BodyMeshes: Array[Mesh] = []
var OutlineMeshes: Array[Mesh] = []
var ColliderShapes: Array[Shape3D] = []
var CurrentShape: int = BlockShapes.Cube
var FlyerMaterial: PhysicsMaterial


func _ready() -> void:
	BuildShapes()
	for Tint in Palette:
		var Material := StandardMaterial3D.new()
		Material.albedo_color = Tint
		Material.roughness = 0.45
		Materials.append(Material)
	# The black edges: a slightly larger copy of the cube drawn inside-out, so only a rim of it shows.
	OutlineMaterial = StandardMaterial3D.new()
	OutlineMaterial.albedo_color = Color.BLACK
	OutlineMaterial.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	OutlineMaterial.cull_mode = BaseMaterial3D.CULL_FRONT
	FlyerMaterial = PhysicsMaterial.new()
	FlyerMaterial.friction = 0.9
	FlyerMaterial.bounce = 0.15


# MARK: Shapes

## A body mesh and its slightly larger twin (drawn inside-out in black, so only a rim shows as the edge), plus a collider.
func BuildShapes() -> void:
	var Outline := 1.05
	# Cube
	var Cube := BoxMesh.new()
	Cube.size = Vector3.ONE * BlockSize
	var CubeEdge := BoxMesh.new()
	CubeEdge.size = Vector3.ONE * BlockSize * Outline
	var CubeBox := BoxShape3D.new()
	CubeBox.size = Vector3.ONE * BlockSize
	# Sphere
	var Ball := SphereMesh.new()
	Ball.radius = BlockSize / 2.0
	Ball.height = BlockSize
	var BallEdge := SphereMesh.new()
	BallEdge.radius = BlockSize / 2.0 * Outline
	BallEdge.height = BlockSize * Outline
	var BallShape := SphereShape3D.new()
	BallShape.radius = BlockSize / 2.0
	# Cone: apex up, base down.
	var Cone := CylinderMesh.new()
	Cone.top_radius = 0.0
	Cone.bottom_radius = BlockSize / 2.0
	Cone.height = BlockSize
	var ConeEdge := CylinderMesh.new()
	ConeEdge.top_radius = 0.0
	ConeEdge.bottom_radius = BlockSize / 2.0 * Outline
	ConeEdge.height = BlockSize * Outline
	var ConePoints := PackedVector3Array()
	ConePoints.append(Vector3(0, BlockSize / 2.0, 0))
	for Index in ConeSegments:
		var Angle := TAU * Index / ConeSegments
		ConePoints.append(Vector3(cos(Angle) * BlockSize / 2.0, -BlockSize / 2.0, sin(Angle) * BlockSize / 2.0))
	var ConeShape := ConvexPolygonShape3D.new()
	ConeShape.points = ConePoints
	# Cylinder: standing on a flat end.
	var Can := CylinderMesh.new()
	Can.top_radius = BlockSize / 2.0
	Can.bottom_radius = BlockSize / 2.0
	Can.height = BlockSize
	var CanEdge := CylinderMesh.new()
	CanEdge.top_radius = BlockSize / 2.0 * Outline
	CanEdge.bottom_radius = BlockSize / 2.0 * Outline
	CanEdge.height = BlockSize * Outline
	var CanShape := CylinderShape3D.new()
	CanShape.radius = BlockSize / 2.0
	CanShape.height = BlockSize
	BodyMeshes = [Cube, Ball, Cone, Can]
	OutlineMeshes = [CubeEdge, BallEdge, ConeEdge, CanEdge]
	ColliderShapes = [CubeBox, BallShape, ConeShape, CanShape]


## Changes the shape of every piece on the board and of every piece dealt from now on.
func SetBlockShape(NewShape: int) -> void:
	CurrentShape = clampi(NewShape, 0, BlockShapes.size() - 1)
	for Id in PieceNodes:
		var Node: Node3D = PieceNodes[Id]
		ApplyShape(Node, CurrentShape)
		((Node.get_child(2) as StaticBody3D).get_child(0) as CollisionShape3D).shape = ColliderShapes[CurrentShape]


func ApplyShape(Visual: Node3D, Shape: int) -> void:
	(Visual.get_child(0) as MeshInstance3D).mesh = BodyMeshes[Shape]
	(Visual.get_child(1) as MeshInstance3D).mesh = OutlineMeshes[Shape]


# MARK: Game lifecycle

func NewGame(Width: int, Height: int, Colors: int, Blockers: int) -> void:
	for Child in get_children():
		Child.queue_free()
	PieceNodes.clear()
	BlockerNodes.clear()
	Flyers.clear()
	WaitingForVacate = false
	PendingTweens = 0
	Model = BoardModel.new(Width, Height, Colors, Blockers)
	BuildNodes()
	Busy = false
	ScoreChanged.emit(0)
	BoardRebuilt.emit()


func BuildNodes() -> void:
	for Col in Model.Width:
		for Row in Model.Height:
			if Model.IsBlocker(Col, Row):
				AddBlocker(Col, Row)
				continue
			var Piece := Model.GetPiece(Col, Row)
			if Piece != null:
				AddPieceNode(Piece, CellPosition(Col, Row))


func CellPosition(Col: int, Row: int) -> Vector3:
	return Vector3((Col - (Model.Width - 1) / 2.0) * Pitch, (Model.Height - 1 - Row) * Pitch + Pitch / 2.0, 0.0)


func AddBlocker(Col: int, Row: int) -> void:
	var Ball := MeshInstance3D.new()
	var Mesh := SphereMesh.new()
	Mesh.radius = BlockSize / 2.0
	Mesh.height = BlockSize
	Ball.mesh = Mesh
	var Material := StandardMaterial3D.new()
	Material.albedo_color = Color(0.25, 0.25, 0.28)
	Material.roughness = 0.8
	Ball.material_override = Material
	Ball.position = CellPosition(Col, Row)
	add_child(Ball)
	BlockerNodes.append(Ball)


func MakeCubeVisual(Kind: int) -> Node3D:
	var Root := Node3D.new()
	var Body := MeshInstance3D.new()
	Body.mesh = BodyMeshes[CurrentShape]
	Body.material_override = Materials[Kind]
	Root.add_child(Body)
	var Outline := MeshInstance3D.new()
	Outline.mesh = OutlineMeshes[CurrentShape]
	Outline.material_override = OutlineMaterial
	Root.add_child(Outline)
	return Root


## A node for one piece standing on the board. It carries a static collider so flying pieces bounce off it.
func AddPieceNode(Piece: BoardModel.PieceData, At: Vector3) -> Node3D:
	var Node := MakeCubeVisual(Piece.Kind)
	var Collider := StaticBody3D.new()
	Collider.collision_layer = BoardLayer
	Collider.collision_mask = 0
	var Shape := CollisionShape3D.new()
	Shape.shape = ColliderShapes[CurrentShape]
	Collider.add_child(Shape)
	Node.add_child(Collider)
	Node.position = At
	add_child(Node)
	PieceNodes[Piece.Id] = Node
	return Node


# MARK: Input

## A tap on the board along a camera ray.
func HandleTapRay(Origin: Vector3, Direction: Vector3) -> void:
	if Busy or Model == null or absf(Direction.z) < 0.0001:
		return
	var T := -Origin.z / Direction.z
	if T < 0.0:
		return
	var Point := Origin + Direction * T
	var Col := floori(Point.x / Pitch + Model.Width / 2.0)
	var Row := Model.Height - 1 - floori(Point.y / Pitch)
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
	for Entry in Removed:
		var Piece: BoardModel.PieceData = Entry["Piece"]
		var Node: Node3D = PieceNodes.get(Piece.Id)
		PieceNodes.erase(Piece.Id)
		if Node != null:
			LaunchFlyer(Piece.Kind, Node.position)
			Node.queue_free()
	WaitingForVacate = true
	VacateClock = 0.0


## Clears the biggest playable group, or a random one - used by Attract Mode.
func AttractStep() -> void:
	if Busy or Model == null:
		return
	var Groups := Model.PlayableGroups()
	if Groups.is_empty():
		return
	var Group: Array = Groups[randi() % Groups.size()]
	TapCell(Group[0].x, Group[0].y)


# MARK: Flying pieces

func LaunchFlyer(Kind: int, From: Vector3) -> void:
	if Flyers.size() >= MaxFlyers:
		return
	var Body := RigidBody3D.new()
	Body.physics_material_override = FlyerMaterial
	Body.angular_damp = 2.5
	Body.linear_damp = 0.05
	# Launch speed times S needs gravity times S squared for the same arc, just played faster (or slower) - so a piece
	# lands where it always did, and stays in view, at any Removal Speed.
	Body.gravity_scale = RemovalSpeed * RemovalSpeed
	Body.continuous_cd = true
	Body.collision_layer = FloorLayer
	Body.collision_mask = FloorLayer
	var Shape := CollisionShape3D.new()
	Shape.shape = ColliderShapes[CurrentShape]
	Body.add_child(Shape)
	if CurrentShape == BlockShapes.Cone:
		# A cone's weight is down by its base, so it settles base-down like a real one.
		Body.center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM
		Body.center_of_mass = Vector3(0, -BlockSize / 4.0, 0)
	var Visual := MakeCubeVisual(Kind)
	# Each flyer fades on its own, so it gets its own copies of the materials.
	var Tint: StandardMaterial3D = Materials[Kind].duplicate()
	var Edge: StandardMaterial3D = OutlineMaterial.duplicate()
	(Visual.get_child(0) as MeshInstance3D).material_override = Tint
	(Visual.get_child(1) as MeshInstance3D).material_override = Edge
	Body.add_child(Visual)
	Body.position = From
	add_child(Body)
	Body.linear_velocity = Vector3(randf_range(-1.0, 1.0), randf_range(2.0, 6.0), randf_range(8.0, 13.0)) * RemovalSpeed
	Body.angular_velocity = Vector3(randf_range(-6.0, 6.0), randf_range(-6.0, 6.0), randf_range(-6.0, 6.0))
	Flyers.append({"Body": Body, "Home": From, "Age": 0.0, "Fading": false, "Tint": Tint, "Edge": Edge})


func AllVacated() -> bool:
	for Flyer in Flyers:
		if not is_instance_valid(Flyer["Body"]):
			continue
		var Body: RigidBody3D = Flyer["Body"]
		if not Flyer["Fading"] and Body.position.distance_to(Flyer["Home"]) < Pitch and Flyer["Age"] < VacateTimeout:
			return false
	return true


func StartFade(Flyer: Dictionary) -> void:
	Flyer["Fading"] = true
	for Material: StandardMaterial3D in [Flyer["Tint"], Flyer["Edge"]]:
		Material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	var FadeTween := create_tween()
	FadeTween.set_parallel(true)
	FadeTween.tween_property(Flyer["Tint"], "albedo_color:a", 0.0, FlyerFadeDuration)
	FadeTween.tween_property(Flyer["Edge"], "albedo_color:a", 0.0, FlyerFadeDuration)
	FadeTween.chain().tween_callback(Flyer["Body"].queue_free)


func _physics_process(Delta: float) -> void:
	for Index in range(Flyers.size() - 1, -1, -1):
		var Flyer := Flyers[Index]
		if not is_instance_valid(Flyer["Body"]):
			Flyers.remove_at(Index)
			continue
		var Body: RigidBody3D = Flyer["Body"]
		# Timers run on the pieces' own clock, so a slow or fast arc still gets the same time to play out.
		Flyer["Age"] += Delta * RemovalSpeed
		if Flyer["Age"] > LaunchClearTime and Body.collision_mask == FloorLayer:
			Body.collision_mask = FloorLayer | BoardLayer
		var AtRest: bool = Body.linear_velocity.length() < 0.3 and Body.angular_velocity.length() < 0.5
		if not Flyer["Fading"] and ((Flyer["Age"] > FlyerRestAge and AtRest) or Flyer["Age"] > FlyerMaxAge):
			StartFade(Flyer)
		if Flyer["Fading"] and Flyer["Age"] > FlyerMaxAge + FlyerFadeDuration + 1.0:
			Flyers.remove_at(Index)
	if WaitingForVacate:
		VacateClock += Delta * RemovalSpeed
		if AllVacated() or VacateClock > VacateTimeout:
			WaitingForVacate = false
			StartDrop()


# MARK: Falling and refilling

func StartDrop() -> void:
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
		Total += Vector2(Path[Index] - Path[Index - 1]).length() * Pitch
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
		var Length := Vector2(Path[Index] - Path[Index - 1]).length() * Pitch
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
