class_name BoardView
extends BoardViewRemoval

## Shuffling, falling and refilling, and the per-frame step (this class; the rest is in the scripts it extends, in this order: BoardViewTurning, BoardViewBuild, BoardViewRemoval).

func _process(Delta: float) -> void:
	if Model != null:
		Hint.Tick(Delta, not Busy and not AttractActive and not InputLocked)
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


func StartDrop() -> void:
	Flyers.ClearOriginBlockers()
	if BlockersMove:
		RelocateBlockers()
	Model.GravityDir = GravityFromUser()
	var Moves := Model.Drop()
	if Moves.is_empty():
		FinishDrop()
		return
	# Every piece falls at the same speed - the longest drop takes `FallDuration` - so pieces that start touching
	# stay touching, and a shorter drop takes proportionally less time.
	var Longest := 0.0
	for Move in Moves:
		Longest = maxf(Longest, PathLength(Move["Path"]))
	var Speed := maxf(Longest, 1.0) / FallDuration
	for Move in Moves:
		MovingIds[Move["Piece"].Id] = true
	for Move in Moves:
		AnimateMove(Move["Piece"], Move["Path"], Speed)
	# Everything that is about to move lets go of its joins now; they come back as each piece lands.
	Joins.Update(MovingIds)
	if PendingTweens == 0:
		FinishDrop()


func PathLength(Path: Array) -> float:
	var Total := 0.0
	for Index in range(1, Path.size()):
		Total += Vector2(Path[Index] - Path[Index - 1]).length() * BlockStyles.Pitch
	return Total


func AnimateMove(Piece: BoardModel.PieceData, Path: Array, Speed: float) -> void:
	var Node: Node3D = PieceNodes.get(Piece.Id)
	var IsNew := Node == null
	if IsNew:
		Node = AddPieceNode(Piece, CellPosition(Path[0].x, Path[0].y))
		Node.scale = Vector3.ONE * 0.7
	var Walk := create_tween()
	for Index in range(1, Path.size()):
		var Step: Vector2i = Path[Index]
		var Length := Vector2(Path[Index] - Path[Index - 1]).length() * BlockStyles.Pitch
		Walk.tween_property(Node, "position", CellPosition(Step.x, Step.y), Length / Speed)
	PendingTweens += 1
	Walk.finished.connect(OnMoveFinished.bind(Piece.Id))
	if IsNew:
		var Grow := create_tween()
		Grow.tween_property(Node, "scale", Vector3.ONE, PathLength(Path) / Speed)


func OnMoveFinished(Id: int) -> void:
	MovingIds.erase(Id)
	Joins.Update(MovingIds)
	PendingTweens -= 1
	if PendingTweens <= 0:
		PendingTweens = 0
		FinishDrop()


func FinishDrop() -> void:
	if Model.HasPlayableGroup():
		Busy = false
		return
	# In Attract Mode no group left to remove is the end of the game: the board stays as it is (busy) for `Main` to deal again.
	if AttractActive:
		NoPlayableGroups.emit()
		return
	Recover()


# MARK: Shuffling

## No group of three left: shuffle what is there (up to three tries), then deal again.
func Recover() -> void:
	# If the board is dealt again, the old pieces go in a puff of smoke (with Smoke chosen). Dealing replaces them in the model,
	# so their colors are noted before.
	var OldKinds: Dictionary = KindsById() if RemovalEffect == RemovalEffects.Smoke else {}
	var Result := Model.Shuffle()
	if Result["Redealt"]:
		if RemovalEffect == RemovalEffects.Smoke:
			var Old: Array[Dictionary] = []
			var Front := SmokeFront()
			for Id in PieceNodes:
				Old.append({"Node": PieceNodes[Id], "Kind": OldKinds.get(Id, 0), "Out": Front})
			SmokeBurst.Replace(Flyers, Old, Styles.Shown, RemovalSpeed, SmokeUp())
		else:
			for Id in PieceNodes:
				PieceNodes[Id].queue_free()
		PieceNodes.clear()
		for Col in Model.Width:
			for Row in Model.Height:
				var Piece := Model.GetPiece(Col, Row)
				if Piece != null:
					var Node := AddPieceNode(Piece, CellPosition(Col, Row))
					Node.scale = Vector3.ONE * 0.01
					create_tween().tween_property(Node, "scale", Vector3.ONE, 0.4)
		MovingIds.clear()
		Joins.Update(MovingIds)
		get_tree().create_timer(0.45).timeout.connect(func() -> void: Busy = false)
		return
	AnimateShuffle(Result["Moves"])


## The color of every piece on the board, by piece id.
func KindsById() -> Dictionary:
	var Kinds: Dictionary = {}
	for Col in Model.Width:
		for Row in Model.Height:
			var Piece := Model.GetPiece(Col, Row)
			if Piece != null:
				Kinds[Piece.Id] = Piece.Kind
	return Kinds


## Every piece flies to its new cell in an arc toward the camera, turning once on the way and landing upright.
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
		var To: Vector2i = Move["To"]
		var Axis := Vector3(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)).normalized()
		var Flight := create_tween()
		PendingShuffles += 1
		Flight.tween_method(ShuffleStep.bind(Node, Node.position, CellPosition(To.x, To.y), Axis), 0.0, 1.0, ShuffleDuration) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		Flight.tween_callback(OnShuffleLanded.bind(Node))
	if PendingShuffles == 0:
		MovingIds.clear()
		Joins.Update(MovingIds)
		Busy = false


func ShuffleStep(Progress: float, Node: Node3D, Start: Vector3, End: Vector3, Axis: Vector3) -> void:
	if not is_instance_valid(Node):
		return
	Node.position = Start.lerp(End, Progress) + Vector3(0, 0, ShuffleLift * sin(PI * Progress))
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


## The Shuffle button: moves the pieces already on the board to other cells (never recoloring them where they sit).
func ShuffleNow() -> void:
	if Busy or InputLocked or Model == null:
		return
	Busy = true
	Recover()
