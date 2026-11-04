class_name InPlaceRemoval
extends RefCounted
## The removal effects that play where the piece stands, instead of flying out (see `BoardView.RemovalEffects`):
##
## - Disappear: the piece is gone at once.
## - Spin and Shrink: it spins about its own middle on a random axis while shrinking to nothing, over `Duration`.
## - Spin then Vanish: it spins the same way, at full size, for `Duration`, then is gone.
##
## - Glowing Hot: the piece takes on a red glow, holds it for `HotHold`, then fades to nothing over `HotFade`; once it is invisible it is freed.
##   It holds its cell only for `HotRelease` after the glow starts; then `Done` is called and new pieces may fall in while it finishes fading.
##
## The piece stays in its cell while it plays, so a refill waits for it (the view counts the effects still playing).

const Duration := 0.5
## How many full turns the spin makes over the effect.
const Turns := 1.5
## Glowing Hot: how long the piece glows before it starts to fade, and how long the fade takes.
const HotHold := 0.3
const HotFade := 0.2
## Glowing Hot lets the refill start this long after the glow begins, while the piece is still fading out.
const HotRelease := 0.35
## Glowing Hot flames: how many flame puffs, and how long each lives.
const FlameCount := 12
const FlameLife := 0.22
const HotColor := Color(1.0, 0.1, 0.0)
const HotEnergy := 3.0


## Plays `Effect` (a `BoardView.RemovalEffects` value) on `Piece`, a piece already taken off the board, then frees it and calls
## `Done`. `Owner` runs the animation (it is stopped if the owner leaves the scene).
static func Play(Owner: Node, Piece: Node3D, Effect: int, Done: Callable) -> void:
	if Effect == BoardView.RemovalEffects.Disappear:
		Piece.queue_free()
		Done.call()
		return
	if Effect == BoardView.RemovalEffects.GlowingHot:
		GlowHot(Owner, Piece, Done)
		return
	var Axis := Vector3(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0), randf_range(-1.0, 1.0))
	if Axis.length() < 0.05:
		Axis = Vector3.UP
	var Turn := Owner.create_tween()
	Turn.tween_method(Step.bind(Piece, Axis.normalized(), Effect == BoardView.RemovalEffects.SpinShrink), 0.0, 1.0, Duration)
	Turn.tween_callback(Finish.bind(Piece, Done))


static func Step(Progress: float, Piece: Node3D, Axis: Vector3, Shrinks: bool) -> void:
	if not is_instance_valid(Piece):
		return
	var Size := maxf(1.0 - Progress, 0.001) if Shrinks else 1.0
	Piece.basis = Basis(Axis, TAU * Turns * Progress).scaled(Vector3.ONE * Size)


static func Finish(Piece: Node3D, Done: Callable) -> void:
	if is_instance_valid(Piece):
		Piece.queue_free()
	if Done.is_valid():
		Done.call()


## Glowing Hot: the piece (body, edge and Glow core) gets its own copies of the shared materials so only it glows, turns red-hot at once,
## and `HotHold` later fades to nothing over `HotFade`. The edge fades first (as on a flying piece) so it does not show through as a
## dark cast, and the shine is faded out early so no bright spot is left on a thinning piece.
static func GlowHot(Owner: Node, Piece: Node3D, Done: Callable) -> void:
	var Fade := Owner.create_tween()
	Fade.set_parallel(true)
	var Meshes: Array[MeshInstance3D] = []
	var Body := Piece.get_child(0) as MeshInstance3D
	Meshes.append(Body)
	Meshes.append(Piece.get_child(1) as MeshInstance3D)
	Meshes.append(Body.get_node("Core") as MeshInstance3D)
	for Mesh in Meshes:
		var Original := Mesh.material_override as StandardMaterial3D
		if not Mesh.visible or Original == null:
			continue
		var Own := Original.duplicate() as StandardMaterial3D
		Mesh.material_override = Own
		var IsEdge := Mesh == Meshes[1]
		if not IsEdge:
			Own.emission_enabled = true
			Own.emission = HotColor
			Own.emission_energy_multiplier = HotEnergy
		Own.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_DEPTH_PRE_PASS if Mesh == Body else BaseMaterial3D.TRANSPARENCY_ALPHA
		Own.render_priority = 0 if IsEdge else 1
		Fade.tween_property(Own, "albedo_color:a", 0.0, HotFade * (0.3 if IsEdge else 1.0)).set_delay(HotHold)
		if Mesh == Body:
			Fade.tween_property(Own, "metallic_specular", 0.0, HotFade * 0.4).set_delay(HotHold)
			Fade.tween_property(Own, "metallic", 0.0, HotFade * 0.4).set_delay(HotHold)
	AddFlames(Piece)
	Fade.chain().tween_callback(Finish.bind(Piece, Callable()))
	var Release := Owner.create_tween()
	Release.tween_interval(HotRelease)
	Release.tween_callback(Done)


## Flames licking up from the piece for as long as it glows (`HotHold` + `HotFade`): soft additive puffs, white-yellow to orange to
## red, that rise against world gravity in world space (so they do not turn with the board) and shrink as they go. The emitter is the
## piece's child, so the flames end with it.
static var FlameMesh: QuadMesh
static var FlameShrink: Curve
static var FlameRamp: Gradient


## The quad, size curve and color ramp every flame emitter shares, built once (a group can be dozens of pieces, and building a
## material, texture and curves for each is slow, especially in a debug build).
static func BuildFlameResources() -> void:
	if FlameMesh != null:
		return
	FlameShrink = Curve.new()
	FlameShrink.add_point(Vector2(0.0, 0.6))
	FlameShrink.add_point(Vector2(0.3, 1.0))
	FlameShrink.add_point(Vector2(1.0, 0.0))
	FlameRamp = Gradient.new()
	FlameRamp.colors = PackedColorArray([Color(1.0, 0.95, 0.5, 1.0), Color(1.0, 0.45, 0.05, 0.9), Color(0.8, 0.05, 0.0, 0.0)])
	FlameRamp.offsets = PackedFloat32Array([0.0, 0.45, 1.0])
	var Puff := GradientTexture2D.new()
	Puff.width = 64
	Puff.height = 64
	Puff.fill = GradientTexture2D.FILL_RADIAL
	Puff.fill_from = Vector2(0.5, 0.5)
	Puff.fill_to = Vector2(0.5, 0.0)
	var Falloff := Gradient.new()
	Falloff.colors = PackedColorArray([Color(1, 1, 1, 1), Color(1, 1, 1, 0)])
	Puff.gradient = Falloff
	var Material := StandardMaterial3D.new()
	Material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	Material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	Material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	Material.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	Material.vertex_color_use_as_albedo = true
	Material.albedo_texture = Puff
	Material.disable_receive_shadows = true
	FlameMesh = QuadMesh.new()
	FlameMesh.size = Vector2.ONE * BlockStyles.BlockSize * 0.6
	FlameMesh.material = Material


static func AddFlames(Piece: Node3D) -> void:
	BuildFlameResources()
	var Flames := CPUParticles3D.new()
	Flames.amount = FlameCount
	Flames.lifetime = FlameLife
	Flames.local_coords = false
	Flames.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	Flames.emission_box_extents = Vector3.ONE * BlockStyles.BlockSize * 0.4
	Flames.direction = Piece.global_basis.inverse() * Vector3.UP
	Flames.spread = 25.0
	Flames.initial_velocity_min = 0.8
	Flames.initial_velocity_max = 1.6
	Flames.gravity = Vector3.ZERO
	Flames.scale_amount_min = 0.7
	Flames.scale_amount_max = 1.2
	Flames.scale_amount_curve = FlameShrink
	Flames.color_ramp = FlameRamp
	Flames.mesh = FlameMesh
	Flames.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	Piece.add_child(Flames)
	Flames.emitting = true
