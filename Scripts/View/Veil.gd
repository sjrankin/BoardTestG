class_name Veil
extends MeshInstance3D
## The Malicious veil (Settings > Malicious): one large, flat, zero-thickness sheet in front of the whole set of pieces that works
## like a colored filter. It multiplies what is behind it by the filter color, which is chosen from the hidden piece color so that
## color comes out nearly black (a red piece behind a cyan filter), while the other colors are only tinted and dimmed.
##
## On the 2D board the sheet is a child of the board, in front of its face, so it turns with the board and is seen foreshortened
## as the board is tilted or turned. On the cube, which has pieces facing every way, the sheet is a world-space rectangle that faces
## the camera in front of the cube and is refitted every frame to the cube's outline as seen from there.

## How long the filter takes to come down or lift, in seconds.
const AnimationTime := 0.5
## The sheet stands this far in front of the pieces of a 2D board (cells), and reaches this far beyond its edges.
const SheetGap := 0.3
const EdgeMargin := 0.6
## The cube's sheet is this far in front of the cube's bounding sphere, as a share of its radius, and reaches this far past the outline.
const CubeStandOff := 1.05
const CubeMargin := 0.4

## The cube the sheet fits (null on a 2D board), and half the size of its bounding box, in its own space.
var Target: Node3D
var Extents: Vector3 = Vector3.ZERO
var Radius: float = 1.0
var Filter: Color = Color.WHITE
var Lifting: bool = false


## The filter color that blacks out `Hidden`: its complement, scaled so the brightest channel is full. (A plain mid grey has no
## complement to speak of, so it is dimmed instead.)
static func FilterColor(Hidden: Color) -> Color:
	# A color with next to no hue (a faded or white piece) has no complement to speak of: the filter just dims.
	if maxf(maxf(Hidden.r, Hidden.g), Hidden.b) - minf(minf(Hidden.r, Hidden.g), Hidden.b) < 0.2:
		return Color(0.4, 0.45, 0.5)
	var Inverse := Color(1.0 - Hidden.r, 1.0 - Hidden.g, 1.0 - Hidden.b)
	var Brightest := maxf(maxf(Inverse.r, Inverse.g), maxf(Inverse.b, 0.001))
	return Color(Inverse.r / Brightest, Inverse.g / Brightest, Inverse.b / Brightest)


## A sheet in front of the face of a 2D board `BoardSize` (width, height, in space units) across, centered on the board's middle.
## The caller adds it as a child of the board.
static func ForBoard(Hidden: Color, BoardSize: Vector2, FaceZ: float) -> Veil:
	var Sheet := Veil.new()
	Sheet.Setup(Hidden)
	var Width := BoardSize.x + EdgeMargin * 2.0
	var Height := BoardSize.y + EdgeMargin * 2.0
	Sheet.scale = Vector3(Width, Height, 1.0)
	Sheet.position = Vector3(0.0, 0.0, FaceZ + SheetGap)
	return Sheet


## A camera-facing sheet for the cube `Target`, whose box is `HalfExtents` (half its width, height, depth) in its own space and whose
## bounding sphere has radius `SphereRadius`. The caller adds it to the world, near the cube.
static func ForCube(Hidden: Color, Cube: Node3D, HalfExtents: Vector3, SphereRadius: float) -> Veil:
	var Sheet := Veil.new()
	Sheet.Setup(Hidden)
	Sheet.top_level = true
	Sheet.Target = Cube
	Sheet.Extents = HalfExtents
	Sheet.Radius = SphereRadius
	return Sheet


func Setup(Hidden: Color) -> void:
	name = "Veil"
	var Quad := QuadMesh.new()
	Quad.size = Vector2.ONE
	mesh = Quad
	var Glass := StandardMaterial3D.new()
	Glass.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	Glass.blend_mode = BaseMaterial3D.BLEND_MODE_MUL
	Glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	Glass.cull_mode = BaseMaterial3D.CULL_DISABLED
	Glass.no_depth_test = false
	Glass.albedo_color = Color.WHITE
	material_override = Glass
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	Filter = FilterColor(Hidden)


func _ready() -> void:
	Fade(Filter)
	Place()


func _process(_Delta: float) -> void:
	Place()


## Fades the sheet's color to `To` (white is clear).
func Fade(To: Color) -> void:
	var Glass := material_override as StandardMaterial3D
	create_tween().tween_property(Glass, "albedo_color", To, AnimationTime).set_trans(Tween.TRANS_SINE)


## Lifts the filter: it clears, and the sheet is freed.
func Lift() -> void:
	if Lifting:
		return
	Lifting = true
	var Glass := material_override as StandardMaterial3D
	var Clear := create_tween()
	Clear.tween_property(Glass, "albedo_color", Color.WHITE, AnimationTime).set_trans(Tween.TRANS_SINE)
	Clear.tween_callback(queue_free)


## The sheet's color as it is now (the filter once it has come down).
func CurrentColor() -> Color:
	return (material_override as StandardMaterial3D).albedo_color


## Keeps a cube's sheet in front of the cube, facing the camera, just large enough to cover the cube's outline from there. A 2D
## board's sheet is fixed to the board and needs nothing.
func Place() -> void:
	if Target == null or not is_instance_valid(Target) or not is_inside_tree():
		return
	var Eye := get_viewport().get_camera_3d()
	if Eye == null:
		return
	var Middle := Target.global_position
	var ToEye := (Eye.global_position - Middle).normalized()
	var Origin := Middle + ToEye * Radius * CubeStandOff
	var Plane := Basis.looking_at(-ToEye, Eye.global_basis.y)
	var Rect := Rect2()
	var First := true
	for Corner in 8:
		var Local := Vector3(Extents.x if Corner & 1 else -Extents.x, Extents.y if Corner & 2 else -Extents.y, Extents.z if Corner & 4 else -Extents.z)
		var World := Target.global_transform * Local
		var Ray := World - Eye.global_position
		var Along := (Origin - Eye.global_position).dot(-Plane.z)
		var Hit := Eye.global_position + Ray * (Along / maxf(Ray.dot(-Plane.z), 0.001)) - Origin
		var Point := Vector2(Hit.dot(Plane.x), Hit.dot(Plane.y))
		if First:
			Rect = Rect2(Point, Vector2.ZERO)
			First = false
		else:
			Rect = Rect.expand(Point)
	Rect = Rect.grow(CubeMargin)
	var Center := Origin + Plane.x * Rect.get_center().x + Plane.y * Rect.get_center().y
	global_transform = Transform3D(Basis(Plane.x * Rect.size.x, Plane.y * Rect.size.y, Plane.z), Center)
