class_name LightningEffect
extends Node3D
## Electric arcs between a set of points: a jagged, crackling network of bolts that re-jitter many times a second, with
## a flash of blue light, then fade. Each bolt is three ribbons turned to face the camera - a wide faint glow, a faint
## yellow outline, and a thin bright core with a slight yellow tint - drawn over everything, so they read as light.

## How long the bolts crackle at full strength, then how long they take to fade out.
const Duration := 0.17
const FadeTime := 0.07
## The bolts take a new random shape this often (seconds; 0 is every frame, so they crackle smoothly).
const RegenInterval := 0.0
## Rounds of midpoint displacement per bolt: 2^N segments.
const Subdivisions := 5
## How far a bolt strays from a straight line, as a fraction of its length.
const Roughness := 0.22
const GlowWidth := 0.6
const OutlineWidth := 0.26
const CoreWidth := 0.11
## The chance each bolt grows a short side branch, and how long it is relative to its parent.
const BranchChance := 0.85
const BranchLength := 0.4
const FlashEnergy := 5.0
const FlashRange := 9.0
## The core is drawn brighter than white so the scene's glow (bloom) picks it up.
const CoreBrightness := 4.0
## The outline's color and its opacity at full strength, and the core's slight yellow tint.
const OutlineColor := Color(1.0, 0.85, 0.2)
const OutlineOpacity := 0.75
const CoreTint := Color(1.0, 0.96, 0.7)
## Each point also throws off a couple of short crackling stubs, so even a small group sparks.
const StubsPerPoint := 2
const StubLength := Vector2(0.6, 1.3)

var Bolts: Array[Array] = []
var Points: Array[Vector3] = []
var BoltMesh: ImmediateMesh
var GlowMaterial: StandardMaterial3D
var OutlineMaterial: StandardMaterial3D
var CoreMaterial: StandardMaterial3D
var Flash: OmniLight3D
var Age: float = 0.0
var SinceRegen: float = 1.0
var BaseColor: Color = Color(0.6, 0.8, 1.0)


## Plays lightning joining `Points` (world space) under `Parent`. Does nothing for fewer than two points.
static func Play(Parent: Node, Points: Array[Vector3], Tint: Color) -> void:
	if Points.size() < 2:
		return
	var Effect := LightningEffect.new()
	Effect.BaseColor = Tint
	Effect.Points = Points
	Effect.Bolts = Effect.JoinPoints(Points)
	Parent.add_child(Effect)
	Effect.global_position = Vector3.ZERO
	var Centroid := Vector3.ZERO
	for Point in Points:
		Centroid += Point
	Effect.Flash.global_position = Centroid / Points.size()


func _ready() -> void:
	BoltMesh = ImmediateMesh.new()
	var Instance := MeshInstance3D.new()
	Instance.mesh = BoltMesh
	Instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# The bolts are rebuilt in world space each time, so the mesh must never be culled by a stale bounding box.
	Instance.extra_cull_margin = 100.0
	add_child(Instance)
	GlowMaterial = BoltDrawing.MakeMaterial(Color(BaseColor, 0.4), 2)
	OutlineMaterial = BoltDrawing.MakeMaterial(Color(OutlineColor, OutlineOpacity), 3)
	var Bright := CoreTint * CoreBrightness
	CoreMaterial = BoltDrawing.MakeMaterial(Color(Bright.r, Bright.g, Bright.b, 1.0), 4)
	Flash = OmniLight3D.new()
	Flash.light_color = BaseColor.lerp(Color(0.5, 0.7, 1.0), 0.5)
	Flash.omni_range = FlashRange
	Flash.light_energy = FlashEnergy
	Flash.shadow_enabled = false
	add_child(Flash)


# MARK: Which points get a bolt

## A network joining every point: each new bolt connects the nearest point not yet joined to the ones that are, so the
## arcs spread across the group like a tree - plus a couple of extra random links so it crackles back on itself.
func JoinPoints(Points: Array[Vector3]) -> Array[Array]:
	var Links: Array[Array] = []
	var Joined: Array[Vector3] = [Points[0]]
	var Remaining: Array[Vector3] = Points.slice(1)
	while not Remaining.is_empty():
		var Best := [0, Vector3.ZERO, INF]
		for Index in Remaining.size():
			for Anchor in Joined:
				var Distance := Anchor.distance_to(Remaining[Index])
				if Distance < Best[2]:
					Best = [Index, Anchor, Distance]
		var Next: Vector3 = Remaining[Best[0]]
		Links.append([Best[1], Next])
		Joined.append(Next)
		Remaining.remove_at(Best[0])
	for Extra in mini(4, Points.size() / 2):
		var A := Points[randi() % Points.size()]
		var B := Points[randi() % Points.size()]
		if A.distance_to(B) > 0.5:
			Links.append([A, B])
	return Links


# MARK: Each frame

func _process(Delta: float) -> void:
	Age += Delta
	SinceRegen += Delta
	var Strength := clampf((Duration + FadeTime - Age) / FadeTime, 0.0, 1.0)
	GlowMaterial.albedo_color.a = 0.4 * Strength
	OutlineMaterial.albedo_color.a = OutlineOpacity * Strength
	CoreMaterial.albedo_color.a = Strength
	Flash.light_energy = FlashEnergy * Strength * (0.6 + 0.4 * randf())
	if SinceRegen >= RegenInterval and Strength > 0.0:
		SinceRegen = 0.0
		Rebuild()
	if Age > Duration + FadeTime:
		queue_free()


## Draws every bolt (and its branches) again with a new random shape.
func Rebuild() -> void:
	var Camera := get_viewport().get_camera_3d()
	if Camera == null:
		return
	BoltMesh.clear_surfaces()
	var Paths: Array[PackedVector3Array] = []
	var Widths: Array[float] = []
	for Link in Bolts:
		var Path := BoltDrawing.MakePath(Link[0], Link[1], Roughness)
		Paths.append(Path)
		Widths.append(1.0)
		if randf() < BranchChance:
			var Start := Path[randi_range(4, Path.size() - 5)]
			var Reach: float = (Link[1] - Link[0]).length() * BranchLength
			var Away: Vector3 = Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)).normalized() * Reach
			Paths.append(BoltDrawing.MakePath(Start, Start + Away, Roughness * 1.4))
			Widths.append(0.55)
	for Point in Points:
		for Stub in StubsPerPoint:
			var Out: Vector3 = Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)).normalized() * randf_range(StubLength.x, StubLength.y)
			Paths.append(BoltDrawing.MakePath(Point, Point + Out, 0.3))
			Widths.append(0.5)
	var Layers := [[GlowMaterial, GlowWidth], [OutlineMaterial, OutlineWidth], [CoreMaterial, CoreWidth]]
	for Layer in Layers:
		BoltMesh.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP, Layer[0])
		for Index in Paths.size():
			BoltDrawing.AddRibbon(BoltMesh, Paths[Index], Layer[1] * Widths[Index], Camera.global_position)
		BoltMesh.surface_end()
