class_name BoardViewRemoval
extends BoardViewBuild

## Taps, removal effects and Attract Mode.

# MARK: Input

## Whether a camera ray meets the board (the rectangle of its cells, pieces or not).
func HitsBoard(WorldOrigin: Vector3, WorldDirection: Vector3) -> bool:
	if Model == null:
		return false
	var ToBoard := global_transform.affine_inverse()
	var Origin := ToBoard * WorldOrigin
	var Direction := ToBoard.basis * WorldDirection
	if absf(Direction.z) < 0.0001:
		return false
	var T := -Origin.z / Direction.z
	if T < 0.0:
		return false
	var Point := Origin + Direction * T
	var Col := floori(Point.x / BlockStyles.Pitch + Model.Width / 2.0)
	var Row := floori(Model.Height / 2.0 - Point.y / BlockStyles.Pitch)
	return Col >= 0 and Col < Model.Width and Row >= 0 and Row < Model.Height


## A tap on the board along a camera ray.
func HandleTapRay(WorldOrigin: Vector3, WorldDirection: Vector3) -> void:
	if Busy or InputLocked or Model == null:
		return
	# The ray in the board's own space, where the board is the plane z = 0 however it is turned.
	var ToBoard := global_transform.affine_inverse()
	var Origin := ToBoard * WorldOrigin
	var Direction := ToBoard.basis * WorldDirection
	if absf(Direction.z) < 0.0001:
		return
	var T := -Origin.z / Direction.z
	if T < 0.0:
		return
	var Point := Origin + Direction * T
	var Col := floori(Point.x / BlockStyles.Pitch + Model.Width / 2.0)
	var Row := floori(Model.Height / 2.0 - Point.y / BlockStyles.Pitch)
	# A tap that lands on a piece of the board takes any showing hint away (even one that clears no group).
	if Model.GetPiece(Col, Row) != null:
		Hint.Dismiss()
	TapCell(Col, Row)


func TapCell(Col: int, Row: int) -> void:
	if Busy or InputLocked or Model == null:
		return
	var Group := Model.GroupAt(Col, Row)
	if Group.size() < BoardModel.MinimumGroupSize:
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
			Leaving.append({"Node": Node, "Kind": Piece.Kind})
			Joins.Strip(Node)
	# Whatever was joined to a removed piece is on its own again at once.
	Joins.Update(MovingIds)
	if LightningEnabled and not Leaving.is_empty():
		await CrackleLightning(Leaving)
	SendFlying(Leaving)


## Shatters every piece on the board (a won level): the board is left empty and the shards fly, and any Blockers fly off out of
## sight. The caller starts the next game.
func ExplodeAll() -> void:
	Busy = true
	Hint.Clear()
	var Camera := get_viewport().get_camera_3d()
	for Light in BlockerLights:
		if Camera != null and is_instance_valid(Light):
			# The next game waits for them like it waits for any removal effect.
			InPlaceActive += 1
			Light.Gone.connect(OnInPlaceDone.bind(GameNumber))
			Light.FlyAway(Camera)
	BlockerLights.clear()
	var Entries: Array[Dictionary] = []
	for Col in Model.Width:
		for Row in Model.Height:
			var Piece := Model.GetPiece(Col, Row)
			if Piece == null:
				continue
			var Node: Node3D = PieceNodes.get(Piece.Id)
			if Node != null:
				Entries.append({"Kind": Piece.Kind, "Position": Node.global_position})
				Joins.Strip(Node)
				Node.queue_free()
			PieceNodes.erase(Piece.Id)
			Model.SetPiece(Col, Row, null)
	Flyers.ExplodeAll(Entries)


## Lightning arcs across the pieces about to leave, while they are still in place; returns when it is time for them to go.
func CrackleLightning(Leaving: Array[Dictionary]) -> void:
	var Game := GameNumber
	var Points: Array[Vector3] = []
	for Entry in Leaving:
		Points.append((Entry["Node"] as Node3D).global_position)
	var Tint := Color(0.55, 0.75, 1.0).lerp(Styles.Shown[Leaving[0]["Kind"]], 0.3)
	LightningEffect.Play(get_parent(), Points, Tint)
	await get_tree().create_timer(LightningLead).timeout
	# A new game started while the lightning played: the pieces it was about are gone.
	if Game != GameNumber:
		Leaving.clear()


## Pops the removed pieces out of the board's front face and starts waiting for them to leave their cells.
func SendFlying(Leaving: Array[Dictionary]) -> void:
	if not is_inside_tree():
		# The board was switched out of the scene while the lightning played (Settings > Board Type). Nothing of this game is shown,
		# and the board starts a new game when it is switched back to, so the pieces are just freed.
		for Entry in Leaving:
			if is_instance_valid(Entry["Node"]):
				(Entry["Node"] as Node3D).queue_free()
		return
	if RemovalEffect == RemovalEffects.Smoke:
		# The pieces are gone at once, so no cell is held up for the refill: it starts at the next physics step, and the smoke
		# carries on over whatever drops in.
		var Front := SmokeFront()
		for Entry in Leaving:
			Entry["Out"] = Front
		SmokeBurst.Replace(Flyers, Leaving, Styles.Shown, RemovalSpeed, SmokeUp())
		WaitingForVacate = true
		VacateClock = 0.0
		return
	for Entry in Leaving:
		var Node: Node3D = Entry["Node"]
		if not is_instance_valid(Node):
			continue
		if RemovalEffect >= RemovalEffects.Disappear:
			# Plays where it stands; the piece is freed when the effect is over.
			InPlaceActive += 1
			InPlaceRemoval.Play(self, Node, RemovalEffect, OnInPlaceDone.bind(GameNumber))
			continue
		if RemovalEffect == RemovalEffects.Explode:
			Flyers.Explode(Entry["Kind"], Node.global_position, randi_range(FlyerSystem.MinShardsPerPiece, FlyerSystem.MaxShardsPerPiece))
		elif RemovalEffect == RemovalEffects.MiniMe:
			# The piece bursts where it stands; its cell stays open, so the fragments are free to leave it (or bounce back in).
			Flyers.MiniMe(Entry["Kind"], Node.global_position, randi_range(FlyerSystem.MinFragmentsPerPiece, FlyerSystem.MaxFragmentsPerPiece))
		else:
			# Out of the board's face, along its normal as it is turned right now.
			Flyers.Launch(Entry["Kind"], Node.global_position, global_basis)
			Flyers.AddOriginBlocker(self, Node.position)
		Node.queue_free()
	WaitingForVacate = true
	VacateClock = 0.0


func OnInPlaceDone(Game: int) -> void:
	if Game == GameNumber:
		InPlaceActive = maxi(InPlaceActive - 1, 0)


## Attract Mode's move: the largest playable group; among groups of the same size, the one closest on average to the bottom
## (the bottom as the user sees it, so the same direction gravity pulls); among those still equal, one at random.
func AttractStep() -> void:
	if Busy or InputLocked or Model == null:
		return
	var Groups := Model.PlayableGroups()
	if Groups.is_empty():
		return
	var Down := GravityFromUser()
	var Best: Array = []
	var BestSize := 0
	var BestDistance := INF
	for Group in Groups:
		var Distance := AverageDistanceFromBottom(Group, Down)
		if Group.size() > BestSize or (Group.size() == BestSize and Distance < BestDistance - 0.0001):
			Best = [Group]
			BestSize = Group.size()
			BestDistance = Distance
		elif Group.size() == BestSize and absf(Distance - BestDistance) <= 0.0001:
			Best.append(Group)
	var Chosen: Array = Best[randi() % Best.size()]
	TapCell(Chosen[0].x, Chosen[0].y)


## How long the refill waits for the removed pieces to leave their cells: an Explode's shards are small enough not to hold it up.
func VacateLimit() -> float:
	return FlyerSystem.ExplodeVacateTimeout if RemovalEffect == RemovalEffects.Explode else FlyerSystem.VacateTimeout


## The way smoke rises: exactly against the way pieces fall on this board. That is the board's gravity (the grid direction the next drop
## will use, `GravityFromUser`) taken into the world, so it follows the board when it is tilted. (Row 0 is the top, so a gravity of
## (0, 1) is the board's own down, -y.)
func SmokeUp() -> Vector3:
	if not is_inside_tree():
		return Vector3.UP
	var Fall := GravityFromUser()
	return -(global_basis * Vector3(Fall.x, -Fall.y, 0.0)).normalized()


## The way smoke leaves the board: out of the face the viewer sees (the front, or the back if the board is turned round), so it
## blooms in front of the neighbouring pieces. Only the look of the smoke; where pieces go is not affected.
func SmokeFront() -> Vector3:
	if not is_inside_tree():
		return Vector3.BACK
	var Front := global_basis.z.normalized()
	var Camera := get_viewport().get_camera_3d()
	if Camera != null and Front.dot(Camera.global_position - global_position) < 0.0:
		return -Front
	return Front
