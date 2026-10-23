class_name Backgrounds
extends RefCounted
## The choices for what is behind the board. Gray is the plain color the game began with; the others are sky shaders
## (`Shaders/`) drawn in screen space, so they fill the window whichever way the camera looks.

enum Kinds { Gray, Sky, Night, StarFlight }

const Names: Array[String] = ["Gray", "Sky", "Night", "Star Flight"]
const ShaderPaths: Array[String] = ["", "res://Shaders/SkyBackground.gdshader", "res://Shaders/NightBackground.gdshader", "res://Shaders/StarFlightBackground.gdshader"]

## One Sky resource per kind other than Gray (Gray's slot is null), built when first wanted.
static var Skies: Array[Sky] = [null, null, null, null]
static var CurrentAspect: float = 1.78


## The Sky to draw for a kind; null for Gray.
static func SkyFor(Kind: int) -> Sky:
	if Kind <= Kinds.Gray or Kind >= ShaderPaths.size():
		return null
	if Skies[Kind] == null:
		var Material := ShaderMaterial.new()
		Material.shader = load(ShaderPaths[Kind])
		Material.set_shader_parameter("Aspect", CurrentAspect)
		var Result := Sky.new()
		Result.sky_material = Material
		Skies[Kind] = Result
	return Skies[Kind]


## Tells every sky shader the window's shape, so the clouds and stars are not stretched.
static func SetAspect(Aspect: float) -> void:
	CurrentAspect = Aspect
	for Item in Skies:
		if Item != null:
			(Item.sky_material as ShaderMaterial).set_shader_parameter("Aspect", Aspect)
