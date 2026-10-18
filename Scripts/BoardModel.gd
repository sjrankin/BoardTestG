class_name BoardModel
extends RefCounted
## The rules of the 2D board, with no nodes and no rendering - a port of BoardTestRK's `BoardModel`.
## See ../BoardTestRK/BoardTestRKRules.md: groups of 3+ same-colored pieces clear, the rest fall (straight down,
## and diagonally only around Blockers), and every gap is refilled from above.
##
## Cells are addressed (Col, Row), Row 0 at the top. `Cells` also holds `Pad` rows above the board (Row < 0) where
## new pieces queue before falling in.

const MinimumGroupSize := 3
const Neighbors: Array[Vector2i] = [Vector2i(0, -1), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(1, 0)]
const MaxRounds := 20
const MaxShuffleAttempts := 3
const MaxDealAttempts := 200


class PieceData:
	extends RefCounted
	var Id: int
	var Kind: int

	func _init(NewId: int, NewKind: int) -> void:
		Id = NewId
		Kind = NewKind


var Width: int
var Height: int
var ColorCount: int
var BlockerCount: int
var Score: int = 0
var Rng := RandomNumberGenerator.new()
var Pad: int
## Cells[Col][Row + Pad] -> PieceData or null.
var Cells: Array = []
## Blockers[Col][Row] -> bool. Placed once; never moved by a shuffle or a redeal.
var Blockers: Array = []
var NextId: int = 1
## Which side a piece tries first when it can go either way at a cell; flips each time it is used.
var FlipToggles: Dictionary = {}
## Piece id -> the cells it passes through during the current `Drop` (first entry is where it started).
var Paths: Dictionary = {}
var PathPieces: Dictionary = {}


func _init(NewWidth: int, NewHeight: int, NewColorCount: int, NewBlockerCount: int, Seed: int = 0) -> void:
	Width = maxi(NewWidth, 3)
	Height = maxi(NewHeight, 3)
	ColorCount = clampi(NewColorCount, 3, 8)
	BlockerCount = maxi(NewBlockerCount, 0)
	Pad = Height
	if Seed != 0:
		Rng.seed = Seed
	else:
		Rng.randomize()
	PlaceBlockers()
	Deal()


# MARK: Cell access

func InColumns(Col: int) -> bool:
	return Col >= 0 and Col < Width


func GetPiece(Col: int, Row: int) -> PieceData:
	if not InColumns(Col) or Row < -Pad or Row >= Height:
		return null
	return Cells[Col][Row + Pad]


func SetPiece(Col: int, Row: int, Piece: PieceData) -> void:
	Cells[Col][Row + Pad] = Piece


func IsBlocker(Col: int, Row: int) -> bool:
	if not InColumns(Col) or Row < 0 or Row >= Height:
		return false
	return Blockers[Col][Row]


## A cell a piece could move into right now: on the board or in the queue above it, not a Blocker, and empty.
func CanEnter(Col: int, Row: int) -> bool:
	if not InColumns(Col) or Row < -Pad or Row >= Height:
		return false
	return not IsBlocker(Col, Row) and GetPiece(Col, Row) == null


## Whether a Blocker sits at or above `Row` in the column, so nothing can ever be refilled into that cell from above.
func ColumnSealed(Col: int, Row: int) -> bool:
	for K in range(0, mini(Row, Height - 1) + 1):
		if IsBlocker(Col, K):
			return true
	return false


func NewPiece(Kind: int) -> PieceData:
	var Piece := PieceData.new(NextId, Kind)
	NextId += 1
	return Piece


func RandomKind() -> int:
	return Rng.randi_range(0, ColorCount - 1)


func ClearCells() -> void:
	Cells = []
	for Col in Width:
		var Column: Array = []
		Column.resize(Height + Pad)
		Cells.append(Column)


# MARK: Setup

## Places up to `BlockerCount` Blockers at random, only where the remaining cells stay one connected region.
func PlaceBlockers() -> void:
	Blockers = []
	for Col in Width:
		var Column: Array = []
		Column.resize(Height)
		Column.fill(false)
		Blockers.append(Column)
	var Placed := 0
	var Tries := 0
	while Placed < BlockerCount and Tries < 500:
		Tries += 1
		var Col := Rng.randi_range(0, Width - 1)
		var Row := Rng.randi_range(0, Height - 1)
		if Blockers[Col][Row]:
			continue
		Blockers[Col][Row] = true
		if OpenCellsConnected():
			Placed += 1
		else:
			Blockers[Col][Row] = false


func OpenCellsConnected() -> bool:
	var Start := Vector2i(-1, -1)
	var OpenCount := 0
	for Col in Width:
		for Row in Height:
			if not Blockers[Col][Row]:
				OpenCount += 1
				if Start.x < 0:
					Start = Vector2i(Col, Row)
	if OpenCount == 0:
		return false
	var Seen := {Start: true}
	var Stack: Array[Vector2i] = [Start]
	while not Stack.is_empty():
		var Cell: Vector2i = Stack.pop_back()
		for Offset in Neighbors:
			var Next := Cell + Offset
			if Next.x < 0 or Next.x >= Width or Next.y < 0 or Next.y >= Height:
				continue
			if Blockers[Next.x][Next.y] or Seen.has(Next):
				continue
			Seen[Next] = true
			Stack.append(Next)
	return Seen.size() == OpenCount


## Fills every open cell with a random piece, retrying until the deal has at least one playable group.
func Deal() -> void:
	for Attempt in MaxDealAttempts:
		FillRandom()
		if HasPlayableGroup():
			return
	ForceGroup()


func FillRandom() -> void:
	ClearCells()
	for Col in Width:
		for Row in Height:
			if not Blockers[Col][Row]:
				SetPiece(Col, Row, NewPiece(RandomKind()))


## Last resort for a board too small or too blocked for a random deal to contain a group: paint three in a row.
func ForceGroup() -> void:
	for Row in Height:
		for Col in range(0, Width - 2):
			if Blockers[Col][Row] or Blockers[Col + 1][Row] or Blockers[Col + 2][Row]:
				continue
			var Kind := RandomKind()
			for Offset in 3:
				SetPiece(Col + Offset, Row, NewPiece(Kind))
			return


# MARK: Groups

## The group of same-kind pieces touching (Col, Row) along a side, or empty if there is no piece there.
func GroupAt(Col: int, Row: int) -> Array[Vector2i]:
	var Result: Array[Vector2i] = []
	var Start := GetPiece(Col, Row)
	if Start == null or Row < 0:
		return Result
	var Seen := {Vector2i(Col, Row): true}
	var Stack: Array[Vector2i] = [Vector2i(Col, Row)]
	while not Stack.is_empty():
		var Cell: Vector2i = Stack.pop_back()
		Result.append(Cell)
		for Offset in Neighbors:
			var Next := Cell + Offset
			if Next.y < 0 or Seen.has(Next):
				continue
			var Other := GetPiece(Next.x, Next.y)
			if Other != null and Other.Kind == Start.Kind:
				Seen[Next] = true
				Stack.append(Next)
	return Result


## Every group on the board, each an array of cells.
func FindGroups() -> Array:
	var Groups: Array = []
	var Seen := {}
	for Col in Width:
		for Row in Height:
			var Cell := Vector2i(Col, Row)
			if Seen.has(Cell) or GetPiece(Col, Row) == null:
				continue
			var Group := GroupAt(Col, Row)
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
func Remove(Group: Array[Vector2i]) -> Array:
	var Removed: Array = []
	if Group.size() < MinimumGroupSize:
		return Removed
	for Cell in Group:
		var Piece := GetPiece(Cell.x, Cell.y)
		if Piece == null:
			continue
		Removed.append({"Cell": Cell, "Piece": Piece})
		SetPiece(Cell.x, Cell.y, null)
	Score += Removed.size()
	return Removed


# MARK: Gravity and refill

func RecordMove(Piece: PieceData, From: Vector2i, To: Vector2i) -> void:
	if not Paths.has(Piece.Id):
		Paths[Piece.Id] = [From]
		PathPieces[Piece.Id] = Piece
	Paths[Piece.Id].append(To)


func MovePiece(Piece: PieceData, From: Vector2i, To: Vector2i) -> void:
	SetPiece(From.x, From.y, null)
	SetPiece(To.x, To.y, Piece)
	RecordMove(Piece, From, To)


## One piece's move, if it has one: straight down if the cell below is open; otherwise diagonally, but only when a
## Blocker is directly below it or the cell it would enter is in a column nothing can be refilled into from above.
func TryMove(Piece: PieceData, Col: int, Row: int) -> bool:
	if CanEnter(Col, Row + 1):
		MovePiece(Piece, Vector2i(Col, Row), Vector2i(Col, Row + 1))
		return true
	if Row < 0:
		return false
	var BlockerBelow := IsBlocker(Col, Row + 1)
	var Key := Vector2i(Col, Row)
	var Flip: bool = FlipToggles.get(Key, false)
	var Sides: Array = [1, -1] if Flip else [-1, 1]
	for Side in Sides:
		var TargetCol: int = Col + Side
		if not CanEnter(TargetCol, Row + 1):
			continue
		if BlockerBelow or ColumnSealed(TargetCol, Row + 1):
			FlipToggles[Key] = not Flip
			MovePiece(Piece, Key, Vector2i(TargetCol, Row + 1))
			return true
	return false


## Gravity, one row at a time from the bottom, repeated until a full pass moves nothing. Returns how many moves.
func Settle() -> int:
	var MoveCount := 0
	var Changed := true
	while Changed:
		Changed = false
		for Row in range(Height - 2, -Pad - 1, -1):
			for Col in Width:
				var Piece := GetPiece(Col, Row)
				if Piece != null and TryMove(Piece, Col, Row):
					Changed = true
					MoveCount += 1
	return MoveCount


## New pieces queue above each column, one per open cell that can be refilled from above. A column with a
## Blocker on row 0 gets none. Returns how many pieces were created.
func SpawnAbove() -> int:
	var Spawned := 0
	for Col in Width:
		var Needed := 0
		for Row in Height:
			if not ColumnSealed(Col, Row) and GetPiece(Col, Row) == null:
				Needed += 1
		Needed = mini(Needed, Pad)
		for Index in Needed:
			var Piece := NewPiece(RandomKind())
			var Cell := Vector2i(Col, -1 - Index)
			SetPiece(Cell.x, Cell.y, Piece)
			Paths[Piece.Id] = [Cell]
			PathPieces[Piece.Id] = Piece
			Spawned += 1
	return Spawned


## Removes any piece still queued above the board once everything has settled. Spawning counts each column's open cells
## up front, and a piece resting on a Blocker can step sideways into a neighboring column's gap, so a column can be
## sent one piece more than it has room for. That extra piece never reaches the board.
func DiscardQueued() -> void:
	for Col in Width:
		for Row in range(-Pad, 0):
			var Piece := GetPiece(Col, Row)
			if Piece != null:
				SetPiece(Col, Row, null)
				Paths.erase(Piece.Id)
				PathPieces.erase(Piece.Id)


## Closes every gap: existing pieces fall, new ones queue above and fall in, until nothing more moves. Returns
## [{Piece, Path: Array[Vector2i]}] for every piece that moved or was created (a new piece's path starts above the board).
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

## Shuffles the existing pieces among their cells (up to 3 tries), then deals fresh pieces if none of those tries
## has a playable group. Returns {Redealt: bool, Moves: [{Piece, From, To}]} - `Moves` is empty after a redeal.
func Shuffle() -> Dictionary:
	var OpenCells: Array[Vector2i] = []
	var Pieces: Array = []
	for Col in Width:
		for Row in Height:
			var Piece := GetPiece(Col, Row)
			if Piece != null:
				OpenCells.append(Vector2i(Col, Row))
				Pieces.append(Piece)
	for Attempt in MaxShuffleAttempts:
		var Order: Array = Pieces.duplicate()
		Order.shuffle()
		for Index in OpenCells.size():
			SetPiece(OpenCells[Index].x, OpenCells[Index].y, Order[Index])
		if HasPlayableGroup():
			var Moves: Array = []
			for Index in OpenCells.size():
				var Source := Pieces.find(Order[Index])
				Moves.append({"Piece": Order[Index], "From": OpenCells[Source], "To": OpenCells[Index]})
			return {"Redealt": false, "Moves": Moves}
	Deal()
	return {"Redealt": true, "Moves": []}
