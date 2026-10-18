class_name SceneSetup
extends RefCounted
## Builds the fixed parts of the 3D scene: the sky, the light, the camera and the checkerboard floor.

const SkyColor := Color(0.42, 0.42, 0.44)
const FloorSize := 80.0
const FloorTiles := 40.0


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
	var WorldEnv := WorldEnvironment.new()
	WorldEnv.environment = Sky
	Parent.add_child(WorldEnv)
	var Sun := DirectionalLight3D.new()
	Sun.rotation_degrees = Vector3(-40, 25, 0)
	Sun.light_energy = 1.1
	Sun.shadow_enabled = true
	Parent.add_child(Sun)
	var CameraNode := Camera3D.new()
	CameraNode.fov = 45.0
	Parent.add_child(CameraNode)
	return CameraNode


## A dark checkerboard with a solid slab under it, its top at y = 0, for the removed pieces to land on.
static func BuildFloor(Parent: Node) -> void:
	var Checker := Image.create(2, 2, false, Image.FORMAT_RGB8)
	Checker.set_pixel(0, 0, Color(0.16, 0.16, 0.17))
	Checker.set_pixel(1, 1, Color(0.16, 0.16, 0.17))
	Checker.set_pixel(1, 0, Color(0.05, 0.05, 0.06))
	Checker.set_pixel(0, 1, Color(0.05, 0.05, 0.06))
	var Material := StandardMaterial3D.new()
	Material.albedo_texture = ImageTexture.create_from_image(Checker)
	Material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS
	Material.uv1_scale = Vector3(FloorTiles, FloorTiles, 1)
	Material.roughness = 0.9
	var Plane := PlaneMesh.new()
	Plane.size = Vector2(FloorSize, FloorSize)
	var Ground := MeshInstance3D.new()
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
