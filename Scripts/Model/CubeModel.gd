class_name CubeModel
extends RefCounted
## The rules of the 3D cube, with no nodes and no rendering - from BoardTestRK's cube shape (see ../BoardTestRK/BoardTestRKRules.md).
##
## The cube is a hollow box Width x Height x Depth cells. Only its surface holds pieces: six boards, one per face, that share their
## edge and corner cells - a piece on an edge belongs to two boards, a corner piece to three. Here that is one piece per surface cell
## (`Cells`, keyed by the cell), so shared pieces are the same colour on every board by construction, and a removal on one side is
## seen on the other.
##
## Cells are (X, Y, Z): X to the right, Y up, Z toward the front. Gravity is the real, world one (down on screen, however the cube is
## turned), given to `Drop` in the cube's own space. A piece falls to the neighbouring surface cell that is most downhill, if that is
## downhill enough (`SlopeMin`) - so it runs down a face, round an edge and onto the next face, and rests on a level face (the floor).
## A gap is filled by the piece above it falling in; a gap at the top (a cell that faces the sky and has nothing above it, whatever is
## turned up) is filled by a new piece that falls in from the sky; a gap neither can reach (a level underside) is filled by a piece
## sliding in along the surface, and the gap that leaves is filled from the top. (Each face is still a grid of (Col, Row) - `FaceCell` - for counting
## and for tests.) There are no Blockers, and nothing ever moves sideways except downhill.
##
## A group is same-coloured pieces that touch along a side; groups reach across edges, and a shared piece counts once.

## The same piece record the 2D board uses.
const PieceData := BoardModel.PieceData
const MinimumGroupSize := 3
const MaxRounds := 400
## A neighbouring cell is downhill enough to fall to when its direction's alignment with gravity is above this (about 20 degrees off level).
const SlopeMin := 0.35
## A cell faces the sky when its outward direction's alignment with up is at least this (about 78 degrees from level).
const SkyMin := 0.2
## A tiny tilt added to gravity when sliding along level surfaces, so there is always one way along a level face (never a tie).
const SlideTilt := Vector3(0.0123, 0.0071, 0.0097)
const MaxShuffleAttempts := 3
const MaxDealAttempts := 200
const DimensionRange := Vector2i(3, 15)
const Neighbors: Array[Vector3i] = [Vector3i(1, 0, 0), Vector3i(-1, 0, 0), Vector3i(0, 1, 0), Vector3i(0, -1, 0), Vector3i(0, 0, 1), Vector3i(0, 0, -1)]

enum Faces { Front, Back, Left, Right, Top, Bottom }
const FaceNames: Array[String] = ["Front", "Back", "Left", "Right", "Top", "Bottom"]
## Each face's outward direction.
const FaceNormals: Array[Vector3i] = [Vector3i(0, 0, 1), Vector3i(0, 0, -1), Vector3i(-1, 0, 0), Vector3i(1, 0, 0), Vector3i(0, 1, 0), Vector3i(0, -1, 0)]

var Width: int
var Height: int
var Depth: int
var ColorCount: int
var Score: int = 0
var Rng := RandomNumberGenerator.new()
## Surface cell -> PieceData. A cell with no entry is empty.
var Cells: Dictionary = {}
## Every surface cell.
var SurfaceCells: Array[Vector3i] = []
var NextId: int = 1
## Piece id -> the cells it passes through during the current `Drop` (the first entry is where it started).
var Paths: Dictionary = {}
var PathPieces: Dictionary = {}
## Piece id -> how many spawn rounds in it was created (so a view can stagger pieces falling in from the sky one behind another).
var SpawnDepths: Dictionary = {}


func _init(NewWidth: int, NewHeight: int, NewDepth: int, NewColorCount: int, Seed: int = 0) -> void:
	Width = clampi(NewWidth, DimensionRange.x, DimensionRange.y)
	Height = clampi(NewHeight, DimensionRange.x, DimensionRange.y)
	Depth = clampi(NewDepth, DimensionRange.x, DimensionRange.y)
	ColorCount = clampi(NewColorCount, 3, 8)
	if Seed != 0:
		Rng.seed = Seed
	else:
		Rng.randomize()
	for X in Width:
		for Y in Height:
			for Z in Depth:
				if IsSurface(Vector3i(X, Y, Z)):
					SurfaceCells.append(Vector3i(X, Y, Z))
	Deal()


# MARK: Cells and faces

func IsSurface(Cell: Vector3i) -> bool:
	if Cell.x < 0 or Cell.x >= Width or Cell.y < 0 or Cell.y >= Height or Cell.z < 0 or Cell.z >= Depth:
		return false
	return Cell.x == 0 or Cell.x == Width - 1 or Cell.y == 0 or Cell.y == Height - 1 or Cell.z == 0 or Cell.z == Depth - 1


func GetPiece(Cell: Vector3i) -> PieceData:
	return Cells.get(Cell)


func SetPiece(Cell: Vector3i, Piece: PieceData) -> void:
	if Piece == null:
		Cells.erase(Cell)
	else:
		Cells[Cell] = Piece


## Whether a cell lies on a face's plane (so it is one of that face's cells; edge cells lie on two faces, corners on three).
func OnFace(Cell: Vector3i, Face: int) -> bool:
	match Face:
		Faces.Front:
			return Cell.z == Depth - 1
		Faces.Back:
			return Cell.z == 0
		Faces.Left:
			return Cell.x == 0
		Faces.Right:
			return Cell.x == Width - 1
		Faces.Top:
			return Cell.y == Height - 1
	return Cell.y == 0


## The direction a piece leaves a cell: out of the one face it is on, or out between the faces (normalized) for an edge or corner.
func OutwardAt(Cell: Vector3i) -> Vector3:
	var Sum := Vector3.ZERO
	for Face in 6:
		if OnFace(Cell, Face):
			Sum += Vector3(FaceNormals[Face])
	return Sum.normalized() if Sum != Vector3.ZERO else Vector3.BACK


## How many columns a face's board has, and how many rows.
func FaceCols(Face: int) -> int:
	return Depth if Face == Faces.Left or Face == Faces.Right else Width


func FaceRows(Face: int) -> int:
	return Depth if Face == Faces.Top or Face == Faces.Bottom else Height


## The cell at (Col, Row) of a face's board. Row 0 is the side pieces enter from; a negative row (a queued piece) is a cell just off
## the face, and a row past the last one is just beyond its far edge.
func FaceCell(Face: int, Col: int, Row: int) -> Vector3i:
	match Face:
		Faces.Front:
			return Vector3i(Col, Height - 1 - Row, Depth - 1)
		Faces.Back:
			return Vector3i(Width - 1 - Col, Height - 1 - Row, 0)
		Faces.Left:
			return Vector3i(0, Height - 1 - Row, Col)
		Faces.Right:
			return Vector3i(Width - 1, Height - 1 - Row, Depth - 1 - Col)
		Faces.Top:
			return Vector3i(Col, Height - 1, Row)
	return Vector3i(Col, 0, Depth - 1 - Row)


func FaceHasCell(Face: int, Cell: Vector3i) -> bool:
	return IsSurface(Cell) and OnFace(Cell, Face)


## The pieces on one face's board.
func PieceCountOnFace(Face: int) -> int:
	var Total := 0
	for Cell in Cells:
		if OnFace(Cell, Face):
			Total += 1
	return Total


# MARK: Making pieces

func NewPiece(Kind: int) -> PieceData:
	var Piece := BoardModel.PieceData.new(NextId, Kind)
	NextId += 1
	return Piece


func RandomKind() -> int:
	return Rng.randi_range(0, ColorCount - 1)


# MARK: Setup

## Fills every cell with a random piece, retrying until the deal has at least one playable group.
func Deal() -> void:
	for Attempt in MaxDealAttempts:
		FillRandom()
		if HasPlayableGroup():
			return
	ForceGroup()


func FillRandom() -> void:
	Cells.clear()
	for Cell in SurfaceCells:
		SetPiece(Cell, NewPiece(RandomKind()))


## Last resort for a deal with no group: paint three in a row along the top.
func ForceGroup() -> void:
	var Kind := RandomKind()
	for X in 3:
		SetPiece(Vector3i(X, Height - 1, 1), NewPiece(Kind))


# MARK: Groups

## The group of same-coloured pieces touching `Start` along a side (across edges too), or empty if there is no piece there.
func GroupAt(Start: Vector3i) -> Array[Vector3i]:
	var Result: Array[Vector3i] = []
	var First := GetPiece(Start)
	if First == null:
		return Result
	var Seen := {Start: true}
	var Stack: Array[Vector3i] = [Start]
	while not Stack.is_empty():
		var Cell: Vector3i = Stack.pop_back()
		Result.append(Cell)
		for Offset in Neighbors:
			var Next := Cell + Offset
			if Seen.has(Next):
				continue
			var Other := GetPiece(Next)
			if Other != null and Other.Kind == First.Kind:
				Seen[Next] = true
				Stack.append(Next)
	return Result


func FindGroups() -> Array:
	var Groups: Array = []
	var Seen := {}
	for Cell in SurfaceCells:
		if Seen.has(Cell) or GetPiece(Cell) == null:
			continue
		var Group := GroupAt(Cell)
		for Member in Group:
			Seen[Member] = true
		Groups.append(Group)
	return Groups


func PlayableGroups() -> Array:
	return FindGroups().filter(func(Group: Array) -> bool: return Group.size() >= MinimumGroupSize)


func HasPlayableGroup() -> bool:
	return not PlayableGroups().is_empty()


# MARK: Removal

## Clears a group (3+ pieces only). Returns [{Cell, Piece}] for each piece taken off, or [] if it was too small.
func Remove(Group: Array[Vector3i]) -> Array:
	var Removed: Array = []
	if Group.size() < MinimumGroupSize:
		return Removed
	for Cell in Group:
		var Piece := GetPiece(Cell)
		if Piece == null:
			continue
		Removed.append({"Cell": Cell, "Piece": Piece})
		SetPiece(Cell, null)
	Score += Removed.size()
	return Removed


# MARK: Gravity and refill

func RecordMove(Piece: PieceData, From: Vector3i, To: Vector3i) -> void:
	if not Paths.has(Piece.Id):
		Paths[Piece.Id] = [From]
		PathPieces[Piece.Id] = Piece
	Paths[Piece.Id].append(To)


## For each surface cell, the neighbouring surface cells a piece could fall into it from, best first: those whose way to the cell is
## more than `SlopeMin` aligned with gravity `Down` (a direction in the cube's space). A cell with none is as high as it gets (the top
## of the cube, or a level face), and nothing can fall into it. Falling always goes to a lower cell, so it cannot go round in a circle.
func BuildFeeders(Down: Vector3) -> Dictionary:
	var Feeders := {}
	for Cell in SurfaceCells:
		var Options: Array = []
		for Offset in Neighbors:
			var Alignment := Vector3(Offset).dot(Down)
			if Alignment > SlopeMin and IsSurface(Cell - Offset):
				Options.append([Alignment, Cell - Offset])
		Options.sort_custom(func(A: Array, B: Array) -> bool: return A[0] > B[0])
		Feeders[Cell] = Options.map(func(Option: Array) -> Vector3i: return Option[1])
	return Feeders


## Whether a cell faces the sky: its outward direction (between the faces, for an edge or corner) looks up at least this much, so a
## new piece can fall onto it from above. `Up` is the way up in the cube's space.
func IsExposed(Cell: Vector3i, Up: Vector3) -> bool:
	return Up.dot(OutwardAt(Cell)) >= SkyMin


## Every empty cell takes the piece that can fall into it from above (the best of its feeders), lowest cells first so a whole column
## drops in one pass, until a pass moves nothing. `Order` is the surface cells lowest first. Returns how many moves it made.
func Settle(Feeders: Dictionary, Order: Array[Vector3i]) -> int:
	var MoveCount := 0
	var Changed := true
	while Changed:
		Changed = false
		for Cell in Order:
			if Cells.has(Cell):
				continue
			for Source in Feeders[Cell]:
				var Piece := GetPiece(Source)
				if Piece == null:
					continue
				SetPiece(Source, null)
				SetPiece(Cell, Piece)
				RecordMove(Piece, Source, Cell)
				Changed = true
				MoveCount += 1
				break
	return MoveCount


## A new piece in every empty top cell - one that faces the sky and has nothing above it to fall from - so new pieces enter only at the
## top, however the cube is turned. It starts there and falls on from it. `Round` counts the spawn rounds so far. Returns how many.
func SpawnAtSources(Sources: Array[Vector3i], Round: int) -> int:
	var Spawned := 0
	for Cell in Sources:
		if Cells.has(Cell):
			continue
		var Piece := NewPiece(RandomKind())
		SetPiece(Cell, Piece)
		Paths[Piece.Id] = [Cell]
		PathPieces[Piece.Id] = Piece
		SpawnDepths[Piece.Id] = Round
		Spawned += 1
	return Spawned


## What is left once falling and the top are done: a gap that nothing can fall into and that does not face the sky (a level underside,
## say) is filled by a piece that slides in along the surface from a neighbour that is not lower than it - never uphill, and never
## out of or into a cell facing the sky. That leaves a gap behind, which falling then fills from the top. Each cell moves at most
## once a pass. Returns how many moves it made.
func SlideIntoGaps(Down: Vector3, Up: Vector3) -> int:
	var Weak := (Down + SlideTilt).normalized()
	var Taken := {}
	var MoveCount := 0
	for Cell in SurfaceCells:
		if Cells.has(Cell) or Taken.has(Cell) or IsExposed(Cell, Up):
			continue
		var BestAlignment := 0.0
		var Best := Vector3i.ZERO
		for Offset in Neighbors:
			var Source := Cell - Offset
			if not IsSurface(Source) or Taken.has(Source) or not Cells.has(Source) or IsExposed(Source, Up):
				continue
			var Alignment := Vector3(Offset).dot(Weak)
			if Alignment > BestAlignment:
				BestAlignment = Alignment
				Best = Source
		if BestAlignment <= 0.0:
			continue
		var Piece := GetPiece(Best)
		SetPiece(Best, null)
		SetPiece(Cell, Piece)
		RecordMove(Piece, Best, Cell)
		Taken[Cell] = true
		Taken[Best] = true
		MoveCount += 1
	return MoveCount


## Closes every gap under `Gravity` (a direction in the cube's own space, default straight down): pieces fall into the gaps below
## them, new pieces fall in at the top (the cells that face the sky and have nothing above them), and a gap neither can reach is
## filled by a piece sliding in along the surface, until the surface is full. Returns [{Piece, Path: Array[Vector3i], Spawned: bool,
## Depth: int}] for every piece that moved or was created; a new piece's path starts at the cell it was created in (a view draws it
## falling in from above that cell, or growing there if that cell does not face the sky), and `Depth` says how many rounds in it was
## created.
func Drop(Gravity: Vector3 = Vector3.DOWN) -> Array:
	Paths.clear()
	PathPieces.clear()
	SpawnDepths.clear()
	var Down := Gravity.normalized()
	var Up := -Down
	var Feeders := BuildFeeders(Down)
	var Sources: Array[Vector3i] = []
	for Cell in SurfaceCells:
		if Feeders[Cell].is_empty() and IsExposed(Cell, Up):
			Sources.append(Cell)
	var Order: Array[Vector3i] = SurfaceCells.duplicate()
	Order.sort_custom(func(A: Vector3i, B: Vector3i) -> bool: return Vector3(A).dot(Down) > Vector3(B).dot(Down))
	var SpawnRound := 0
	for Round in MaxRounds:
		var Moved := Settle(Feeders, Order)
		var Spawned := SpawnAtSources(Sources, SpawnRound)
		if Spawned > 0:
			SpawnRound += 1
		if Moved > 0 or Spawned > 0:
			continue
		if SlideIntoGaps(Down, Up) == 0:
			break
	# A gap that nothing could reach at all (no neighbour to slide in from): a piece grows there.
	SpawnAtSources(SurfaceCells, 0)
	var Result: Array = []
	for Id in Paths:
		Result.append({"Piece": PathPieces[Id], "Path": Paths[Id], "Spawned": SpawnDepths.has(Id), "Depth": SpawnDepths.get(Id, 0)})
	return Result


# MARK: No moves

## Shuffles the pieces among their cells (up to 3 tries), then deals fresh ones if none of those tries has a playable group.
## Returns {Redealt: bool, Moves: [{Piece, From, To}]} - `Moves` is empty after a redeal.
func Shuffle() -> Dictionary:
	var OpenCells: Array[Vector3i] = []
	var Pieces: Array = []
	for Cell in SurfaceCells:
		var Piece := GetPiece(Cell)
		if Piece != null:
			OpenCells.append(Cell)
			Pieces.append(Piece)
	for Attempt in MaxShuffleAttempts:
		var Order: Array = Pieces.duplicate()
		Order.shuffle()
		for Index in OpenCells.size():
			SetPiece(OpenCells[Index], Order[Index])
		if HasPlayableGroup():
			var Moves: Array = []
			for Index in OpenCells.size():
				var Source := Pieces.find(Order[Index])
				Moves.append({"Piece": Order[Index], "From": OpenCells[Source], "To": OpenCells[Index]})
			return {"Redealt": false, "Moves": Moves}
	Deal()
	return {"Redealt": true, "Moves": []}
