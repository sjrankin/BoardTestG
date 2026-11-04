class_name CubeView
extends CubeViewRemoval

## Shuffling, falling and refilling, and the per-frame step (this class; the rest is in the scripts it extends, in this order: CubeViewTurning, CubeViewBuild, CubeViewRemoval).

func _process(Delta: float) -> void:
	if AttractActive and AttractSpin and not AutoRotate and not TurnLocked and Model != null:
		SpinStep(Delta)
	if AutoRotate and not TurnLocked:
		AutoClock += Delta
		Yaw = wrapf(Yaw + AutoYawRate * Delta, -PI, PI)
		Tilt = sin(AutoClock * AutoTiltRate) * AutoTiltSwing
		ApplyRotation()


func _physics_process(Delta: float) -> void:
	# The refill waits until every removed piece has left its cell (or a timeout), on the pieces' own clock.
	if WaitingForVacate:
		VacateClock += Delta * RemovalSpeed
		if (Flyers.AllVacated() and InPlaceActive == 0) or VacateClock > VacateLimit():
			WaitingForVacate = false
			StartDrop()


# MARK: Falling and refilling
func StartDrop() -> void:
	Flyers.ClearOriginBlockers()
	var Moves := Model.Drop(Gravity())
	if Moves.is_empty():
		FinishDrop()
		return
	# Every piece moves at the same speed - the longest path takes `FallDuration` - so pieces that start touching stay touching.
	var Walks: Array[Array] = []
	var Longest := 0.0
	for Move in Moves:
		var Points := PathPoints(Move["Path"], Move["Spawned"], Move["Depth"])
		Walks.append(Points)
		Longest = maxf(Longest, PointsLength(Points))
	var Speed := maxf(Longest, 1.0) / FallDuration
	for Move in Moves:
		MovingIds[Move["Piece"].Id] = true
	for Index in Moves.size():
		AnimateMove(Moves[Index]["Piece"], Walks[Index], Speed)
	# Everything that is about to move lets go of its joins now; they come back as each piece lands.
	Joins.Update(MovingIds)
	if PendingTweens == 0:
		FinishDrop()


## The cube-space points a piece walks through for a path of cells. A new piece (created in the cell the path starts at) first falls
## along gravity from above the cube to that cell - higher for each round it was created later, so a column of them arrives one behind
## another - when its face looks up enough to be reached from above; a face turned away from above has nothing to fall from, so the
## piece just grows into place there (a one-point walk).
func PathPoints(Path: Array, Spawned: bool, Depth: int) -> Array[Vector3]:
	var Points: Array[Vector3] = []
	for Cell in Path:
		Points.append(CellPosition(Cell))
	if not Spawned:
		return Points
	var Up := -Gravity()
	if Up.dot(Model.OutwardAt(Path[0])) < ArrivalMinUpward:
		return Points
	Points.insert(0, Points[0] + Up * (ArrivalHeight + Depth) * Pitch)
	return Points


func PointsLength(Points: Array[Vector3]) -> float:
	var Total := 0.0
	for Index in range(1, Points.size()):
		Total += Points[Index].distance_to(Points[Index - 1])
	return Total


func AnimateMove(Piece: BoardModel.PieceData, Points: Array[Vector3], Speed: float) -> void:
	var Node: Node3D = PieceNodes.get(Piece.Id)
	var IsNew := Node == null
	if IsNew:
		Node = AddPieceNode(Piece, Points[0])
		Node.scale = Vector3.ONE * 0.7
	var Walk := create_tween()
	var Duration := PointsLength(Points) / Speed
	if Points.size() < 2:
		# Nothing to fall from: it grows where it is.
		Node.scale = Vector3.ONE * 0.01
		Duration = GrowTime
		Walk.tween_interval(GrowTime)
	for Index in range(1, Points.size()):
		Walk.tween_property(Node, "position", Points[Index], Points[Index].distance_to(Points[Index - 1]) / Speed)
	PendingTweens += 1
	Walk.finished.connect(OnMoveFinished.bind(Piece.Id))
	if IsNew:
		var Grow := create_tween()
		Grow.tween_property(Node, "scale", Vector3.ONE, Duration)


func OnMoveFinished(Id: int) -> void:
	MovingIds.erase(Id)
	RequestJoins()
	PendingTweens -= 1
	if PendingTweens <= 0:
		PendingTweens = 0
		FinishDrop()


## Brings the joins up to date once at the end of this frame. A join update walks every surface cell, and many pieces land in the
## same frame, so one update per landing piece (hundreds of cells each, on a big cube) made the game crawl, a debug build especially.
func RequestJoins() -> void:
	if JoinsQueued:
		return
	JoinsQueued = true
	call_deferred("RunQueuedJoins")


func RunQueuedJoins() -> void:
	JoinsQueued = false
	if Model != null:
		Joins.Update(MovingIds)


func FinishDrop() -> void:
	if Model.HasPlayableGroup():
		Busy = false
		return
	# In Attract Mode no group left to remove is the end of the game: the board stays as it is (busy) for `Main` to deal again.
	if AttractActive:
		NoPlayableGroups.emit()
		return
	AnnounceReshuffle()


# MARK: Shuffling

## No group left in a game: "No More Moves, Reshuffling" shows for a second (the board stays busy), then the shuffle happens.
func AnnounceReshuffle() -> void:
	NoMovesNotice = true
	var Shown := Model
	await get_tree().create_timer(1.0).timeout
	NoMovesNotice = false
	if Model == Shown and Model != null:
		Recover()


## No group of three left: shuffle what is there (up to three tries), then deal again.
func Recover() -> void:
	# If the cube is dealt again, the old pieces go in a puff of smoke (with Smoke chosen). Dealing replaces them in the model,
	# so their colors are noted before.
	var OldKinds: Dictionary = KindsById() if RemovalEffect == BoardView.RemovalEffects.Smoke else {}
	var Result := Model.Shuffle()
	if Result["Redealt"]:
		if RemovalEffect == BoardView.RemovalEffects.Smoke:
			var Old: Array[Dictionary] = []
			for Id in PieceNodes:
				var Node: Node3D = PieceNodes[Id]
				# Away from the middle of the cube: out of the face the piece is on.
				var Away := Node.global_position - global_position
				Old.append({"Node": Node, "Kind": OldKinds.get(Id, 0), "Out": Away.normalized() if Away.length() > 0.01 else Vector3.UP})
			SmokeBurst.Replace(Flyers, Old, Styles.Shown, RemovalSpeed, SmokeUp())
		else:
			for Id in PieceNodes:
				PieceNodes[Id].queue_free()
		PieceNodes.clear()
		for Cell in Model.SurfaceCells:
			var Piece := Model.GetPiece(Cell)
			if Piece != null:
				var Node := AddPieceNode(Piece, CellPosition(Cell))
				Node.scale = Vector3.ONE * 0.01
				create_tween().tween_property(Node, "scale", Vector3.ONE, 0.4)
		MovingIds.clear()
		Joins.Update(MovingIds)
		get_tree().create_timer(0.45).timeout.connect(func() -> void: Busy = false)
		return
	AnimateShuffle(Result["Moves"])


## The color of every piece on the cube, by piece id.
func KindsById() -> Dictionary:
	var Kinds: Dictionary = {}
	for Cell in Model.SurfaceCells:
		var Piece := Model.GetPiece(Cell)
		if Piece != null:
			Kinds[Piece.Id] = Piece.Kind
	return Kinds


## Every piece flies to its new cell in an arc out from the cube, turning once on the way and landing upright.
func AnimateShuffle(Moves: Array) -> void:
	PendingShuffles = 0
	# Every shuffling piece lets go of its joins while it flies; they all come back together once the shuffle has finished.
	for Move in Moves:
		MovingIds[Move["Piece"].Id] = true
	Joins.Update(MovingIds)
	for Move in Moves:
		var Node: Node3D = PieceNodes.get(Move["Piece"].Id)
		if Node == null:
			continue
		var Axis := Vector3(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)).normalized()
		var Out := Model.OutwardAt(Move["From"])
		var Flight := create_tween()
		PendingShuffles += 1
		Flight.tween_method(ShuffleStep.bind(Node, CellPosition(Move["From"]), CellPosition(Move["To"]), Axis, Out), 0.0, 1.0, ShuffleDuration) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		Flight.tween_callback(OnShuffleLanded.bind(Node))
	if PendingShuffles == 0:
		MovingIds.clear()
		Joins.Update(MovingIds)
		Busy = false


func ShuffleStep(Progress: float, Node: Node3D, Start: Vector3, End: Vector3, Axis: Vector3, Out: Vector3) -> void:
	if not is_instance_valid(Node):
		return
	Node.position = Start.lerp(End, Progress) + Out * ShuffleLift * sin(PI * Progress)
	Node.basis = Basis(Axis, TAU * Progress)


func OnShuffleLanded(Node: Node3D) -> void:
	if is_instance_valid(Node):
		Node.basis = Basis.IDENTITY
	PendingShuffles -= 1
	if PendingShuffles <= 0:
		PendingShuffles = 0
		MovingIds.clear()
		Joins.Update(MovingIds)
		Busy = false


## The Shuffle button: moves the pieces already on the cube to other cells (never recoloring them where they sit).
func ShuffleNow() -> void:
	if Busy or InputLocked or Model == null:
		return
	Busy = true
	Recover()
