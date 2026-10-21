class_name CubeJoins
extends RefCounted
## The joined shapes on the 3D cube - the same four as `JoinSystem` has for the 2D board (Joined Cubes, Joined Spheres, Joined
## Cylinders, Joined Glow), the same rules, but a piece has up to six neighbours: pieces of the same colour that touch along a side
## and are both at rest are joined. A group that runs round an edge of the cube is joined round it too.
##
## A neighbour mask has a bit per direction, the same bits `PieceMeshes.AddBox` uses for its faces: 1 is +X, 2 is -X, 4 is +Y (up),
## 8 is -Y, 16 is +Z (toward the front), 32 is -Z. A piece that is moving (falling, refilling, shuffling) has no joins, and neither
## does anything beside it that was joined to it; they come back when it lands. A piece taken off the cube loses them at once.

const Pitch := BlockStyles.Pitch
const BlockSize := BlockStyles.BlockSize
const EdgeScale := BlockStyles.OutlineScale
## A bridge's width as a fraction of a piece's: a hair narrower, so its surface never coincides with a sphere's.
const BridgeFraction := 0.99
## How many small glows span the gap between two joined glow pieces.
const GlowBridgeSteps := 3
## The directions, as [offset, bit].
const Sides: Array = [[Vector3i(1, 0, 0), 1], [Vector3i(-1, 0, 0), 2], [Vector3i(0, 1, 0), 4], [Vector3i(0, -1, 0), 8], [Vector3i(0, 0, 1), 16], [Vector3i(0, 0, -1), 32]]
## The bridges a piece owns (the neighbour on the positive side owns the matching one from the other end): [bit, node name, axis].
const Owned: Array = [[1, "JoinX", Vector3.RIGHT], [4, "JoinY", Vector3.UP], [16, "JoinZ", Vector3.BACK]]

var Model: CubeModel
var Styles: BlockStyles
var PieceNodes: Dictionary
var LastShape: int = -1
var CubeMeshes: Dictionary = {}
var CylinderMeshes: Dictionary = {}
var RodMeshes: Dictionary = {}
var GlowBridgeHalo: QuadMesh
var GlowBridgeCore: QuadMesh


## Brings every piece's joins up to date with the cube: `Moving` holds the ids of pieces that are not at rest.
func Update(Moving: Dictionary) -> void:
	var Shape := Styles.CurrentShape
	var Joined := Styles.IsJoined()
	# A shape change starts from a clean slate: no bridge of the old shape may be mistaken for one of the new.
	var Changed := Shape != LastShape
	LastShape = Shape
	for Cell in Model.SurfaceCells:
		var Piece := Model.GetPiece(Cell)
		if Piece == null or not PieceNodes.has(Piece.Id):
			continue
		var Node: Node3D = PieceNodes[Piece.Id]
		if Changed:
			RemoveBridges(Node)
		var Mask := 0
		if Joined and not Moving.has(Piece.Id):
			Mask = NeighbourMask(Piece, Cell, Moving)
		match Shape:
			BlockStyles.Shapes.JoinedCubes:
				ApplyMeshes(Node, CubeMeshes, Mask, MakeCubeMesh)
				RemoveBridges(Node)
			BlockStyles.Shapes.JoinedCylinders:
				ApplyMeshes(Node, CylinderMeshes, Mask, MakeCylinderMesh)
				RemoveBridges(Node)
			BlockStyles.Shapes.JoinedSpheres:
				ApplyBridges(Node, Piece.Kind, Mask, false)
			BlockStyles.Shapes.JoinedGlow:
				ApplyBridges(Node, Piece.Kind, Mask, true)
			_:
				RemoveBridges(Node)


## A piece taken off the cube (or about to fly): plain again, with no joins.
func Strip(Node: Node3D) -> void:
	RemoveBridges(Node)
	if Styles.CurrentShape == BlockStyles.Shapes.JoinedCubes:
		ApplyMeshes(Node, CubeMeshes, 0, MakeCubeMesh)
	elif Styles.CurrentShape == BlockStyles.Shapes.JoinedCylinders:
		ApplyMeshes(Node, CylinderMeshes, 0, MakeCylinderMesh)


## Which sides of the piece at `Cell` have a joined neighbour: same colour, present, and not moving.
func NeighbourMask(Piece: BoardModel.PieceData, Cell: Vector3i, Moving: Dictionary) -> int:
	var Mask := 0
	for Side in Sides:
		var Other := Model.GetPiece(Cell + Side[0])
		if Other != null and Other.Kind == Piece.Kind and PieceNodes.has(Other.Id) and not Moving.has(Other.Id):
			Mask |= Side[1]
	return Mask


# MARK: Joined Cubes and Joined Cylinders

func ApplyMeshes(Node: Node3D, Cache: Dictionary, Mask: int, Maker: Callable) -> void:
	if not Cache.has(Mask):
		Cache[Mask] = [Maker.call(Mask, false), Maker.call(Mask, true)]
	var Meshes: Array = Cache[Mask]
	(Node.get_child(0) as MeshInstance3D).mesh = Meshes[0]
	(Node.get_child(1) as MeshInstance3D).mesh = Meshes[1]


## A box as big as a piece, reaching out to the cell's edge (half a pitch from the middle) on every joined side. The edge shell
## (`Shell`) is a copy a little bigger on every side but the joined ones, which it leaves open.
func MakeCubeMesh(Mask: int, Shell: bool) -> ArrayMesh:
	var Grow := BlockSize * (EdgeScale - 1.0) / 2.0 if Shell else 0.0
	var Half := BlockSize / 2.0 + Grow
	var Reach := Pitch / 2.0
	var Low := Vector3(-(Reach if Mask & 2 else Half), -(Reach if Mask & 8 else Half), -(Reach if Mask & 32 else Half))
	var High := Vector3(Reach if Mask & 1 else Half, Reach if Mask & 4 else Half, Reach if Mask & 16 else Half)
	var Tool := PieceMeshes.NewTool()
	PieceMeshes.AddBox(Tool, Low, High, Mask if Shell else 0)
	return Tool.commit()


## A drum standing on its end, grown up or down to the cell's edge toward a joined neighbour (its cap left off there), with a flat
## wing out to the cell's edge toward a joined neighbour beside it (east, west, front or back) - as deep as the drum is round, and as
## tall as the drum is there. The edge shell is the same, a little bigger, and open wherever there is a join.
func MakeCylinderMesh(Mask: int, Shell: bool) -> ArrayMesh:
	var Grow := BlockSize * (EdgeScale - 1.0) / 2.0 if Shell else 0.0
	var Radius := BlockSize / 2.0 + Grow
	var Reach := Pitch / 2.0
	var Up := Reach if Mask & 4 else Radius
	var Down := Reach if Mask & 8 else Radius
	var Tool := PieceMeshes.NewTool()
	PieceMeshes.AddCylinder(Tool, Radius, -Down, Up, Mask & 4 == 0, Mask & 8 == 0)
	var Ends := Mask & (PieceMeshes.FaceUp | PieceMeshes.FaceDown)
	if Mask & 1:
		PieceMeshes.AddBox(Tool, Vector3(0, -Down, -Radius), Vector3(Reach, Up, Radius), (PieceMeshes.FaceRight | PieceMeshes.FaceLeft | Ends) if Shell else 0)
	if Mask & 2:
		PieceMeshes.AddBox(Tool, Vector3(-Reach, -Down, -Radius), Vector3(0, Up, Radius), (PieceMeshes.FaceRight | PieceMeshes.FaceLeft | Ends) if Shell else 0)
	if Mask & 16:
		PieceMeshes.AddBox(Tool, Vector3(-Radius, -Down, 0), Vector3(Radius, Up, Reach), (PieceMeshes.FaceBack | PieceMeshes.FaceFront | Ends) if Shell else 0)
	if Mask & 32:
		PieceMeshes.AddBox(Tool, Vector3(-Radius, -Down, -Reach), Vector3(Radius, Up, 0), (PieceMeshes.FaceBack | PieceMeshes.FaceFront | Ends) if Shell else 0)
	return Tool.commit()


# MARK: Bridges (Joined Spheres and Joined Glow)

## Adds a bridge to each joined side the piece owns (+X, +Y, +Z), and removes the rest. A bridge is a rod (Joined Spheres) or a
## streak of small glows (Joined Glow).
func ApplyBridges(Node: Node3D, Kind: int, Mask: int, Glowing: bool) -> void:
	for Own in Owned:
		var Name: String = Own[1]
		var Existing := Node.get_node_or_null(Name)
		if Mask & Own[0] == 0:
			if Existing != null:
				Existing.queue_free()
				Existing.name = Name + "Gone"
			continue
		if Existing != null:
			if not Glowing:
				(Existing as MeshInstance3D).material_override = Styles.Materials[Kind]
			continue
		Node.add_child(MakeGlowBridge(Name, Kind, Own[2]) if Glowing else MakeRod(Name, Kind, Own[2]))


func RemoveBridges(Node: Node3D) -> void:
	for Own in Owned:
		var Existing := Node.get_node_or_null(Own[1] as String)
		if Existing != null:
			Existing.queue_free()
			Existing.name = (Own[1] as String) + "Gone"


## A rod between two joined spheres, half a pitch out along `Axis` (the middle of the gap), with its black edge as a child.
func MakeRod(Name: String, Kind: int, Axis: Vector3) -> MeshInstance3D:
	var Rod := MeshInstance3D.new()
	Rod.name = Name
	Rod.mesh = RodMesh(1.0)
	Rod.material_override = Styles.Materials[Kind]
	Rod.position = Axis * Pitch / 2.0
	if Axis == Vector3.RIGHT:
		Rod.rotation_degrees = Vector3(0, 0, 90)
	elif Axis == Vector3.BACK:
		Rod.rotation_degrees = Vector3(90, 0, 0)
	var Shell := MeshInstance3D.new()
	Shell.name = "Edge"
	Shell.mesh = RodMesh(EdgeScale)
	Shell.material_override = Styles.OutlineMaterial
	Rod.add_child(Shell)
	return Rod


func RodMesh(Scale: float) -> Mesh:
	if RodMeshes.has(Scale):
		return RodMeshes[Scale]
	var Rod := CylinderMesh.new()
	Rod.top_radius = BlockSize * BridgeFraction * Scale / 2.0
	Rod.bottom_radius = Rod.top_radius
	Rod.height = Pitch
	RodMeshes[Scale] = Rod
	return Rod


## A few small glows spaced across the gap along `Axis`, which add up to a soft streak joining the two cores.
func MakeGlowBridge(Name: String, Kind: int, Axis: Vector3) -> Node3D:
	if GlowBridgeHalo == null:
		GlowBridgeHalo = QuadMesh.new()
		GlowBridgeHalo.size = Vector2.ONE * BlockStyles.GlowHaloSize * 0.6
		GlowBridgeCore = QuadMesh.new()
		GlowBridgeCore.size = Vector2.ONE * BlockStyles.GlowCoreSize * 0.7
	var Bridge := Node3D.new()
	Bridge.name = Name
	for Step in GlowBridgeSteps:
		var Spot := MeshInstance3D.new()
		Spot.mesh = GlowBridgeHalo
		Spot.material_override = Styles.GlowHaloMaterials[Kind]
		Spot.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		Spot.position = Axis * Pitch * (float(Step + 1) / (GlowBridgeSteps + 1))
		Bridge.add_child(Spot)
		var Heart := MeshInstance3D.new()
		Heart.mesh = GlowBridgeCore
		Heart.material_override = Styles.GlowCoreMaterials[Kind]
		Heart.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		Spot.add_child(Heart)
	return Bridge
