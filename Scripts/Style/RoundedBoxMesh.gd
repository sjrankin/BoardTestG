class_name RoundedBoxMesh
extends RefCounted
## A cube with rounded edges and corners, built from a grid on each face: every point of the plain cube is moved to the
## nearest point of the smaller inner box, then pushed out along the way back by the corner radius - which is exactly
## the surface of a box with rounded edges. The rounding is spread over `Steps` grid lines per edge, and the flat middle
## of each face is a single quad.


## A rounded box `Size` wide on every side whose edges and corners have radius `Radius`.
static func Build(Size: float, Radius: float, Steps: int = 6) -> ArrayMesh:
	var Half := Size / 2.0
	var Inner := Half - Radius
	# The grid lines along one side of a face: `Steps` + 1 across the rounded edge, then the flat middle is one quad,
	# then the same again across the other edge.
	var Lines: Array[float] = []
	for Index in Steps + 1:
		Lines.append(-Half + Radius * float(Index) / float(Steps))
	for Index in Steps + 1:
		Lines.append(Inner + Radius * float(Index) / float(Steps))
	var Tool := SurfaceTool.new()
	Tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	# Each face: the direction it faces, and its two grid directions.
	var Faces := [
		[Vector3.RIGHT, Vector3.BACK, Vector3.UP],
		[Vector3.LEFT, Vector3.UP, Vector3.BACK],
		[Vector3.UP, Vector3.RIGHT, Vector3.BACK],
		[Vector3.DOWN, Vector3.BACK, Vector3.RIGHT],
		[Vector3.BACK, Vector3.UP, Vector3.RIGHT],
		[Vector3.FORWARD, Vector3.RIGHT, Vector3.UP],
	]
	for Face in Faces:
		var Normal: Vector3 = Face[0]
		var AxisU: Vector3 = Face[1]
		var AxisV: Vector3 = Face[2]
		for Row in Lines.size() - 1:
			for Column in Lines.size() - 1:
				var Corners: Array[Vector3] = []
				for Offset in [Vector2i(0, 0), Vector2i(1, 0), Vector2i(1, 1), Vector2i(0, 1)]:
					var Spot := Normal * Half + AxisU * Lines[Column + Offset.x] + AxisV * Lines[Row + Offset.y]
					Corners.append(Rounded(Spot, Inner, Radius))
				AddTriangle(Tool, Corners[0], Corners[1], Corners[2], Inner)
				AddTriangle(Tool, Corners[0], Corners[2], Corners[3], Inner)
	return Tool.commit()


## The point of the rounded box that matches a point of the plain cube's surface.
static func Rounded(Spot: Vector3, Inner: float, Radius: float) -> Vector3:
	var Core := Spot.clamp(Vector3.ONE * -Inner, Vector3.ONE * Inner)
	var Away := Spot - Core
	return Core + (Away.normalized() * Radius if Away.length() > 0.00001 else Vector3.ZERO)


## One triangle with smooth normals (the direction away from the inner box), wound so it faces outward.
static func AddTriangle(Tool: SurfaceTool, A: Vector3, B: Vector3, C: Vector3, Inner: float) -> void:
	var Facing := (B - A).cross(C - A)
	var Outward := (A + B + C) / 3.0
	# Godot draws the clockwise side of a triangle, so the winding's cross product must point inward.
	if Facing.dot(Outward) > 0.0:
		var Swap := B
		B = C
		C = Swap
	for Corner in [A, B, C]:
		var Core: Vector3 = Corner.clamp(Vector3.ONE * -Inner, Vector3.ONE * Inner)
		var Direction: Vector3 = Corner - Core
		Tool.set_normal(Direction.normalized() if Direction.length() > 0.00001 else Corner.normalized())
		Tool.add_vertex(Corner)
