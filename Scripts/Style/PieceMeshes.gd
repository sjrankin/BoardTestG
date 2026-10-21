class_name PieceMeshes
extends RefCounted
## Builders for the odd-shaped meshes of the joined shapes: boxes and cylinders with exact ends (Godot's own are always centred on
## their origin) and with chosen faces left out, so that two pieces joined along a side have no wall - and no black edge line -
## between them. Several shapes can be added to one `SurfaceTool` and committed as a single mesh.

## Face bits for `AddBox`'s `Skip`: which faces are not built.
const FaceRight := 1
const FaceLeft := 2
const FaceUp := 4
const FaceDown := 8
const FaceBack := 16
const FaceFront := 32


static func NewTool() -> SurfaceTool:
	var Tool := SurfaceTool.new()
	Tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	return Tool


## A box with the given opposite corners, flat normals, each face mapped across the whole 0..1 square, leaving out the faces in `Skip`.
static func AddBox(Tool: SurfaceTool, Low: Vector3, High: Vector3, Skip: int = 0) -> void:
	var Faces := [
		[Vector3.RIGHT, Vector3.UP, Vector3.BACK, FaceRight],
		[Vector3.LEFT, Vector3.UP, Vector3.FORWARD, FaceLeft],
		[Vector3.UP, Vector3.BACK, Vector3.RIGHT, FaceUp],
		[Vector3.DOWN, Vector3.RIGHT, Vector3.BACK, FaceDown],
		[Vector3.BACK, Vector3.UP, Vector3.LEFT, FaceBack],
		[Vector3.FORWARD, Vector3.UP, Vector3.RIGHT, FaceFront],
	]
	var Centre := (Low + High) / 2.0
	var Half := (High - Low) / 2.0
	for Face in Faces:
		if Skip & int(Face[3]) != 0:
			continue
		var Normal: Vector3 = Face[0]
		var AxisU: Vector3 = Face[1]
		var AxisV: Vector3 = Face[2]
		var Points: Array[Vector3] = []
		for Corner in [[-1, -1], [1, -1], [1, 1], [-1, 1]]:
			Points.append(Centre + Normal * Half + AxisU * Half * Corner[0] + AxisV * Half * Corner[1])
		var UVs: Array[Vector2] = [Vector2(0, 1), Vector2(1, 1), Vector2(1, 0), Vector2(0, 0)]
		for Triangle in [[0, 1, 2], [0, 2, 3]]:
			AddTriangle(Tool, [Points[Triangle[0]], Points[Triangle[1]], Points[Triangle[2]]],
					[UVs[Triangle[0]], UVs[Triangle[1]], UVs[Triangle[2]]], [Normal, Normal, Normal])


## A cylinder standing on the y axis from `YLow` to `YHigh`, with smooth sides and flat caps - each cap only if wanted.
static func AddCylinder(Tool: SurfaceTool, Radius: float, YLow: float, YHigh: float, CapUp: bool, CapDown: bool, Segments: int = 48) -> void:
	for Index in Segments:
		var A := TAU * Index / Segments
		var B := TAU * (Index + 1) / Segments
		var DirA := Vector3(cos(A), 0, sin(A))
		var DirB := Vector3(cos(B), 0, sin(B))
		var P0 := DirA * Radius + Vector3(0, YLow, 0)
		var P1 := DirB * Radius + Vector3(0, YLow, 0)
		var P2 := DirB * Radius + Vector3(0, YHigh, 0)
		var P3 := DirA * Radius + Vector3(0, YHigh, 0)
		var UA := float(Index) / Segments
		var UB := float(Index + 1) / Segments
		AddTriangle(Tool, [P0, P1, P2], [Vector2(UA, 1), Vector2(UB, 1), Vector2(UB, 0)], [DirA, DirB, DirB])
		AddTriangle(Tool, [P0, P2, P3], [Vector2(UA, 1), Vector2(UB, 0), Vector2(UA, 0)], [DirA, DirB, DirA])
		if CapUp:
			AddTriangle(Tool, [Vector3(0, YHigh, 0), P3, P2], [Vector2(0.5, 0.5), Vector2(0.5 + cos(A) * 0.5, 0.5 + sin(A) * 0.5), Vector2(0.5 + cos(B) * 0.5, 0.5 + sin(B) * 0.5)], [Vector3.UP, Vector3.UP, Vector3.UP])
		if CapDown:
			AddTriangle(Tool, [Vector3(0, YLow, 0), P1, P0], [Vector2(0.5, 0.5), Vector2(0.5 + cos(B) * 0.5, 0.5 + sin(B) * 0.5), Vector2(0.5 + cos(A) * 0.5, 0.5 + sin(A) * 0.5)], [Vector3.DOWN, Vector3.DOWN, Vector3.DOWN])


## One triangle, wound so that it faces away from the origin-ish side its normals point to (Godot draws the clockwise side).
static func AddTriangle(Tool: SurfaceTool, Corners: Array[Vector3], UVs: Array[Vector2], Normals: Array[Vector3]) -> void:
	var Facing := (Corners[1] - Corners[0]).cross(Corners[2] - Corners[0])
	var Order: Array[int] = [0, 1, 2]
	if Facing.dot(Normals[0] + Normals[1] + Normals[2]) > 0.0:
		Order = [0, 2, 1]
	for Index in Order:
		Tool.set_normal(Normals[Index])
		Tool.set_uv(UVs[Index])
		Tool.add_vertex(Corners[Index])
