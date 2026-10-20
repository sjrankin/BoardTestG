class_name JoinSystem
extends RefCounted
## The "joined" shapes, from BoardTestRK: pieces of the same colour that touch along a side are joined into one shape.
##
## - Joined Cubes: a cube grows to meet its joined neighbour on that side - its own mesh is extended out to the cell's edge, so the
##   two surfaces run together with no gap or edge line between them, and a group reads as one solid block.
## - Joined Spheres: a cylinder bridges the gap between two joined spheres (a little narrower than a sphere, so the two
##   surfaces never lie in the same plane), with the same black edge as the spheres.
## - Joined Cylinders (new here): vertically, a cylinder column fills the gap; sideways, a flat slab as deep as a drum is
##   round, so a joined row reads as one long drum.
##
## The same rules as BoardTestRK: a join exists only between two same-coloured pieces that are next to each other right now and
## that are both at rest. A piece that is moving (falling, refilling, shuffling) has none, and neither does anything beside it
## that was joined to it; they come back when it lands. A piece that is taken off the board loses its joins at once. (The cross-edge
## cases of the 3D cube do not exist on the 2D board.)

const Pitch := BlockStyles.Pitch
const BlockSize := BlockStyles.BlockSize
## A bridge's width as a fraction of a piece's: a hair narrower, so its surface never coincides with a sphere's or cylinder's.
const BridgeFraction := 0.99
## How much bigger than its bridge the black edge shell round the bridge is, as for the pieces themselves.
const EdgeScale := BlockStyles.OutlineScale

var Model: BoardModel
var Styles: BlockStyles
var PieceNodes: Dictionary
## Cube meshes by neighbour mask (bit 1 east, 2 west, 4 up, 8 down): [body mesh, edge mesh].
var CubeMeshes: Dictionary = {}
var BridgeMeshes: Dictionary = {}


## Brings every piece's joins up to date with the board: `Moving` holds the ids of pieces that are not at rest. Cheap enough
## to call after any change.
func Update(Moving: Dictionary) -> void:
	var Shape := Styles.CurrentShape
	var Joined := Styles.IsJoined()
	for Col in Model.Width:
		for Row in Model.Height:
			var Piece := Model.GetPiece(Col, Row)
			if Piece == null or not PieceNodes.has(Piece.Id):
				continue
			var Node: Node3D = PieceNodes[Piece.Id]
			var Mask := 0
			if Joined and not Moving.has(Piece.Id):
				Mask = NeighbourMask(Piece, Col, Row, Moving)
			match Shape:
				BlockStyles.Shapes.JoinedCubes:
					ApplyCubeMask(Node, Mask)
					RemoveBridges(Node)
				BlockStyles.Shapes.JoinedSpheres, BlockStyles.Shapes.JoinedCylinders:
					ApplyBridges(Node, Piece.Kind, Mask, Shape)
				_:
					RemoveBridges(Node)


## A piece taken off the board (or about to fly): plain again, with no joins.
func Strip(Node: Node3D) -> void:
	RemoveBridges(Node)
	if Styles.CurrentShape == BlockStyles.Shapes.JoinedCubes:
		ApplyCubeMask(Node, 0)


## Which sides of the piece at (Col, Row) have a joined neighbour: same colour, present, and not moving.
func NeighbourMask(Piece: BoardModel.PieceData, Col: int, Row: int, Moving: Dictionary) -> int:
	var Mask := 0
	var Sides := [[1, 0, 1], [-1, 0, 2], [0, -1, 4], [0, 1, 8]]
	for Side in Sides:
		var Other := Model.GetPiece(Col + Side[0], Row + Side[1])
		if Other != null and Other.Kind == Piece.Kind and PieceNodes.has(Other.Id) and not Moving.has(Other.Id):
			Mask |= Side[2]
	return Mask


# MARK: Joined Cubes

func ApplyCubeMask(Node: Node3D, Mask: int) -> void:
	if not CubeMeshes.has(Mask):
		CubeMeshes[Mask] = [MakeCubeMesh(Mask, 0.0), MakeCubeMesh(Mask, BlockSize * (EdgeScale - 1.0))]
	var Meshes: Array = CubeMeshes[Mask]
	(Node.get_child(0) as MeshInstance3D).mesh = Meshes[0]
	(Node.get_child(1) as MeshInstance3D).mesh = Meshes[1]


## A box that is `BlockSize` deep and as wide and tall as a piece, but reaching out to the cell's edge (half a pitch from
## the middle) on every joined side. `Grow` makes it that much bigger on every side but the joined ones (the edge shell).
func MakeCubeMesh(Mask: int, Grow: float) -> ArrayMesh:
	var Half := BlockSize / 2.0 + Grow / 2.0
	var Reach := Pitch / 2.0
	var East := Reach if Mask & 1 else Half
	var West := Reach if Mask & 2 else Half
	var Up := Reach if Mask & 4 else Half
	var Down := Reach if Mask & 8 else Half
	var Depth := BlockSize / 2.0 + Grow / 2.0
	return BoxBetween(Vector3(-West, -Down, -Depth), Vector3(East, Up, Depth))


## A box with the given opposite corners (Godot's own box mesh can only be centred on its origin), with flat normals and each
## face mapped across the whole 0..1 square.
func BoxBetween(Low: Vector3, High: Vector3) -> ArrayMesh:
	var Tool := SurfaceTool.new()
	Tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	var Faces := [
		[Vector3.RIGHT, Vector3.UP, Vector3.BACK],
		[Vector3.LEFT, Vector3.UP, Vector3.FORWARD],
		[Vector3.UP, Vector3.BACK, Vector3.RIGHT],
		[Vector3.DOWN, Vector3.RIGHT, Vector3.BACK],
		[Vector3.BACK, Vector3.UP, Vector3.LEFT],
		[Vector3.FORWARD, Vector3.UP, Vector3.RIGHT],
	]
	var Centre := (Low + High) / 2.0
	var Half := (High - Low) / 2.0
	for Face in Faces:
		var Normal: Vector3 = Face[0]
		var AxisU: Vector3 = Face[1]
		var AxisV: Vector3 = Face[2]
		var Corners := [[-1, -1], [1, -1], [1, 1], [-1, 1]]
		var Points: Array[Vector3] = []
		for Corner in Corners:
			Points.append(Centre + Normal * Half + AxisU * Half * Corner[0] + AxisV * Half * Corner[1])
		var UVs: Array[Vector2] = [Vector2(0, 1), Vector2(1, 1), Vector2(1, 0), Vector2(0, 0)]
		# Godot draws the clockwise side of a triangle: order so the winding's cross product points inward.
		for Triangle in [[0, 1, 2], [0, 2, 3]]:
			var Indices: Array[int] = [Triangle[0], Triangle[1], Triangle[2]]
			var A: Vector3 = Points[Indices[0]]
			var B: Vector3 = Points[Indices[1]]
			var C: Vector3 = Points[Indices[2]]
			if (B - A).cross(C - A).dot(Normal) > 0.0:
				Indices = [Triangle[0], Triangle[2], Triangle[1]]
			for Index in Indices:
				Tool.set_normal(Normal)
				Tool.set_uv(UVs[Index])
				Tool.add_vertex(Points[Index])
	return Tool.commit()


# MARK: Joined Spheres and Joined Cylinders

## Adds a bridge to each joined side that the piece "owns" (east and down - the other side's piece owns the matching bridge),
## and removes the rest.
func ApplyBridges(Node: Node3D, Kind: int, Mask: int, Shape: int) -> void:
	SetBridge(Node, "JoinEast", Kind, Mask & 1 != 0, Shape, true)
	SetBridge(Node, "JoinDown", Kind, Mask & 8 != 0, Shape, false)


func SetBridge(Node: Node3D, Name: String, Kind: int, Wanted: bool, Shape: int, Horizontal: bool) -> void:
	var Existing := Node.get_node_or_null(Name) as MeshInstance3D
	if not Wanted:
		if Existing != null:
			Existing.queue_free()
			Existing.name = Name + "Gone"
		return
	if Existing != null:
		Existing.material_override = Styles.Materials[Kind]
		return
	var Bridge := MeshInstance3D.new()
	Bridge.name = Name
	Bridge.mesh = BridgeMesh(Shape, Horizontal, 1.0)
	Bridge.material_override = Styles.Materials[Kind]
	# Horizontal: centred half a pitch east; vertical: half a pitch down - the middle of the gap.
	Bridge.position = Vector3(Pitch / 2.0, 0, 0) if Horizontal else Vector3(0, -Pitch / 2.0, 0)
	if Shape == BlockStyles.Shapes.JoinedSpheres and Horizontal:
		Bridge.rotation_degrees = Vector3(0, 0, 90)
	var Shell := MeshInstance3D.new()
	Shell.name = "Edge"
	Shell.mesh = BridgeMesh(Shape, Horizontal, EdgeScale)
	Shell.material_override = Styles.OutlineMaterial
	Bridge.add_child(Shell)
	Node.add_child(Bridge)


func RemoveBridges(Node: Node3D) -> void:
	for Name in ["JoinEast", "JoinDown"]:
		var Existing := Node.get_node_or_null(Name)
		if Existing != null:
			Existing.queue_free()
			Existing.name = Name + "Gone"


## The mesh of a bridge: a cylinder (along its own up-axis, turned for a sideways one) for spheres and for a cylinder column; a
## slab for a sideways bridge between cylinders. `Scale` is 1 for the bridge itself, the edge scale for its black shell.
func BridgeMesh(Shape: int, Horizontal: bool, Scale: float) -> Mesh:
	var Key := [Shape, Horizontal, Scale]
	if BridgeMeshes.has(Key):
		return BridgeMeshes[Key]
	var Width := BlockSize * BridgeFraction * Scale
	var Result: Mesh
	if Shape == BlockStyles.Shapes.JoinedCylinders and Horizontal:
		var Slab := BoxMesh.new()
		Slab.size = Vector3(Pitch + (Scale - 1.0) * 0.0, Width, Width)
		Result = Slab
	else:
		var Rod := CylinderMesh.new()
		Rod.top_radius = Width / 2.0
		Rod.bottom_radius = Width / 2.0
		Rod.height = Pitch
		Result = Rod
	BridgeMeshes[Key] = Result
	return Result
