class_name JoinSystem
extends RefCounted
## The "joined" shapes, from BoardTestRK: pieces of the same colour that touch along a side are joined into one shape.
##
## - Joined Cubes: a cube grows to meet its joined neighbour on that side - its own mesh is extended out to the cell's edge, so the
##   two surfaces run together with no gap or edge line between them, and a group reads as one solid block.
## - Joined Spheres: a cylinder bridges the gap between two joined spheres (a little narrower than a sphere, so the two
##   surfaces never lie in the same plane), with the same black edge as the spheres.
## - Joined Cylinders (new here): a drum grows up or down to meet a joined neighbour, and grows a flat wing (as deep as the drum
##   is round) toward one beside it, so a joined group reads as one smooth shape.
##
## Where two pieces are joined, the black edge shell is left out on that side too (its walls would show as a dark line between
## the pieces), so the join is smooth.
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
var CylinderMeshes: Dictionary = {}


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
				BlockStyles.Shapes.JoinedCylinders:
					ApplyCylinderMask(Node, Mask)
					RemoveBridges(Node)
				BlockStyles.Shapes.JoinedSpheres:
					ApplyBridges(Node, Piece.Kind, Mask, Shape)
				_:
					RemoveBridges(Node)


## A piece taken off the board (or about to fly): plain again, with no joins.
func Strip(Node: Node3D) -> void:
	RemoveBridges(Node)
	if Styles.CurrentShape == BlockStyles.Shapes.JoinedCubes:
		ApplyCubeMask(Node, 0)
	elif Styles.CurrentShape == BlockStyles.Shapes.JoinedCylinders:
		ApplyCylinderMask(Node, 0)


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
		CubeMeshes[Mask] = [MakeCubeMesh(Mask, false), MakeCubeMesh(Mask, true)]
	var Meshes: Array = CubeMeshes[Mask]
	(Node.get_child(0) as MeshInstance3D).mesh = Meshes[0]
	(Node.get_child(1) as MeshInstance3D).mesh = Meshes[1]


## A box `BlockSize` deep and as wide and tall as a piece, reaching out to the cell's edge (half a pitch from the middle) on every
## joined side. The edge shell (`Shell`) is a copy a little bigger on every side but the joined ones, which it leaves open.
func MakeCubeMesh(Mask: int, Shell: bool) -> ArrayMesh:
	var Grow := BlockSize * (EdgeScale - 1.0) / 2.0 if Shell else 0.0
	var Half := BlockSize / 2.0 + Grow
	var Reach := Pitch / 2.0
	var Skip := 0
	var East := Half
	var West := Half
	var Up := Half
	var Down := Half
	if Mask & 1:
		East = Reach
		Skip |= PieceMeshes.FaceRight
	if Mask & 2:
		West = Reach
		Skip |= PieceMeshes.FaceLeft
	if Mask & 4:
		Up = Reach
		Skip |= PieceMeshes.FaceUp
	if Mask & 8:
		Down = Reach
		Skip |= PieceMeshes.FaceDown
	var Tool := PieceMeshes.NewTool()
	PieceMeshes.AddBox(Tool, Vector3(-West, -Down, -Half), Vector3(East, Up, Half), Skip if Shell else 0)
	return Tool.commit()


# MARK: Joined Cylinders

func ApplyCylinderMask(Node: Node3D, Mask: int) -> void:
	if not CylinderMeshes.has(Mask):
		CylinderMeshes[Mask] = [MakeCylinderMesh(Mask, false), MakeCylinderMesh(Mask, true)]
	var Meshes: Array = CylinderMeshes[Mask]
	(Node.get_child(0) as MeshInstance3D).mesh = Meshes[0]
	(Node.get_child(1) as MeshInstance3D).mesh = Meshes[1]


## A drum standing on its end, grown up or down to the cell's edge toward a joined neighbour (its cap left off there), with a flat
## wing out to the cell's edge toward a joined neighbour beside it - as deep as the drum is round, and as tall as the drum is
## there. The edge shell is the same, a little bigger, and open wherever there is a join.
func MakeCylinderMesh(Mask: int, Shell: bool) -> ArrayMesh:
	var Grow := BlockSize * (EdgeScale - 1.0) / 2.0 if Shell else 0.0
	var Radius := BlockSize / 2.0 + Grow
	var Reach := Pitch / 2.0
	var Up := Reach if Mask & 4 else Radius
	var Down := Reach if Mask & 8 else Radius
	var Tool := PieceMeshes.NewTool()
	PieceMeshes.AddCylinder(Tool, Radius, -Down, Up, Mask & 4 == 0, Mask & 8 == 0)
	var Skip := PieceMeshes.FaceRight | PieceMeshes.FaceLeft
	if Mask & 4:
		Skip |= PieceMeshes.FaceUp
	if Mask & 8:
		Skip |= PieceMeshes.FaceDown
	if Mask & 1:
		PieceMeshes.AddBox(Tool, Vector3(0, -Down, -Radius), Vector3(Reach, Up, Radius), Skip if Shell else 0)
	if Mask & 2:
		PieceMeshes.AddBox(Tool, Vector3(-Reach, -Down, -Radius), Vector3(0, Up, Radius), Skip if Shell else 0)
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


## The mesh of a bridge between two spheres: a cylinder, `Scale` times as wide (1 for the bridge, the edge scale for its shell).
func BridgeMesh(Shape: int, Horizontal: bool, Scale: float) -> Mesh:
	var Key := [Shape, Horizontal, Scale]
	if BridgeMeshes.has(Key):
		return BridgeMeshes[Key]
	var Width := BlockSize * BridgeFraction * Scale
	var Rod := CylinderMesh.new()
	Rod.top_radius = Width / 2.0
	Rod.bottom_radius = Width / 2.0
	Rod.height = Pitch
	BridgeMeshes[Key] = Rod
	return Rod
