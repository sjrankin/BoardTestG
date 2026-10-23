class_name BlockerLight
extends Node3D
## A Blocker: a bright indigo light that pulses. The same idea as the Glow piece - a halo and a core of light with no
## solid surface - but blended over what is behind it, denser, and swelling and dimming in a slow loop. It sits exactly
## in its own cell, in line with the other pieces, and spreads over the pieces beside it where it reaches in front of them. It is still solid to the pieces that fly about. Like a plasma
## globe, it also throws off electrical zaps - a varying number of jagged branches radiating from its center, some red
## and some yellow or orange, each taking a new shape many times a second, and each tinted a little differently every time. The zaps are hidden by pieces in front of them (the
## halo and core are not, so a Blocker is easy to find).

const LightColor := Color(0.24, 0.02, 0.8)
## Seconds for one swell and fade.
const PulsePeriod := 1.4
## Sizes in cells: bigger and denser than a Glow piece's light, so it stands out against the pieces.
const HaloSize := 2.6
const CoreSize := 1.0
## The glow is a real ball of light centered on the cell (so it looks round from any side), drawn depth-tested: the pieces
## around it cover the parts of the ball inside or behind them, so it spreads over the neighbors' faces only where it reaches
## out in front of them, and it can't be seen through a piece. Each ball is shaded by how squarely its surface faces the
## camera, so it fades smoothly to nothing at its rim: the same radial falloff the flat glow had (opaque at the middle, then
## fading), solid out to `Solid` of the radius and gone at the rim.
const BallShaderCode := """
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled;
uniform vec4 Tint : source_color = vec4(0.24, 0.02, 0.8, 1.0);
uniform float Strength = 1.0;
void fragment() {
	float Facing = abs(dot(normalize(NORMAL), normalize(VIEW)));
	// Distance from the middle of the ball as it appears on screen, 0 at the center and 1 at the rim.
	float R = sqrt(max(1.0 - Facing * Facing, 0.0));
	float A = R < 0.4 ? mix(1.0, 0.9, R / 0.4) : (R < 0.7 ? mix(0.9, 0.4, (R - 0.4) / 0.3) : mix(0.4, 0.0, (R - 0.7) / 0.3));
	ALBEDO = Tint.rgb;
	ALPHA = A * Strength;
}
"""
static var BallShader: Shader
## The zaps: how often they take a new shape (seconds; 0 is every frame, 0.07 was the choppy original), how many branches
## there can be, how far each reaches (in cells) and how thick it is.
const ZapInterval := 0.035
const MinBranches := 2
const MaxBranches := 7
## No branch reaches past the edge of the Blocker's own cell: half a cell from the center.
const BranchReach := Vector2(0.22, 0.5)
const ZapWidth := 0.09
## Brighter than 1 so the scene's glow (bloom) picks them up.
const RedZap := Color(2.2, 0.18, 0.12)
const YellowZap := Color(2.4, 2.0, 0.45)
const OrangeZap := Color(2.4, 0.9, 0.1)
## Every branch, every time it is drawn, gets its base color shifted at random: its saturation and brightness by up to
## this fraction either way, and its hue by up to `HueVariation` of the color wheel either way (so red may lean toward
## orange or pink, yellow toward orange or lime).
const ColorVariation := 0.1
const HueVariation := 0.03

var ZapMesh: ImmediateMesh
var ZapMaterial: StandardMaterial3D
var SinceZap: float = 1.0
## Whether the plasma zaps play. Set from the controls.
var ZapsEnabled: bool = true:
	set(Value):
		ZapsEnabled = Value
		if not Value and ZapMesh != null:
			ZapMesh.clear_surfaces()


## A Blocker's light at `At` (in the board's space), starting at a random point of its pulse.
static func Create(Styles: BlockStyles, At: Vector3) -> BlockerLight:
	var Light := BlockerLight.new()
	Light.position = At
	var Halo := MeshInstance3D.new()
	Halo.mesh = MakeBall(HaloSize)
	var HaloMaterial := MakeBallMaterial(LightColor, 1.0, 1)
	Halo.material_override = HaloMaterial
	Halo.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	Light.add_child(Halo)
	var Core := MeshInstance3D.new()
	Core.mesh = MakeBall(CoreSize)
	var CoreMaterial := MakeBallMaterial(LightColor.lerp(Color.WHITE, 0.2), 1.0, 2)
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
	var Zaps := MeshInstance3D.new()
	Light.ZapMesh = ImmediateMesh.new()
	Zaps.mesh = Light.ZapMesh
	Zaps.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	Zaps.extra_cull_margin = 10.0
	Light.add_child(Zaps)
	# One material for every branch; each branch's own color comes from its vertex colors.
	Light.ZapMaterial = BoltDrawing.MakeMaterial(Color.WHITE, 5, false, true)
	Light.ZapMaterial.vertex_color_use_as_albedo = true
	return Light


## A ball of light `Diameter` cells across, centered on the cell.
static func MakeBall(Diameter: float) -> SphereMesh:
	var Ball := SphereMesh.new()
	Ball.radius = Diameter / 2.0
	Ball.height = Diameter
	Ball.radial_segments = 32
	Ball.rings = 16
	return Ball


static func MakeBallMaterial(Tint: Color, Strength: float, Priority: int) -> ShaderMaterial:
	if BallShader == null:
		BallShader = Shader.new()
		BallShader.code = BallShaderCode
	var Material := ShaderMaterial.new()
	Material.shader = BallShader
	Material.set_shader_parameter("Tint", Tint)
	Material.set_shader_parameter("Strength", Strength)
	Material.render_priority = Priority
	return Material


func _ready() -> void:
	var Halo := get_child(0) as MeshInstance3D
	var HaloMaterial := Halo.material_override as ShaderMaterial
	var CoreMaterial := (get_child(1) as MeshInstance3D).material_override as ShaderMaterial
	var Phase := randf() * TAU
	var Pulse := create_tween().set_loops()
	Pulse.tween_method(PulseStep.bind(Halo, HaloMaterial, CoreMaterial, Phase), 0.0, 1.0, PulsePeriod)


func PulseStep(Progress: float, Halo: MeshInstance3D, HaloMaterial: ShaderMaterial, CoreMaterial: ShaderMaterial, Phase: float) -> void:
	var Swell := 0.5 + 0.5 * sin(TAU * Progress + Phase)
	Halo.scale = Vector3.ONE * lerpf(0.85, 1.15, Swell)
	HaloMaterial.set_shader_parameter("Strength", lerpf(0.8, 1.0, Swell))
	CoreMaterial.set_shader_parameter("Strength", lerpf(0.92, 1.0, Swell))


func _process(Delta: float) -> void:
	if not ZapsEnabled:
		return
	SinceZap += Delta
	if SinceZap >= ZapInterval:
		SinceZap = 0.0
		RebuildZaps()


## A fresh set of branches radiating from the center in the plane the camera sees: a random number of them, each a
## jagged path of random length and direction, red, yellow or orange at random and varied a little in color.
func RebuildZaps() -> void:
	var Camera := get_viewport().get_camera_3d()
	if Camera == null:
		return
	ZapMesh.clear_surfaces()
	var ToLocal := global_basis.inverse()
	var Right := ToLocal * Camera.global_basis.x
	var Up := ToLocal * Camera.global_basis.y
	var CameraLocal := to_local(Camera.global_position)
	ZapMesh.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP, ZapMaterial)
	for Branch in randi_range(MinBranches, MaxBranches):
		var Angle := randf() * TAU
		var Tip := (Right * cos(Angle) + Up * sin(Angle)) * randf_range(BranchReach.x, BranchReach.y)
		var Path := BoltDrawing.MakePath(Vector3.ZERO, Tip, 0.28, 3)
		BoltDrawing.AddRibbon(ZapMesh, Path, ZapWidth * randf_range(0.7, 1.3), CameraLocal, VariedColor())
	ZapMesh.surface_end()


## One of the zap colors (red, yellow or orange, equally likely), varied at random in hue, saturation and brightness - so
## no two branches, and no two redraws of a branch, are quite the same color.
func VariedColor() -> Color:
	var Base := [RedZap, YellowZap, OrangeZap][randi() % 3] as Color
	var Hue := fposmod(Base.h + randf_range(-HueVariation, HueVariation), 1.0)
	var Saturation := clampf(Base.s * randf_range(1.0 - ColorVariation, 1.0 + ColorVariation), 0.0, 1.0)
	# `Base.v` is above 1 (the zaps are brighter than white, so the scene's glow catches them); it stays that way.
	var Brightness := Base.v * randf_range(1.0 - ColorVariation, 1.0 + ColorVariation)
	return Color.from_hsv(Hue, Saturation, Brightness)
