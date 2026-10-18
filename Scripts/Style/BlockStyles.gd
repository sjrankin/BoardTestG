class_name BlockStyles
extends RefCounted
## How a piece looks and what it collides as: the shapes (a mesh, a black-edge twin, and a collider each), the color
## materials, and the light materials of the Glow shape. One instance is shared by everything that draws a piece.

## The distance between cell centers, and the size of a piece within its cell.
const Pitch := 1.0
const BlockSize := 0.92

## The piece shapes. `BodyMeshes`, `OutlineMeshes` and `ColliderShapes` have one entry per value.
## (New shapes go on the end, so a remembered shape keeps meaning the same thing.)
enum Shapes { Cube, Sphere, Cone, Cylinder, Glow, RoundedCube }
const ShapeNames: Array[String] = ["Cube", "Sphere", "Cone", "Cylinder", "Glow", "Rounded Cube"]
## The rounded cube's corner radius, as a fraction of its size (as in BoardTestRK).
const RoundedCubeRadius := 0.25

## The Glow piece: a soft ball of light with no surface. A big faint halo plus a small bright core, both camera-facing
## quads drawn additively with a radial falloff, and no shadow. Sizes are in cells.
const GlowHaloSize := 2.1
const GlowCoreSize := 0.7
const GlowTextureSize := 128
## Points around a cone's base, for its convex collider.
const ConeSegments := 24
## How much larger than the piece its black edge is drawn.
const OutlineScale := 1.05
## How rough the color materials are: the matte look, and the glossy one with Specular on.
const MatteRoughness := 0.45
const SpecularRoughness := 0.14

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

var CurrentShape: int = Shapes.Cube
var SpecularEnabled: bool = false
var Materials: Array[StandardMaterial3D] = []
var OutlineMaterial: StandardMaterial3D
var BodyMeshes: Array[Mesh] = []
var OutlineMeshes: Array[Mesh] = []
var ColliderShapes: Array[Shape3D] = []
var CoreMesh: Mesh
## Glow materials, one per color: the halo and the brighter core.
var GlowHaloMaterials: Array[StandardMaterial3D] = []
var GlowCoreMaterials: Array[StandardMaterial3D] = []
## Radial falloffs: the Glow piece's soft one, and the denser one a Blocker's light uses.
var GlowFalloff: GradientTexture2D
var BlockerFalloff: GradientTexture2D


func _init() -> void:
	BuildShapes()
	for Tint in Palette:
		var Material := StandardMaterial3D.new()
		Material.albedo_color = Tint
		Material.roughness = MatteRoughness
		Materials.append(Material)
	BuildGlowMaterials()
	# The black edges: a slightly larger copy of the piece drawn inside-out, so only a rim of it shows.
	OutlineMaterial = StandardMaterial3D.new()
	OutlineMaterial.albedo_color = Color.BLACK
	OutlineMaterial.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	OutlineMaterial.cull_mode = BaseMaterial3D.CULL_FRONT


# MARK: Using a style

## Glossy, mirror-like pieces (a hard bright highlight, a clear coat, reflections of the sky) when `On`, the matte look
## otherwise. Applies to every solid shape's color materials - not to the Glow piece, which is only light - and to every
## piece already on the board, since they share these materials.
func SetSpecular(On: bool) -> void:
	SpecularEnabled = On
	for Material in Materials:
		Material.roughness = SpecularRoughness if On else MatteRoughness
		Material.metallic_specular = 1.0 if On else 0.5
		Material.clearcoat_enabled = On
		Material.clearcoat = 0.9
		Material.clearcoat_roughness = 0.06


## Whether the current shape is one of the two cube-like ones, which stop spinning the moment they touch something.
func IsCubeLike() -> bool:
	return CurrentShape == Shapes.Cube or CurrentShape == Shapes.RoundedCube


func IsGlow() -> bool:
	return CurrentShape == Shapes.Glow


## The collider of the current shape.
func ColliderShape() -> Shape3D:
	return ColliderShapes[CurrentShape]


## A new visual for a piece of color `Kind`, dressed for the current shape. Its children are the body (0), whose own
## child "Core" is the Glow light's center, and the black edge (1); the caller may add more after them.
func MakeVisual(Kind: int) -> Node3D:
	var Root := Node3D.new()
	Root.set_meta("Kind", Kind)
	var Body := MeshInstance3D.new()
	Root.add_child(Body)
	var Core := MeshInstance3D.new()
	Core.name = "Core"
	Core.mesh = CoreMesh
	Core.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	Body.add_child(Core)
	var Outline := MeshInstance3D.new()
	Outline.material_override = OutlineMaterial
	Root.add_child(Outline)
	ApplyShape(Root, CurrentShape)
	return Root


## Dresses a piece's visual (body, edge, and the Glow core) for `Shape`, in the color stored on it.
func ApplyShape(Visual: Node3D, Shape: int) -> void:
	var Kind: int = Visual.get_meta("Kind")
	var Body := Visual.get_child(0) as MeshInstance3D
	var Edge := Visual.get_child(1) as MeshInstance3D
	var Core := Body.get_node("Core") as MeshInstance3D
	var Glowing := Shape == Shapes.Glow
	Body.mesh = BodyMeshes[Shape]
	Body.material_override = GlowHaloMaterials[Kind] if Glowing else Materials[Kind]
	Body.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF if Glowing else GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	Edge.mesh = OutlineMeshes[Shape]
	Edge.visible = not Glowing
	Core.visible = Glowing
	Core.material_override = GlowCoreMaterials[Kind]


## `Additive` light adds to what is behind it (the Glow pieces); otherwise it blends over it, which keeps a dark light
## looking its own color in front of bright pieces instead of washing out to pink.
func MakeGlowMaterial(Texture: Texture2D, Tint: Color, Strength: float, Additive: bool = true) -> StandardMaterial3D:
	var Material := StandardMaterial3D.new()
	Material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	Material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	Material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD if Additive else BaseMaterial3D.BLEND_MODE_MIX
	Material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	Material.cull_mode = BaseMaterial3D.CULL_DISABLED
	Material.no_depth_test = false
	Material.albedo_texture = Texture
	Material.albedo_color = Color(Tint, Strength)
	return Material


# MARK: Building

func MakeFalloff(Offsets: PackedFloat32Array, Alphas: Array[float]) -> GradientTexture2D:
	var Falloff := Gradient.new()
	Falloff.offsets = Offsets
	var Colors := PackedColorArray()
	for Alpha in Alphas:
		Colors.append(Color(1, 1, 1, Alpha))
	Falloff.colors = Colors
	var Texture := GradientTexture2D.new()
	Texture.gradient = Falloff
	Texture.fill = GradientTexture2D.FILL_RADIAL
	Texture.fill_from = Vector2(0.5, 0.5)
	Texture.fill_to = Vector2(1.0, 0.5)
	Texture.width = GlowTextureSize
	Texture.height = GlowTextureSize
	return Texture


## The materials of the Glow piece: a radial falloff texture, unshaded and additive so overlapping lights add up.
func BuildGlowMaterials() -> void:
	GlowFalloff = MakeFalloff(PackedFloat32Array([0.0, 0.25, 0.6, 1.0]), [1.0, 0.55, 0.12, 0.0])
	# The Blocker's own falloff: nearly solid out to the middle of the halo, then fading, so it is hard to miss.
	BlockerFalloff = MakeFalloff(PackedFloat32Array([0.0, 0.4, 0.7, 1.0]), [1.0, 0.9, 0.4, 0.0])
	for Tint in Palette:
		GlowHaloMaterials.append(MakeGlowMaterial(GlowFalloff, Tint, 0.85))
		GlowCoreMaterials.append(MakeGlowMaterial(GlowFalloff, Tint.lerp(Color.WHITE, 0.65), 1.0))


## A body mesh and its slightly larger twin (drawn inside-out in black, so only a rim shows as the edge), plus a collider.
func BuildShapes() -> void:
	var Half := BlockSize / 2.0
	var Edge := OutlineScale
	# Cube
	var Cube := BoxMesh.new()
	Cube.size = Vector3.ONE * BlockSize
	var CubeEdge := BoxMesh.new()
	CubeEdge.size = Vector3.ONE * BlockSize * Edge
	var CubeBox := BoxShape3D.new()
	CubeBox.size = Vector3.ONE * BlockSize
	# Sphere
	var Ball := SphereMesh.new()
	Ball.radius = Half
	Ball.height = BlockSize
	var BallEdge := SphereMesh.new()
	BallEdge.radius = Half * Edge
	BallEdge.height = BlockSize * Edge
	var BallShape := SphereShape3D.new()
	BallShape.radius = Half
	# Cone: apex up, base down.
	var Cone := CylinderMesh.new()
	Cone.top_radius = 0.0
	Cone.bottom_radius = Half
	Cone.height = BlockSize
	var ConeEdge := CylinderMesh.new()
	ConeEdge.top_radius = 0.0
	ConeEdge.bottom_radius = Half * Edge
	ConeEdge.height = BlockSize * Edge
	var ConePoints := PackedVector3Array()
	ConePoints.append(Vector3(0, Half, 0))
	for Index in ConeSegments:
		var Angle := TAU * Index / ConeSegments
		ConePoints.append(Vector3(cos(Angle) * Half, -Half, sin(Angle) * Half))
	var ConeShape := ConvexPolygonShape3D.new()
	ConeShape.points = ConePoints
	# Cylinder: standing on a flat end.
	var Can := CylinderMesh.new()
	Can.top_radius = Half
	Can.bottom_radius = Half
	Can.height = BlockSize
	var CanEdge := CylinderMesh.new()
	CanEdge.top_radius = Half * Edge
	CanEdge.bottom_radius = Half * Edge
	CanEdge.height = BlockSize * Edge
	var CanShape := CylinderShape3D.new()
	CanShape.radius = Half
	CanShape.height = BlockSize
	# Glow: the halo quad, a placeholder where the edge would be (it is hidden), and a ball-sized collider so
	# glowing pieces still bump into each other even though they look like nothing but light.
	var Halo := QuadMesh.new()
	Halo.size = Vector2.ONE * GlowHaloSize
	var NoEdge := QuadMesh.new()
	NoEdge.size = Vector2.ONE * 0.01
	CoreMesh = QuadMesh.new()
	CoreMesh.size = Vector2.ONE * GlowCoreSize
	# Rounded cube: a box with rounded edges, its black edge a slightly larger copy, and a collider hugging its shape.
	var Rounded := RoundedBoxMesh.Build(BlockSize, BlockSize * RoundedCubeRadius)
	var RoundedEdge := RoundedBoxMesh.Build(BlockSize * Edge, BlockSize * RoundedCubeRadius * Edge)
	var RoundedShape := Rounded.create_convex_shape(true, false)
	BodyMeshes = [Cube, Ball, Cone, Can, Halo, Rounded]
	OutlineMeshes = [CubeEdge, BallEdge, ConeEdge, CanEdge, NoEdge, RoundedEdge]
	ColliderShapes = [CubeBox, BallShape, ConeShape, CanShape, BallShape, RoundedShape]
