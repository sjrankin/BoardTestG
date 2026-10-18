class_name BlockerLight
extends Node3D
## A Blocker: a bright indigo light that pulses. The same idea as the Glow piece - a halo and a core of light with no
## solid surface - but blended over what is behind it, denser, and swelling and dimming in a slow loop. It sits exactly
## in its own cell, in line with the other pieces, and is drawn over the pieces beside it (which would otherwise cover
## the parts of the light that reach into their cells). It is still solid to the pieces that fly about.

const LightColor := Color(0.24, 0.02, 0.8)
## Seconds for one swell and fade.
const PulsePeriod := 1.4
## Sizes in cells: bigger and denser than a Glow piece's light, so it stands out against the pieces.
const HaloSize := 2.6
const CoreSize := 1.0


## A Blocker's light at `At` (in the board's space), starting at a random point of its pulse.
static func Create(Styles: BlockStyles, At: Vector3) -> BlockerLight:
	var Light := BlockerLight.new()
	Light.position = At
	var Halo := MeshInstance3D.new()
	var HaloMesh := QuadMesh.new()
	HaloMesh.size = Vector2.ONE * HaloSize
	Halo.mesh = HaloMesh
	var HaloMaterial := Styles.MakeGlowMaterial(Styles.BlockerFalloff, LightColor, 1.0, false)
	HaloMaterial.no_depth_test = true
	HaloMaterial.render_priority = 1
	Halo.material_override = HaloMaterial
	Halo.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	Light.add_child(Halo)
	var Core := MeshInstance3D.new()
	var CoreQuad := QuadMesh.new()
	CoreQuad.size = Vector2.ONE * CoreSize
	Core.mesh = CoreQuad
	var CoreMaterial := Styles.MakeGlowMaterial(Styles.BlockerFalloff, LightColor.lerp(Color.WHITE, 0.2), 1.0, false)
	CoreMaterial.no_depth_test = true
	CoreMaterial.render_priority = 2
	Core.material_override = CoreMaterial
	Core.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	Light.add_child(Core)
	var Collider := StaticBody3D.new()
	Collider.collision_layer = PhysicsLayers.Board
	Collider.collision_mask = 0
	var Shape := CollisionShape3D.new()
	Shape.shape = Styles.ColliderShapes[BlockStyles.Shapes.Sphere]
	Collider.add_child(Shape)
	Light.add_child(Collider)
	return Light


func _ready() -> void:
	var Halo := get_child(0) as MeshInstance3D
	var HaloMaterial := Halo.material_override as StandardMaterial3D
	var CoreMaterial := (get_child(1) as MeshInstance3D).material_override as StandardMaterial3D
	var Phase := randf() * TAU
	var Pulse := create_tween().set_loops()
	Pulse.tween_method(PulseStep.bind(Halo, HaloMaterial, CoreMaterial, Phase), 0.0, 1.0, PulsePeriod)


func PulseStep(Progress: float, Halo: MeshInstance3D, HaloMaterial: StandardMaterial3D, CoreMaterial: StandardMaterial3D, Phase: float) -> void:
	var Swell := 0.5 + 0.5 * sin(TAU * Progress + Phase)
	Halo.scale = Vector3.ONE * lerpf(0.85, 1.15, Swell)
	HaloMaterial.albedo_color.a = lerpf(0.8, 1.0, Swell)
	CoreMaterial.albedo_color.a = lerpf(0.92, 1.0, Swell)
