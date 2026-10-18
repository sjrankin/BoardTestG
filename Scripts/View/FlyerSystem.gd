class_name FlyerSystem
extends Node3D
## The pieces taken off the board: each flies out as a rigid body, falls to the floor under gravity, bounces off the
## board and the other flyers, and fades. It lives in the world (a sibling of the board, not a child), so a flyer does
## not turn with the board once it has left.

const MaxFlyers := 24
## A flying piece ignores the board for this long after launch, so it can't jam against its neighbors on the way out.
const LaunchClearTime := 0.25
## A flying piece has left its cell once it is a full block away, or after this long regardless.
const VacateTimeout := 2.0
const FadeDuration := 0.5
const MaxAge := 4.0
const RestAge := 1.2
## Extra gravity on a removed piece, on top of the Removal Speed scaling: a piece falls hard, rather than floating.
const RemovalGravity := 2.5
## A cube-like flying piece stops spinning (heavy damping) the moment it touches something.
const ContactAngularDamp := 14.0

var Styles: BlockStyles
## How fast removed pieces leave, as a multiple of the base launch speed (1 = the base speed).
var RemovalSpeed: float = 1.0
var Flyers: Array[Dictionary] = []
## Solid stand-ins for the cells pieces were just removed from; they hold a flying piece up over its own gap.
var OriginBlockers: Array[Node3D] = []
var FlyerMaterial: PhysicsMaterial


func _ready() -> void:
	FlyerMaterial = PhysicsMaterial.new()
	FlyerMaterial.friction = 0.9
	FlyerMaterial.bounce = 0.15


## Forgets every flyer and removes them from the scene.
func Reset() -> void:
	Flyers.clear()
	OriginBlockers.clear()
	for Child in get_children():
		Child.queue_free()


# MARK: Origin gaps

## A cell-sized solid block (a child of `Board`, so it turns with it) where a piece was removed, so a piece flying about
## above it can't fall back through the gap it came out of - only over the edge, or through some other gap. Lasts until
## the refill starts.
func AddOriginBlocker(Board: Node3D, At: Vector3) -> void:
	var Blocker := StaticBody3D.new()
	Blocker.collision_layer = PhysicsLayers.Board
	Blocker.collision_mask = 0
	var Shape := CollisionShape3D.new()
	var Box := BoxShape3D.new()
	Box.size = Vector3.ONE * BlockStyles.BlockSize
	Shape.shape = Box
	Blocker.add_child(Shape)
	Blocker.position = At
	Board.add_child(Blocker)
	OriginBlockers.append(Blocker)


func ClearOriginBlockers() -> void:
	for Blocker in OriginBlockers:
		if is_instance_valid(Blocker):
			Blocker.queue_free()
	OriginBlockers.clear()


# MARK: Launching

## Sends a piece of color `Kind` flying from `From` (world space), out of the board's face: `BoardBasis` carries the
## launch (given in the board's own axes) into the world.
func Launch(Kind: int, From: Vector3, BoardBasis: Basis) -> void:
	if Flyers.size() >= MaxFlyers:
		return
	var Body := RigidBody3D.new()
	Body.physics_material_override = FlyerMaterial
	Body.angular_damp = 2.5
	Body.linear_damp = 0.05
	# Launch speed times S needs gravity times S squared for the same arc, just played faster (or slower) - so a piece
	# lands in the same place, and stays in view, at any Removal Speed. `RemovalGravity` then makes that arc steeper.
	Body.gravity_scale = RemovalSpeed * RemovalSpeed * RemovalGravity
	Body.continuous_cd = true
	Body.collision_layer = PhysicsLayers.Floor
	Body.collision_mask = PhysicsLayers.Floor
	Body.contact_monitor = true
	Body.max_contacts_reported = 4
	var Shape := CollisionShape3D.new()
	Shape.shape = Styles.ColliderShape()
	Body.add_child(Shape)
	if Styles.CurrentShape == BlockStyles.Shapes.Cone:
		# A cone's weight is down by its base, so it settles base-down like a real one.
		Body.center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM
		Body.center_of_mass = Vector3(0, -BlockStyles.BlockSize / 4.0, 0)
	var Visual := Styles.MakeVisual(Kind)
	# Each flyer fades on its own, so it gets its own copies of the materials.
	var FlyerBody := Visual.get_child(0) as MeshInstance3D
	var Tint: StandardMaterial3D = FlyerBody.material_override.duplicate()
	var Edge: StandardMaterial3D = Styles.OutlineMaterial.duplicate()
	FlyerBody.material_override = Tint
	(Visual.get_child(1) as MeshInstance3D).material_override = Edge
	var CoreTint: StandardMaterial3D = null
	if Styles.IsGlow():
		var FlyerCore := FlyerBody.get_node("Core") as MeshInstance3D
		CoreTint = FlyerCore.material_override.duplicate()
		FlyerCore.material_override = CoreTint
	Body.add_child(Visual)
	Body.position = From
	add_child(Body)
	var Launch := Vector3(randf_range(-1.0, 1.0), randf_range(2.0, 6.0), randf_range(8.0, 13.0)) * RemovalSpeed
	Body.linear_velocity = BoardBasis * Launch
	Body.angular_velocity = Vector3(randf_range(-6.0, 6.0), randf_range(-6.0, 6.0), randf_range(-6.0, 6.0))
	Flyers.append({"Body": Body, "Home": From, "Age": 0.0, "Fading": false, "Tint": Tint, "Edge": Edge, "Core": CoreTint,
			"StopsSpinning": Styles.CurrentShape == BlockStyles.Shapes.Cube})


## Whether every flyer has left its cell: a full block away, fading, or past the timeout.
func AllVacated() -> bool:
	for Flyer in Flyers:
		if not is_instance_valid(Flyer["Body"]):
			continue
		var Body: RigidBody3D = Flyer["Body"]
		if not Flyer["Fading"] and Body.global_position.distance_to(Flyer["Home"]) < BlockStyles.Pitch and Flyer["Age"] < VacateTimeout:
			return false
	return true


# MARK: Each frame

func StartFade(Flyer: Dictionary) -> void:
	Flyer["Fading"] = true
	var Fading: Array = [Flyer["Tint"], Flyer["Edge"]]
	if Flyer["Core"] != null:
		Fading.append(Flyer["Core"])
	var FadeTween := create_tween()
	FadeTween.set_parallel(true)
	for Material: StandardMaterial3D in Fading:
		Material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		FadeTween.tween_property(Material, "albedo_color:a", 0.0, FadeDuration)
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
		if Flyer["Age"] > LaunchClearTime and Body.collision_mask == PhysicsLayers.Floor:
			Body.collision_mask = PhysicsLayers.Floor | PhysicsLayers.Board
		# Cube-like pieces only spin while they fall: touch anything and the spin dies out.
		if Flyer["StopsSpinning"] and Flyer["Age"] > LaunchClearTime and Body.get_contact_count() > 0:
			Body.angular_damp = ContactAngularDamp
		var AtRest: bool = Body.linear_velocity.length() < 0.3 and Body.angular_velocity.length() < 0.5
		if not Flyer["Fading"] and ((Flyer["Age"] > RestAge and AtRest) or Flyer["Age"] > MaxAge):
			StartFade(Flyer)
		if Flyer["Fading"] and Flyer["Age"] > MaxAge + FadeDuration + 1.0:
			Flyers.remove_at(Index)
