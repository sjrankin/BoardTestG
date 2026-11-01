class_name CubeViewRemoval
extends CubeViewBuild

## Taps, removal effects and Attract Mode.

# MARK: Input

## Whether a camera ray meets the cube's box.
func HitsBoard(WorldOrigin: Vector3, WorldDirection: Vector3) -> bool:
	if Model == null:
		return false
	var ToCube := global_transform.affine_inverse()
	var Origin := ToCube * WorldOrigin
	var Direction := ToCube.basis * WorldDirection
	var Half := Vector3(Model.Width, Model.Height, Model.Depth) * Pitch / 2.0
	var Near := -INF
	var Far := INF
	for Axis in 3:
		if absf(Direction[Axis]) < 0.00001:
			if absf(Origin[Axis]) > Half[Axis]:
				return false
			continue
		var T1: float = (-Half[Axis] - Origin[Axis]) / Direction[Axis]
		var T2: float = (Half[Axis] - Origin[Axis]) / Direction[Axis]
		Near = maxf(Near, minf(T1, T2))
		Far = minf(Far, maxf(T1, T2))
	return Far >= 0.0 and Near <= Far


## A tap along a camera ray: the ray is taken into the cube's own space, where it meets the box's surface at the nearest face.
func HandleTapRay(WorldOrigin: Vector3, WorldDirection: Vector3) -> void:
	if Busy or InputLocked or Model == null:
		return
	var ToCube := global_transform.affine_inverse()
	var Origin := ToCube * WorldOrigin
	var Direction := ToCube.basis * WorldDirection
	var Size := Vector3(Model.Width, Model.Height, Model.Depth)
	var Half := Size * Pitch / 2.0
	var Near := -INF
	var Far := INF
	var NearAxis := -1
	for Axis in 3:
		if absf(Direction[Axis]) < 0.00001:
			if absf(Origin[Axis]) > Half[Axis]:
				return
			continue
		var T1: float = (-Half[Axis] - Origin[Axis]) / Direction[Axis]
		var T2: float = (Half[Axis] - Origin[Axis]) / Direction[Axis]
		if minf(T1, T2) > Near:
			Near = minf(T1, T2)
			NearAxis = Axis
		Far = minf(Far, maxf(T1, T2))
	if NearAxis < 0 or Near < 0.0 or Near > Far:
		return
	var Hit := Origin + Direction * Near
	var Index: Array[int] = [0, 0, 0]
	for Axis in 3:
		Index[Axis] = clampi(floori(Hit[Axis] / Pitch + Size[Axis] / 2.0), 0, int(Size[Axis]) - 1)
	Index[NearAxis] = 0 if Direction[NearAxis] > 0.0 else int(Size[NearAxis]) - 1
	var Cell := Vector3i(Index[0], Index[1], Index[2])
	if Model.GetPiece(Cell) != null:
		TapCell(Cell)


func TapCell(Cell: Vector3i) -> void:
	if Busy or InputLocked or Model == null:
		return
	var Group := Model.GroupAt(Cell)
	if Group.size() < CubeModel.MinimumGroupSize:
		return
	Busy = true
	var Removed := Model.Remove(Group)
	ScoreChanged.emit(Model.Score)
	if not Removed.is_empty():
		GroupRemoved.emit((Removed[0]["Piece"] as BoardModel.PieceData).Kind, Removed.size())
	var Leaving: Array[Dictionary] = []
	for Entry in Removed:
		var Piece: BoardModel.PieceData = Entry["Piece"]
		var Node: Node3D = PieceNodes.get(Piece.Id)
		PieceNodes.erase(Piece.Id)
		if Node != null:
			Leaving.append({"Node": Node, "Kind": Piece.Kind, "Out": Model.OutwardAt(Entry["Cell"])})
			Joins.Strip(Node)
	# Whatever was joined to a removed piece is on its own again at once.
	Joins.Update(MovingIds)
	if LightningEnabled and not Leaving.is_empty():
		await CrackleLightning(Leaving)
	SendFlying(Leaving)


## Shatters every piece on the cube (a won level): the cube is left empty and the shards fly. The caller starts the next game.
func ExplodeAll() -> void:
	Busy = true
	var Entries: Array[Dictionary] = []
	for Cell in Model.Cells.keys():
		var Piece := Model.GetPiece(Cell)
		if Piece == null:
			continue
		var Node: Node3D = PieceNodes.get(Piece.Id)
		if Node != null:
			Entries.append({"Kind": Piece.Kind, "Position": Node.global_position})
			Joins.Strip(Node)
			Node.queue_free()
		PieceNodes.erase(Piece.Id)
		Model.SetPiece(Cell, null)
	Flyers.ExplodeAll(Entries)


## Lightning arcs across the pieces about to leave, while they are still in place; returns when it is time for them to go.
func CrackleLightning(Leaving: Array[Dictionary]) -> void:
	var Game := GameNumber
	var Points: Array[Vector3] = []
	for Entry in Leaving:
		# Just outside the piece's face, so the bolt runs over the surface; the blocks hide it everywhere else.
		Points.append((Entry["Node"] as Node3D).global_position + global_basis * (Entry["Out"] as Vector3) * BoltLift)
	var Tint := Color(0.55, 0.75, 1.0).lerp(Styles.Shown[Leaving[0]["Kind"]], 0.3)
	LightningEffect.Play(get_parent(), Points, Tint, true)
	await get_tree().create_timer(LightningLead).timeout
	if Game != GameNumber:
		Leaving.clear()


## A basis for a launch out of a face: its Z is the way out, its Y as near to the world's up as that allows.
func LaunchBasis(Out: Vector3) -> Basis:
	var Z := Out.normalized()
	var UpHint := Vector3.UP if absf(Z.dot(Vector3.UP)) < 0.9 else Vector3.FORWARD
	var X := UpHint.cross(Z).normalized()
	return Basis(X, Z.cross(X), Z)


## Pops the removed pieces out of the faces they were on and starts waiting for them to leave their cells.
func SendFlying(Leaving: Array[Dictionary]) -> void:
	if not is_inside_tree():
		# The board was switched out of the scene while the lightning played (Settings > Board Type). Nothing of this game is shown,
		# and the board starts a new game when it is switched back to, so the pieces are just freed.
		for Entry in Leaving:
			if is_instance_valid(Entry["Node"]):
				(Entry["Node"] as Node3D).queue_free()
		return
	if RemovalEffect == BoardView.RemovalEffects.Smoke:
		# The pieces are gone at once, so no cell is held up for the refill: it starts at the next physics step, and the smoke
		# carries on over whatever falls in.
		for Entry in Leaving:
			# Out of the face the piece was on, as the cube is turned right now.
			Entry["Out"] = (global_basis * (Entry["Out"] as Vector3)).normalized()
		SmokeBurst.Replace(Flyers, Leaving, Styles.Shown, RemovalSpeed, SmokeUp())
		WaitingForVacate = true
		VacateClock = 0.0
		return
	for Entry in Leaving:
		var Node: Node3D = Entry["Node"]
		if not is_instance_valid(Node):
			continue
		if RemovalEffect >= BoardView.RemovalEffects.Disappear:
			# Plays where it stands; the piece is freed when the effect is over.
			InPlaceActive += 1
			InPlaceRemoval.Play(self, Node, RemovalEffect, OnInPlaceDone.bind(GameNumber))
			continue
		if RemovalEffect == BoardView.RemovalEffects.Explode:
			Flyers.Explode(Entry["Kind"], Node.global_position, randi_range(FlyerSystem.MinShardsPerPiece, FlyerSystem.MaxShardsPerPiece))
		elif RemovalEffect == BoardView.RemovalEffects.MiniMe:
			Flyers.MiniMe(Entry["Kind"], Node.global_position, randi_range(FlyerSystem.MinFragmentsPerPiece, FlyerSystem.MaxFragmentsPerPiece))
		else:
			# Out of the face the piece was on (between the faces, for an edge or corner), as the cube is turned right now.
			Flyers.Launch(Entry["Kind"], Node.global_position, LaunchBasis(global_basis * (Entry["Out"] as Vector3)))
			Flyers.AddOriginBlocker(self, Node.position)
		Node.queue_free()
	WaitingForVacate = true
	VacateClock = 0.0


func OnInPlaceDone(Game: int) -> void:
	if Game == GameNumber:
		InPlaceActive = maxi(InPlaceActive - 1, 0)


## Attract Mode's move: a face chosen at random from the six - among those with a playable group touching them - then the largest
## such group on it (a random one among equals). Over time every side gets played, not just the one that has the biggest groups.
func AttractStep() -> void:
	if Busy or InputLocked or Model == null:
		return
	var Groups := Model.PlayableGroups()
	var Faces: Array[int] = []
	for Face in 6:
		for Group in Groups:
			if Group.any(func(Cell: Vector3i) -> bool: return Model.OnFace(Cell, Face)):
				Faces.append(Face)
				break
	if Faces.is_empty():
		return
	var Face: int = Faces[randi() % Faces.size()]
	var Best: Array = []
	var BestSize := 0
	for Group in Groups:
		if not Group.any(func(Cell: Vector3i) -> bool: return Model.OnFace(Cell, Face)):
			continue
		if Group.size() > BestSize:
			Best = [Group]
			BestSize = Group.size()
		elif Group.size() == BestSize:
			Best.append(Group)
	var Chosen: Array = Best[randi() % Best.size()]
	TapCell(Chosen[0])


## How long the refill waits for the removed pieces to leave their cells: an Explode's shards are small enough not to hold it up.
func VacateLimit() -> float:
	return FlyerSystem.ExplodeVacateTimeout if RemovalEffect == BoardView.RemovalEffects.Explode else FlyerSystem.VacateTimeout


## The way smoke rises: exactly against the way pieces fall on the cube, which is the world's down, however the cube is turned
## (`Gravity` is that, in the cube's own space).
func SmokeUp() -> Vector3:
	if not is_inside_tree():
		return Vector3.UP
	return -(global_basis * Gravity()).normalized()
