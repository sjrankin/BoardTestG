class_name BoltDrawing
extends RefCounted
## Shared pieces for drawing electrical zaps: a jagged path, a camera-facing ribbon along it, and the light material.


## A jagged path from `From` to `To`: the midpoint of each segment is pushed sideways by a random amount, repeatedly, so
## 2^`Rounds` segments. `Spread` is how far it strays, as a fraction of the length.
static func MakePath(From: Vector3, To: Vector3, Spread: float, Rounds: int = 5) -> PackedVector3Array:
	var Points := PackedVector3Array([From, To])
	var Offset := From.distance_to(To) * Spread
	for Round in Rounds:
		var Next := PackedVector3Array()
		for Index in range(Points.size() - 1):
			var A := Points[Index]
			var B := Points[Index + 1]
			var Direction := (B - A).normalized()
			var Side := Direction.cross(Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1))).normalized()
			Next.append(A)
			Next.append((A + B) / 2.0 + Side * randf_range(-Offset, Offset))
		Next.append(Points[Points.size() - 1])
		Points = Next
		Offset *= 0.55
	return Points


## A camera-facing ribbon along `Path` into a surface already begun as a triangle strip on `Mesh`: thickest in the middle,
## tapering to a point at each end. Consecutive ribbons in one surface are joined by doubled (degenerate) vertices, so no
## stripe is drawn between them. `CameraPosition` is in the mesh's own space. `Tint` colors the ribbon's vertices (the
## material must use vertex colors for it to show).
static func AddRibbon(Mesh: ImmediateMesh, Path: PackedVector3Array, Width: float, CameraPosition: Vector3, Tint: Color = Color.WHITE) -> void:
	var Count := Path.size()
	var First := true
	for Index in Count:
		var Tangent := (Path[mini(Index + 1, Count - 1)] - Path[maxi(Index - 1, 0)]).normalized()
		var View := (CameraPosition - Path[Index]).normalized()
		var Side := Tangent.cross(View).normalized()
		var Taper := sin(PI * float(Index) / float(Count - 1))
		var Half := Side * Width * 0.5 * Taper
		Mesh.surface_set_color(Tint)
		if First:
			Mesh.surface_add_vertex(Path[Index] - Half)
			First = false
		Mesh.surface_add_vertex(Path[Index] - Half)
		Mesh.surface_add_vertex(Path[Index] + Half)
	Mesh.surface_set_color(Tint)
	Mesh.surface_add_vertex(Path[Count - 1])


## An unshaded light material (`Priority` orders overlapping zaps). Additive adds to what is behind it; otherwise it
## blends over it. Drawn over everything unless `DepthTest` is on, in which case pieces in front of it hide it.
static func MakeMaterial(Tint: Color, Priority: int, Additive: bool = true, DepthTest: bool = false) -> StandardMaterial3D:
	var Material := StandardMaterial3D.new()
	Material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	Material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	Material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD if Additive else BaseMaterial3D.BLEND_MODE_MIX
	Material.cull_mode = BaseMaterial3D.CULL_DISABLED
	Material.no_depth_test = not DepthTest
	Material.render_priority = Priority
	Material.albedo_color = Tint
	return Material
