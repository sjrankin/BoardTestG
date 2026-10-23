class_name IdleHint
extends RefCounted
## The idle hint, as in BoardTestRK (`CubeCoordinator+IdleHint.swift`): after `Delay` seconds with no player input - and not
## in Attract Mode, and not while the board is busy (a drop or shuffle in progress) - the largest playable group is painted
## with a black-and-white checkerboard, 5 squares to a side on each piece, with no lighting, so it can't be mistaken for a
## colour. The group with the most pieces wins; among equals, the one lowest on the board. Any input clears it, and the clock
## starts again. Other input (dragging to turn the board, zooming, the buttons) restarts the clock before a hint appears, but
## does not remove one that is already showing: a hint stays until a piece on the board itself is tapped.

## How long the player can go without touching the board before a hint appears (seconds) - the same as BoardTestRK.
const Delay := 20.0
## Squares along each side of a hinted piece, and the bitmap's pixels per square (only how crisp the square edges look up close).
const SquaresPerSide := 5
const PixelsPerSquare := 24
## A sphere's hint is black and white stripes from pole to pole (lines of longitude), this many in all, alternating, and the
## sphere turns slowly about the board's up-down axis while the hint shows.
const SphereStripes := 32
## A cylinder's hint: the same number of vertical stripes round it, and this many concentric rings on its top and bottom.
const DrumRings := 6
## Squares along each edge of a cube (even, so they line up with its edges), and of the 3D checkerboard on a cone or cylinder.
const CubeSquares := 8
## How fast hinted spheres turn about the board's up-down axis (radians per second), so their stripes visibly spin.
const SphereSpinRate := 1.0

var Model: BoardModel
var Styles: BlockStyles
var PieceNodes: Dictionary
## Seconds since the last input.
var IdleTime: float = 0.0
var HintedIds: Array = []
## The colors the goal still needs (set by `Main`): the hint is for the largest group of one of them. Empty: any color.
var WantedKinds: Array[int] = []
var CheckerTexture: ImageTexture
## One hint material per shape (see `MaterialFor`).
var HintMaterials: Dictionary = {}


func _init() -> void:
	CheckerTexture = MakeCheckerboard()


## The hint's material for `Shape`. Rounded cubes use the flat checkerboard picture on each face (a plain cube's box mesh lays its six
## faces out in one shared picture, so the picture there comes out several times too large - cubes use the 3D checkerboard). A sphere has no
## flat face to put a picture on - wrapped round it, the picture bunches up at the poles and stretches elsewhere - so it gets
## black and white longitude stripes instead (`HintStripes.gdshader`), and a cylinder gets the same stripes with rings on its ends
## (`HintCylinder.gdshader`). A cone or cube is checkered in 3D
## (`HintChecker.gdshader`): the surface is coloured by which cell of a grid of cubes (`SquaresPerSide` across the piece) each
## point is in, so the squares are the same size everywhere.
func MaterialFor(Shape: int) -> Material:
	# A joined shape is hinted like the plain shape it looks like.
	match Shape:
		BlockStyles.Shapes.JoinedCubes:
			Shape = BlockStyles.Shapes.Cube
		BlockStyles.Shapes.JoinedSpheres:
			Shape = BlockStyles.Shapes.Sphere
		BlockStyles.Shapes.JoinedCylinders:
			Shape = BlockStyles.Shapes.Cylinder
	if HintMaterials.has(Shape):
		return HintMaterials[Shape]
	var Result: Material
	if Shape == BlockStyles.Shapes.Sphere:
		var Stripes := ShaderMaterial.new()
		Stripes.shader = load("res://Scripts/View/HintStripes.gdshader")
		Stripes.set_shader_parameter("Count", SphereStripes)
		Result = Stripes
	elif Shape == BlockStyles.Shapes.Cylinder:
		var Drum := ShaderMaterial.new()
		Drum.shader = load("res://Scripts/View/HintCylinder.gdshader")
		Drum.set_shader_parameter("Count", SphereStripes)
		Drum.set_shader_parameter("RingWidth", BlockStyles.BlockSize / 2.0 / DrumRings)
		Result = Drum
	elif Shape == BlockStyles.Shapes.Cone or Shape == BlockStyles.Shapes.Cube:
		var Surface := ShaderMaterial.new()
		Surface.shader = load("res://Scripts/View/HintChecker.gdshader")
		# An even number of cells across (a cube's edges then fall exactly on cell edges, so each face is a whole checkerboard).
		Surface.set_shader_parameter("CellSize", BlockStyles.BlockSize / CubeSquares)
		Result = Surface
	else:
		var Flat := StandardMaterial3D.new()
		Flat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		Flat.albedo_texture = CheckerTexture
		Flat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS
		Flat.cull_mode = BaseMaterial3D.CULL_DISABLED
		Result = Flat
	HintMaterials[Shape] = Result
	return Result


## Draws every hint material on a speck of every shape, out of sight behind the board, so Godot compiles their shaders now. Left
## until the hint first appears, the compile freezes the whole view for a moment just as the hint shows. `Board` is the node
## the specks are added to; call this again after anything frees them (a new game).
func WarmUp(Board: Node3D, BehindBoard: Vector3) -> void:
	for Shape in BlockStyles.Shapes.values():
		var Speck := MeshInstance3D.new()
		Speck.mesh = Styles.BodyMeshes[Shape]
		Speck.material_override = MaterialFor(Shape)
		Speck.position = BehindBoard
		Speck.scale = Vector3.ONE * 0.002
		Speck.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		Board.add_child(Speck)


## A black-and-white `SquaresPerSide`-square checkerboard, white in the top-left corner.
static func MakeCheckerboard() -> ImageTexture:
	var Side := SquaresPerSide * PixelsPerSquare
	var Picture := Image.create(Side, Side, false, Image.FORMAT_RGB8)
	for Row in SquaresPerSide:
		for Column in SquaresPerSide:
			var Shade := Color.WHITE if (Row + Column) % 2 == 0 else Color.BLACK
			Picture.fill_rect(Rect2i(Column * PixelsPerSquare, Row * PixelsPerSquare, PixelsPerSquare, PixelsPerSquare), Shade)
	return ImageTexture.create_from_image(Picture)


func IsShowing() -> bool:
	return not HintedIds.is_empty()


## The player did something: restart the idle clock, so a hint is not about to appear. A hint that is already showing stays.
func RecordActivity() -> void:
	IdleTime = 0.0


## A piece on the board was tapped: that is what takes a showing hint away. Restarts the idle clock too.
func Dismiss() -> void:
	IdleTime = 0.0
	Clear()


## Advances the idle clock. `Allowed` is false while something (Attract Mode, a drop, a shuffle) makes a hint pointless.
func Tick(Delta: float, Allowed: bool) -> void:
	SpinHinted(Delta)
	if not Allowed:
		IdleTime = 0.0
		Clear()
		return
	if IsShowing():
		return
	IdleTime += Delta
	if IdleTime >= Delay:
		Show()


func Show() -> void:
	if Styles.IsGlow():
		return
	var Group := Model.LargestGroup(WantedKinds)
	if Group.is_empty():
		return
	for Cell in Group:
		var Piece := Model.GetPiece(Cell.x, Cell.y)
		var Node: Node3D = PieceNodes.get(Piece.Id) if Piece != null else null
		if Node == null:
			continue
		var Pattern := MaterialFor(Styles.CurrentShape)
		(Node.get_child(0) as MeshInstance3D).material_override = Pattern
		# A joined group's bridges get the pattern too, so the whole group reads as one.
		for BridgeName in ["JoinEast", "JoinDown"]:
			var Bridge := Node.get_node_or_null(BridgeName) as MeshInstance3D
			if Bridge != null:
				Bridge.material_override = Pattern
		HintedIds.append(Piece.Id)


## Turns every hinted sphere about its own vertical axis - the board's up-down axis (a piece's own axes are the board's), so the
## stripes spin. Other shapes keep still.
func SpinHinted(Delta: float) -> void:
	# Spheres and plain cylinders spin; a joined shape would swing its joins out of place.
	if Styles.CurrentShape != BlockStyles.Shapes.Sphere and Styles.CurrentShape != BlockStyles.Shapes.Cylinder:
		return
	for Id in HintedIds:
		var Node: Node3D = PieceNodes.get(Id)
		if Node != null and is_instance_valid(Node):
			Node.rotate_object_local(Vector3.UP, SphereSpinRate * Delta)


## Puts every hinted piece's own look back, and stops and undoes its spin.
func Clear() -> void:
	for Id in HintedIds:
		var Node: Node3D = PieceNodes.get(Id)
		if Node != null and is_instance_valid(Node):
			var Kind: int = Node.get_meta("Kind")
			(Node.get_child(0) as MeshInstance3D).material_override = Styles.Materials[Kind]
			for BridgeName in ["JoinEast", "JoinDown"]:
				var Bridge := Node.get_node_or_null(BridgeName) as MeshInstance3D
				if Bridge != null:
					Bridge.material_override = Styles.Materials[Kind]
			Node.basis = Basis.IDENTITY
	HintedIds.clear()
