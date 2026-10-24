class_name SceneSetup
extends RefCounted
## Builds the fixed parts of the 3D scene: the sky, the light, the camera and the checkerboard floor.

const SkyColor := Color(0.42, 0.42, 0.44)
const FloorSize := 80.0
const FloorTiles := 40.0

## The environment and the sun, kept so Specular can change how they light the pieces.
static var SceneEnvironment: Environment
static var Sun: DirectionalLight3D
## The sun's own turn in degrees (pitch, yaw, roll); the Malicious spinning light adds to its yaw.
const SunDirection := Vector3(-40, 25, 0)
static var ReflectionSky: Sky
static var BackgroundKind: int = Backgrounds.Kinds.Gray
static var SpecularOn: bool = false
static var Ground: MeshInstance3D
static var FloorMaterial: StandardMaterial3D
static var SolidChecker: ImageTexture
static var ClearChecker: ImageTexture


## The sky, the sun (with shadows), and the camera. Returns the camera.
static func BuildEnvironment(Parent: Node) -> Camera3D:
	var Sky := Environment.new()
	Sky.background_mode = Environment.BG_COLOR
	Sky.background_color = SkyColor
	Sky.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	Sky.ambient_light_color = Color(0.75, 0.75, 0.8)
	Sky.ambient_light_energy = 0.55
	# Bloom, only for things brighter than the lit scene itself (the lightning's core).
	Sky.glow_enabled = true
	Sky.glow_intensity = 0.9
	Sky.glow_hdr_threshold = 1.2
	Sky.glow_bloom = 0.1
	SceneEnvironment = Sky
	var WorldEnv := WorldEnvironment.new()
	WorldEnv.environment = Sky
	Parent.add_child(WorldEnv)
	ReflectionSky = MakeReflectionSky()
	Sun = DirectionalLight3D.new()
	Sun.rotation_degrees = SunDirection
	Sun.light_energy = 1.1
	Sun.shadow_enabled = true
	Parent.add_child(Sun)
	var CameraNode := Camera3D.new()
	CameraNode.fov = 45.0
	Parent.add_child(CameraNode)
	return CameraNode


## What glossy pieces reflect: a soft sky, bright above and darker below. It is only used when Specular is on, and is
## never drawn as the background (that stays the plain color).
static func MakeReflectionSky() -> Sky:
	var Material := ProceduralSkyMaterial.new()
	Material.sky_top_color = Color(0.45, 0.6, 0.9)
	Material.sky_horizon_color = Color(0.9, 0.9, 0.95)
	Material.ground_horizon_color = Color(0.5, 0.5, 0.55)
	Material.ground_bottom_color = Color(0.12, 0.12, 0.15)
	var Result := Sky.new()
	Result.sky_material = Material
	return Result


## Specular lighting: with it on, the sun's highlight is stronger and the sky is reflected in glossy surfaces.
static func SetSpecular(On: bool) -> void:
	SpecularOn = On
	Sun.light_specular = 2.0 if On else 1.0
	ApplySky()


## What is behind the board: Gray is the plain color, the others a drawn sky. The checkerboard floor stays for all of them.
static func SetBackground(Kind: int) -> void:
	BackgroundKind = Kind
	ApplySky()


## Works out the background and the reflections from the background kind and Specular together: a drawn sky is both
## what is behind the board and what glossy pieces reflect; with Gray, they reflect the soft reflection sky.
static func ApplySky() -> void:
	if FloorMaterial != null:
		SetFloorClear(BackgroundKind == Backgrounds.Kinds.Sky)
	var Drawn := Backgrounds.SkyFor(BackgroundKind)
	if Drawn == null:
		SceneEnvironment.background_mode = Environment.BG_COLOR
		SceneEnvironment.sky = ReflectionSky if SpecularOn else null
	else:
		SceneEnvironment.background_mode = Environment.BG_SKY
		SceneEnvironment.sky = Drawn
	SceneEnvironment.reflected_light_source = Environment.REFLECTION_SOURCE_SKY if SpecularOn else Environment.REFLECTION_SOURCE_DISABLED


## The floor's checkerboard: the gray squares and the darker ones. With `ClearGray` the gray squares are see-through (Sky).
static func MakeChecker(ClearGray: bool) -> ImageTexture:
	var Checker := Image.create(2, 2, false, Image.FORMAT_RGBA8)
	var Gray := Color(0.16, 0.16, 0.17, 0.0 if ClearGray else 1.0)
	var Dark := Color(0.05, 0.05, 0.06)
	Checker.set_pixel(0, 0, Gray)
	Checker.set_pixel(1, 1, Gray)
	Checker.set_pixel(1, 0, Dark)
	Checker.set_pixel(0, 1, Dark)
	return ImageTexture.create_from_image(Checker)


## Under the Sky the floor's gray squares are see-through (the sky shows through them); otherwise they are solid gray.
static func SetFloorClear(Clear: bool) -> void:
	if SolidChecker == null:
		SolidChecker = MakeChecker(false)
		ClearChecker = MakeChecker(true)
	FloorMaterial.albedo_texture = ClearChecker if Clear else SolidChecker
	FloorMaterial.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA if Clear else BaseMaterial3D.TRANSPARENCY_DISABLED


## A dark checkerboard with a solid slab under it, its top at y = 0, for the removed pieces to land on.
static func BuildFloor(Parent: Node) -> void:
	FloorMaterial = StandardMaterial3D.new()
	FloorMaterial.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS
	FloorMaterial.uv1_scale = Vector3(FloorTiles, FloorTiles, 1)
	FloorMaterial.roughness = 0.9
	var Material := FloorMaterial
	SetFloorClear(BackgroundKind == Backgrounds.Kinds.Sky)
	var Plane := PlaneMesh.new()
	Plane.size = Vector2(FloorSize, FloorSize)
	Ground = MeshInstance3D.new()
	Ground.mesh = Plane
	Ground.material_override = Material
	Parent.add_child(Ground)
	var Body := StaticBody3D.new()
	Body.collision_layer = PhysicsLayers.Floor
	var Shape := CollisionShape3D.new()
	var Slab := BoxShape3D.new()
	Slab.size = Vector3(FloorSize, 1, FloorSize)
	Shape.shape = Slab
	Shape.position = Vector3(0, -0.5, 0)
	Body.add_child(Shape)
	var Physical := PhysicsMaterial.new()
	Physical.friction = 0.9
	Physical.bounce = 0.15
	Body.physics_material_override = Physical
	Parent.add_child(Body)
