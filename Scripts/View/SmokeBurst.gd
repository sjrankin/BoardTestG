class_name SmokeBurst
extends MultiMeshInstance3D
## The "Puff of Smoke" removal effect (`BoardView.RemovalEffects.Smoke`): the pieces are gone at once and a few soft, grey puffs
## are left where each stood. The puffs swell, drift up and sideways, and thin out to nothing.
##
## One burst is one `MultiMesh` of camera-facing quads, however many pieces it covers, so clearing a big board costs one draw
## call. The puffs are moved by script, every frame, from a single progress value, so every one of them is exactly gone at `Life`
## seconds. The caller works `Life` out from `DissipationTime`.
##
## It lives in the world (a child of `FlyerSystem`, not of the board), so it does not turn with the board, and a new game
## (`FlyerSystem.Reset`) clears it.

## Puffs per piece for a small group, how many pieces still get that many, and the fewest a piece gets in a big group. The pieces of
## a big group are side by side, so their puffs overlap heavily: more of them would not show, they would only be more translucent
## quads to blend, and blending is what a burst costs. Every 6 pieces past `FullDensityPieces` takes one puff off each piece.
const PuffsPerPiece := 6
const FullDensityPieces := 6
const MinPuffsPerPiece := 3
## A puff's width at the start and at the end, in cells (each puff picks a size in the range).
const StartSize := Vector2(0.6, 0.9)
const EndSize := Vector2(1.5, 2.4)
## How far a puff climbs, in cells, and the most it drifts sideways (either way).
const Rise := Vector2(0.4, 1.2)
const Drift := 0.5
## A puff starts this far, at most, from the middle of its piece, along each axis (in cells).
const Scatter := 0.25
## The smoke is moved this far out of the piece's face (a block's face is 0.46 cells from its middle), so it starts in front of
## the neighbouring pieces and is not hidden behind them, and it billows out a further `Billow` (a range) as it spreads.
const FrontLift := 0.75
const Billow := Vector2(0.3, 0.8)
## How long the smoke takes to clear, in seconds at Removal Speed 1 (shorter when pieces are removed faster, as Explode's shards
## are). Explode's shards take about 1.7 s (`FlyerSystem.RestAge` + `FadeDuration`); the smoke is kept a little longer on purpose.
const DissipationTime := 1.9
## The share of its life a puff spends fading in, and the greatest opacity a puff reaches. (Quick to fill in and nearly solid at
## its fullest, so a puff hides the gap at the start and does not look like a faint smudge.)
const FadeInShare := 0.03
const Opacity := 0.95
## The least strength a puff has, against the others (the strongest is 1.0).
const MinStrength := 0.85
## The smoke is this grey, plus `TintShare` of the removed piece's own color, so it shows what was removed.
const Grey := Color(0.84, 0.85, 0.88)
const TintShare := 0.3
## How fast the soft edge of a puff falls off (the texture's radial gradient), and its size in pixels.
const TextureSize := 128

static var SharedMesh: QuadMesh
static var SoftTexture: Texture2D

## Seconds the burst lasts, and how long it has been going.
var Life: float = 1.0
var Age: float = 0.0
## One entry per puff: where it starts, how far it moves in all, its size at the start and at the end, and its color (the
## alpha holds how strong this puff is, from `MinStrength` to 1, against the others).
var Starts := PackedVector3Array()
var Paths := PackedVector3Array()
var StartSizes := PackedFloat32Array()
var EndSizes := PackedFloat32Array()
var Tints := PackedColorArray()


## Takes `Pieces` off the board in a puff of smoke: each entry is {"Node": the piece's node, "Kind": its color index, "Out": a unit
## vector, in world space, for the way out of the face to bloom (optional)}. Each node is freed at once, and the puffs are added to
## `Parent` (a world-space node). The smoke lasts `DissipationTime`, shortened as `RemovalSpeed` goes up. `Up` is the way it rises:
## exactly against the way pieces fall on that board (a unit vector in world space).
static func Replace(Parent: Node3D, Pieces: Array[Dictionary], Palette: Array[Color], RemovalSpeed: float, Up: Vector3 = Vector3.UP) -> void:
	var Where := PackedVector3Array()
	var Colors := PackedColorArray()
	var Outs := PackedVector3Array()
	for Entry in Pieces:
		var Node: Node3D = Entry["Node"]
		if not is_instance_valid(Node):
			continue
		Where.append(Node.global_position)
		Colors.append(Palette[Entry["Kind"]])
		Outs.append(Entry.get("Out", Vector3.ZERO))
		Node.queue_free()
	Play(Parent, Where, Colors, DissipationTime / maxf(RemovalSpeed, 0.1), Outs, Up)


## Starts a burst of smoke over `Where` (world positions), tinted by `Colors` (one per position), lasting `LifeSeconds`. `Outs`
## (one per position, or empty) is the unit vector each puff set blooms along, out of its piece's face. `Up` is the unit vector the
## smoke rises along.
static func Play(Parent: Node3D, Where: PackedVector3Array, Colors: PackedColorArray, LifeSeconds: float, Outs: PackedVector3Array = PackedVector3Array(), Up: Vector3 = Vector3.UP) -> SmokeBurst:
	if Where.is_empty():
		return null
	var Burst := SmokeBurst.new()
	Burst.Build(Where, Colors, LifeSeconds, Outs, Up)
	Parent.add_child(Burst)
	return Burst


## How many puffs each piece of a group of `Pieces` gets: `PuffsPerPiece` for a small group, fewer for a big one.
static func PuffsFor(Pieces: int) -> int:
	return clampi(PuffsPerPiece - maxi(Pieces - FullDensityPieces, 0) / 6, MinPuffsPerPiece, PuffsPerPiece)


## Works out every puff, makes the mesh to draw them, and draws the first frame.
func Build(Where: PackedVector3Array, Colors: PackedColorArray, LifeSeconds: float, Outs: PackedVector3Array = PackedVector3Array(), UpVector: Vector3 = Vector3.UP) -> void:
	Life = maxf(LifeSeconds, 0.05)
	# The smoke rises along `Rising` and drifts sideways across the plane at right angles to it.
	var Rising := UpVector.normalized() if UpVector.length() > 0.001 else Vector3.UP
	var Across := Rising.cross(Vector3.FORWARD if absf(Rising.dot(Vector3.FORWARD)) < 0.9 else Vector3.RIGHT).normalized()
	var Along := Rising.cross(Across)
	var Puffs := PuffsFor(Where.size())
	for Index in Where.size():
		var Base := Grey.lerp(Colors[Index], TintShare)
		var Out := Outs[Index] if Index < Outs.size() else Vector3.ZERO
		for Puff in Puffs:
			Starts.append(Where[Index] + Out * FrontLift + Vector3(randf_range(-Scatter, Scatter), randf_range(-Scatter, Scatter), randf_range(-Scatter, Scatter)))
			# Drifts sideways across the face, never back into it (what is left of the sideways drift once the way out is taken off), and
			# never along the way up, which is left to the rise alone.
			var Sideways := Across * randf_range(-Drift, Drift) + Along * randf_range(-Drift, Drift)
			Sideways -= Out * Sideways.dot(Out)
			Sideways -= Rising * Sideways.dot(Rising)
			Paths.append(Sideways + Rising * randf_range(Rise.x, Rise.y) + Out * randf_range(Billow.x, Billow.y))
			StartSizes.append(randf_range(StartSize.x, StartSize.y))
			EndSizes.append(randf_range(EndSize.x, EndSize.y))
			# A little lighter or darker, so puffs that overlap read as billows and not as one flat patch.
			var Shade := randf_range(0.88, 1.08)
			Tints.append(Color(minf(Base.r * Shade, 1.0), minf(Base.g * Shade, 1.0), minf(Base.b * Shade, 1.0), randf_range(MinStrength, 1.0)))
	var Instances := MultiMesh.new()
	Instances.transform_format = MultiMesh.TRANSFORM_3D
	Instances.use_colors = true
	Instances.mesh = PuffMesh()
	Instances.instance_count = Starts.size()
	multimesh = Instances
	# The puffs move every frame, so give the burst a bounding box that always holds them.
	custom_aabb = AABB(Vector3.ONE * -500.0, Vector3.ONE * 1000.0)
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	Advance(0.0)


func _process(Delta: float) -> void:
	Advance(Delta)


## Moves time on by `Delta` seconds and places every puff for the new time. The burst frees itself once `Life` has passed.
func Advance(Delta: float) -> void:
	Age += Delta
	var Progress := clampf(Age / Life, 0.0, 1.0)
	var Strength := OpacityAt(Progress)
	for Index in Starts.size():
		multimesh.set_instance_transform(Index, PuffAt(Index, Progress))
		var Tint := Tints[Index]
		multimesh.set_instance_color(Index, Color(Tint.r, Tint.g, Tint.b, Tint.a * Strength))
	if Progress >= 1.0:
		queue_free()


## How opaque the smoke is `Progress` of the way through its life (0 to 1): it fades in over the first moments, so the puffs do not
## pop, then thins out smoothly to nothing at 1.
static func OpacityAt(Progress: float) -> float:
	return clampf(Progress / FadeInShare, 0.0, 1.0) * pow(1.0 - clampf(Progress, 0.0, 1.0), 1.5) * Opacity


## How far a puff has swelled and risen `Progress` of the way through the life of the smoke: quick at first, then settling, like
## smoke that spreads and slows. 0 at the start, 1 at the end.
static func SpreadAt(Progress: float) -> float:
	var Left := 1.0 - clampf(Progress, 0.0, 1.0)
	return 1.0 - Left * Left


## Where puff `Index` is, and how big, `Progress` of the way through the life of the smoke.
func PuffAt(Index: int, Progress: float) -> Transform3D:
	var Spread := SpreadAt(Progress)
	var Width := lerpf(StartSizes[Index], EndSizes[Index], Spread)
	return Transform3D(Basis.from_scale(Vector3.ONE * Width), Starts[Index] + Paths[Index] * Spread)


## The quad every puff is an instance of, with the smoke material. Made once.
static func PuffMesh() -> QuadMesh:
	if SharedMesh != null:
		return SharedMesh
	var Material := StandardMaterial3D.new()
	Material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	Material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	# Always facing the camera, and still scaled by each puff's own size.
	Material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	Material.billboard_keep_scale = true
	Material.vertex_color_use_as_albedo = true
	Material.albedo_texture = SoftBlob()
	Material.cull_mode = BaseMaterial3D.CULL_DISABLED
	SharedMesh = QuadMesh.new()
	SharedMesh.size = Vector2.ONE
	SharedMesh.material = Material
	return SharedMesh


## A white disc whose opacity falls smoothly from the middle to nothing at the edge: a soft puff, not a hard circle.
static func SoftBlob() -> Texture2D:
	if SoftTexture != null:
		return SoftTexture
	var Fade := Gradient.new()
	Fade.offsets = PackedFloat32Array([0.0, 0.5, 1.0])
	Fade.colors = PackedColorArray([Color(1, 1, 1, 1), Color(1, 1, 1, 0.8), Color(1, 1, 1, 0)])
	var Blob := GradientTexture2D.new()
	Blob.gradient = Fade
	Blob.fill = GradientTexture2D.FILL_RADIAL
	Blob.fill_from = Vector2(0.5, 0.5)
	Blob.fill_to = Vector2(1.0, 0.5)
	Blob.width = TextureSize
	Blob.height = TextureSize
	SoftTexture = Blob
	return SoftTexture
