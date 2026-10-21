class_name CubeModel
extends RefCounted
## The rules of the 3D cube, with no nodes and no rendering - from BoardTestRK's cube shape (see ../BoardTestRK/BoardTestRKRules.md).
##
## The cube is a hollow box Width x Height x Depth cells. Only its surface holds pieces: six boards, one per face, that share their
## edge and corner cells - a piece on an edge belongs to two boards, a corner piece to three. Here that is one piece per surface cell
## (`Cells`, keyed by the cell), so shared pieces are the same colour on every board by construction, and a removal on one side is
## seen on the other.
##
## Cells are (X, Y, Z): X to the right, Y up, Z toward the front. Each face is also a grid of (Col, Row) - `FaceCell` maps it to a
## cell - with pieces flowing toward higher rows (the face's own gravity, fixed by the face and not by how the cube is turned):
## Front, Back, Left and Right flow down, Top flows toward the front (+Z), Bottom toward the back (-Z). Pieces never move sideways (the
## cube has no Blockers). New pieces queue off the face, before row 0, in `Queue` - keyed (Face, Col, Row < 0).
##
## A group is same-coloured pieces that touch along a side; groups reach across edges, and a shared piece counts once.

## The same piece record the 2D board uses.
const PieceData := BoardModel.PieceData
const MinimumGroupSize := 3
const MaxRounds := 60
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
## The longest a column can be, and so how far off a face a queued piece can wait.
var Pad: int
## Surface cell -> PieceData. A cell with no entry is empty.
var Cells: Dictionary = {}
## Every surface cell.
var SurfaceCells: Array[Vector3i] = []
## New pieces waiting off a face: Vector3i(Face, Col, Row < 0) -> PieceData.
var Queue: Dictionary = {}
var NextId: int = 1
## Piece id -> the cells it passes through during the current `Drop` (the first entry is where it started).
var Paths: Dictionary = {}
var PathPieces: Dictionary = {}


func _init(NewWidth: int, NewHeight: int, NewDepth: int, NewColorCount: int, Seed: int = 0) -> void:
	Width = clampi(NewWidth, DimensionRange.x, DimensionRange.y)
	Height = clampi(NewHeight, DimensionRange.x, DimensionRange.y)
	Depth = clampi(NewDepth, DimensionRange.x, DimensionRange.y)
	ColorCount = clampi(NewColorCount, 3, 8)
	Pad = maxi(Width, maxi(Height, Depth))
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


# MARK: Virtual cells (a face's board, with its queue above row 0)

func FGet(Face: int, Col: int, Row: int) -> PieceData:
	if Row < 0:
		return Queue.get(Vector3i(Face, Col, Row))
	return Cells.get(FaceCell(Face, Col, Row))


func FSet(Face: int, Col: int, Row: int, Piece: PieceData) -> void:
	if Row < 0:
		if Piece == null:
			Queue.erase(Vector3i(Face, Col, Row))
		else:
			Queue[Vector3i(Face, Col, Row)] = Piece
		return
	SetPiece(FaceCell(Face, Col, Row), Piece)


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
	Queue.clear()
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


## Every face closes its gaps: each piece with an open cell ahead of it on its face's board moves into it, until a full pass moves
## nothing. (A piece on an edge can move along either face it is on; it never goes back, since no face flows upward - Top and Bottom
## only move pieces along their own level - so this always ends.) Returns how many moves it made.
func Settle() -> int:
	var MoveCount := 0
	var Changed := true
	while Changed:
		Changed = false
		for Face in 6:
			for Row in range(FaceRows(Face) - 2, -Pad - 1, -1):
				for Col in FaceCols(Face):
					var Piece := FGet(Face, Col, Row)
					if Piece == null or FGet(Face, Col, Row + 1) != null:
						continue
					FSet(Face, Col, Row, null)
					FSet(Face, Col, Row + 1, Piece)
					RecordMove(Piece, FaceCell(Face, Col, Row), FaceCell(Face, Col, Row + 1))
					Changed = true
					MoveCount += 1
	return MoveCount


## New pieces queue off each face, one per open cell in a column that is not already covered by a queued piece. Returns how many
## were created. (A shared cell may be filled by the other face first; the extra piece then never enters and is discarded.)
func SpawnAbove() -> int:
	var Spawned := 0
	for Face in 6:
		for Col in FaceCols(Face):
			var Needed := 0
			for Row in FaceRows(Face):
				if FGet(Face, Col, Row) == null:
					Needed += 1
			for Index in Pad:
				if Queue.has(Vector3i(Face, Col, -1 - Index)):
					Needed -= 1
			for Index in Pad:
				if Needed <= 0:
					break
				if Queue.has(Vector3i(Face, Col, -1 - Index)):
					continue
				var Piece := NewPiece(RandomKind())
				FSet(Face, Col, -1 - Index, Piece)
				Paths[Piece.Id] = [FaceCell(Face, Col, -1 - Index)]
				PathPieces[Piece.Id] = Piece
				Needed -= 1
				Spawned += 1
	return Spawned


## Removes any piece still queued off a face once everything has settled (it had no room to enter).
func DiscardQueued() -> void:
	for Key in Queue.keys():
		var Piece: PieceData = Queue[Key]
		Paths.erase(Piece.Id)
		PathPieces.erase(Piece.Id)
	Queue.clear()


## Closes every gap: existing pieces move along their faces, new ones queue off the faces and flow in, until nothing more moves.
## Returns [{Piece, Path: Array[Vector3i]}] for every piece that moved or was created; a new piece's path starts off the cube.
func Drop() -> Array:
	Paths.clear()
	PathPieces.clear()
	for Round in MaxRounds:
		var Moved := Settle()
		var Spawned := SpawnAbove()
		if Moved == 0 and Spawned == 0:
			break
	DiscardQueued()
	var Result: Array = []
	for Id in Paths:
		Result.append({"Piece": PathPieces[Id], "Path": Paths[Id]})
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
