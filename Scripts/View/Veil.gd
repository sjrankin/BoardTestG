class_name Veil
extends RefCounted
## The Malicious veil (Settings > Malicious): a layer of flat dark tiles in front of every piece of one color, hiding it. A tile is a
## child of its piece (so it falls and is removed with it) that pops in, and shrinks away when the veil lifts. On the 2D board a tile
## is a thin plate in front of the piece's face; on the cube, which has pieces facing every way, it is a box that wraps the piece.

const PlateColor := Color(0.17, 0.18, 0.23)
## How long a tile takes to pop in or shrink away, in seconds.
const AnimationTime := 0.5
## A plate stands this far in front of the piece's face (cells); a wrapping box is this much bigger than the piece.
const PlateGap := 0.08
const WrapScale := 1.12

static var TileMaterial: StandardMaterial3D


static func MakeTile(Flat: bool) -> MeshInstance3D:
	if TileMaterial == null:
		TileMaterial = StandardMaterial3D.new()
		TileMaterial.albedo_color = PlateColor
		TileMaterial.roughness = 0.85
	var Size := BlockStyles.BlockSize
	var Tile := MeshInstance3D.new()
	Tile.name = "Veil"
	var Box := BoxMesh.new()
	if Flat:
		Box.size = Vector3(Size, Size, 0.06)
		Tile.position = Vector3(0, 0, Size / 2.0 + PlateGap)
	else:
		Box.size = Vector3.ONE * Size * WrapScale
	Tile.mesh = Box
	Tile.material_override = TileMaterial
	Tile.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return Tile


## Puts a tile over `Node` (a piece). `Animate` makes it pop in; without it the tile is simply there (a piece that arrives while the
## veil is down).
static func Cover(Node: Node3D, Flat: bool, Animate: bool) -> void:
	if Node.has_node("Veil"):
		return
	var Tile := MakeTile(Flat)
	Node.add_child(Tile)
	if Animate:
		Tile.scale = Vector3.ZERO
		Tile.create_tween().tween_property(Tile, "scale", Vector3.ONE, AnimationTime).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


## Takes the tile off `Node`: it shrinks away and is freed.
static func Uncover(Node: Node3D) -> void:
	var Tile := Node.get_node_or_null("Veil") as MeshInstance3D
	if Tile == null:
		return
	Tile.name = "VeilLeaving"
	var Shrink := Tile.create_tween()
	Shrink.tween_property(Tile, "scale", Vector3.ZERO, AnimationTime).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	Shrink.tween_callback(Tile.queue_free)
