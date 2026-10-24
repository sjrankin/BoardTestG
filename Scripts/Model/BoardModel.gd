class_name BoardModel
extends RefCounted
## The rules of the 2D board, with no nodes and no rendering - a port of BoardTestRK's `BoardModel`.
## See ../BoardTestRK/BoardTestRKRules.md: groups of 3+ same-colored pieces clear, the rest fall (straight down,
## and diagonally only around Blockers), and every gap is refilled from above.
##
## Cells are addressed (Col, Row), Row 0 at the top. Gravity can point any of four ways (`GravityDir`) - it is down as
## the user sees the board, however it is turned - so everything about falling is worked out in a "virtual" frame in which
## gravity always points toward increasing virtual rows (`ToReal` maps a virtual cell to a real one). New pieces queue
## in `Queue` at virtual rows above the board (VRow < 0) before falling in.

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
## Cells[Col][Row] -> PieceData or null.
var Cells: Array = []
## Which way pieces fall, in real cell steps: (0, 1) is toward higher rows (down the board), (0, -1) up, (1, 0) toward
## higher columns, (-1, 0) toward lower ones. Set before a drop.
var GravityDir: Vector2i = Vector2i(0, 1)
## New pieces waiting off the board: Vector2i(VCol, VRow < 0) -> PieceData.
var Queue: Dictionary = {}
## Blockers[Col][Row] -> bool. Placed once; never moved by a shuffle or a redeal.
var Blockers: Array = []
var NextId: int = 1
## Which side a piece tries first when it can go either way at a cell; flips each time it is used.
var FlipToggles: Dictionary = {}
## Piece id -> the cells it passes through during the current `Drop` (first entry is where it started).
var Paths: Dictionary = {}
var PathPieces: Dictionary = {}


func _init(NewWidth: int, NewHeight: int, NewColorCount: int, NewBlockerCount: int, Seed: int = 0, Preset: Array[Vector3i] = []) -> void:
	Width = maxi(NewWidth, 3)
	Height = maxi(NewHeight, 3)
	ColorCount = clampi(NewColorCount, 3, 8)
	BlockerCount = maxi(NewBlockerCount, 0)
	Pad = maxi(Width, Height)
	if Seed != 0:
		Rng.seed = Seed
	else:
		Rng.randomize()
	PlaceBlockers(Preset)
	Deal()


# MARK: Cell access

func InBoard(Col: int, Row: int) -> bool:
	return Col >= 0 and Col < Width and Row >= 0 and Row < Height


func GetPiece(Col: int, Row: int) -> PieceData:
	if not InBoard(Col, Row):
		return null
	return Cells[Col][Row]


func SetPiece(Col: int, Row: int, Piece: PieceData) -> void:
	Cells[Col][Row] = Piece


func IsBlocker(Col: int, Row: int) -> bool:
	if not InBoard(Col, Row):
		return false
	return Blockers[Col][Row]


# MARK: Virtual cells (gravity always toward increasing VRow)

func VirtualWidth() -> int:
	return Width if GravityDir.y != 0 else Height


func VirtualHeight() -> int:
	return Height if GravityDir.y != 0 else Width


## The real cell for a virtual one; not clamped, so a queued cell (VRow < 0) maps to a place just off the board.
func ToReal(VCol: int, VRow: int) -> Vector2i:
	if GravityDir == Vector2i(0, 1):
		return Vector2i(VCol, VRow)
	if GravityDir == Vector2i(0, -1):
		return Vector2i(VCol, Height - 1 - VRow)
	if GravityDir == Vector2i(1, 0):
		return Vector2i(VRow, VCol)
	return Vector2i(Width - 1 - VRow, VCol)


func VInRange(VCol: int, VRow: int) -> bool:
	return VCol >= 0 and VCol < VirtualWidth() and VRow >= -Pad and VRow < VirtualHeight()


func VGet(VCol: int, VRow: int) -> PieceData:
	if not VInRange(VCol, VRow):
		return null
	if VRow < 0:
		return Queue.get(Vector2i(VCol, VRow))
	var Real := ToReal(VCol, VRow)
	return Cells[Real.x][Real.y]


func VSet(VCol: int, VRow: int, Piece: PieceData) -> void:
	if VRow < 0:
		if Piece == null:
			Queue.erase(Vector2i(VCol, VRow))
		else:
			Queue[Vector2i(VCol, VRow)] = Piece
		return
	var Real := ToReal(VCol, VRow)
	Cells[Real.x][Real.y] = Piece


func VBlocker(VCol: int, VRow: int) -> bool:
	if VCol < 0 or VCol >= VirtualWidth() or VRow < 0 or VRow >= VirtualHeight():
		return false
	var Real := ToReal(VCol, VRow)
	return Blockers[Real.x][Real.y]


## A cell a piece could move into right now: on the board or in the queue off it, not a Blocker, and empty.
func CanEnter(VCol: int, VRow: int) -> bool:
	if not VInRange(VCol, VRow):
		return false
	return not VBlocker(VCol, VRow) and VGet(VCol, VRow) == null


## Whether a Blocker sits at or above `VRow` in the column, so nothing can ever be refilled into that cell from above.
func ColumnSealed(VCol: int, VRow: int) -> bool:
	for K in range(0, mini(VRow, VirtualHeight() - 1) + 1):
		if VBlocker(VCol, K):
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
	Queue.clear()
	for Col in Width:
		var Column: Array = []
		Column.resize(Height)
		Cells.append(Column)


# MARK: Setup

## Places up to `BlockerCount` Blockers at random, only where the remaining cells stay one connected region - or, when `Preset`
## is given, exactly on those cells (x = Col, y = Row; a level's).
func PlaceBlockers(Preset: Array[Vector3i] = []) -> void:
	Blockers = []
	for Col in Width:
		var Column: Array = []
		Column.resize(Height)
		Column.fill(false)
		Blockers.append(Column)
	if not Preset.is_empty():
		for Cell in Preset:
			if InBoard(Cell.x, Cell.y):
				Blockers[Cell.x][Cell.y] = true
		BlockerCount = Preset.size()
		return
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


## Malicious: puts the Blockers somewhere else (the same number, at random, with the open cells still connected). A piece on a cell
## that is now a Blocker is taken off the board; the cells the Blockers left are empty, so the next `Drop` fills them. Returns
## {Old: [cells], New: [cells], Gone: [{Cell, Piece}]}.
func RelocateBlockers() -> Dictionary:
	var Old: Array[Vector2i] = []
	for Col in Width:
		for Row in Height:
			if Blockers[Col][Row]:
				Old.append(Vector2i(Col, Row))
	PlaceBlockers()
	var New: Array[Vector2i] = []
	var Gone: Array = []
	for Col in Width:
		for Row in Height:
			if not Blockers[Col][Row]:
				continue
			New.append(Vector2i(Col, Row))
			var Piece := GetPiece(Col, Row)
			if Piece != null:
				Gone.append({"Cell": Vector2i(Col, Row), "Piece": Piece})
				SetPiece(Col, Row, null)
	return {"Old": Old, "New": New, "Gone": Gone}


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
	if Start == null:
		return Result
	var Seen := {Vector2i(Col, Row): true}
	var Stack: Array[Vector2i] = [Vector2i(Col, Row)]
	while not Stack.is_empty():
		var Cell: Vector2i = Stack.pop_back()
		Result.append(Cell)
		for Offset in Neighbors:
			var Next := Cell + Offset
			if Seen.has(Next):
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


## The group to suggest: the largest of the playable groups; among equal ones, the one lowest on the board (the highest row).
## With `Wanted` (colors still to remove), only groups of those colors count - unless there is none, then any group does.
## Empty if there is none.
func LargestGroup(Wanted: Array[int] = []) -> Array[Vector2i]:
	var Best: Array[Vector2i] = []
	var BestLowest := -1
	var Groups := PlayableGroups()
	if not Wanted.is_empty():
		var OfWanted := Groups.filter(func(Group: Array) -> bool: return Wanted.has(GetPiece(Group[0].x, Group[0].y).Kind))
		if not OfWanted.is_empty():
			Groups = OfWanted
	for Group in Groups:
		var Lowest := 0
		for Cell in Group:
			Lowest = maxi(Lowest, Cell.y)
		if Group.size() > Best.size() or (Group.size() == Best.size() and Lowest > BestLowest):
			Best.assign(Group)
			BestLowest = Lowest
	return Best


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


## Moves a piece between virtual cells, recording the path as virtual cells (they become real ones in `Drop`).
func MovePiece(Piece: PieceData, From: Vector2i, To: Vector2i) -> void:
	VSet(From.x, From.y, null)
	VSet(To.x, To.y, Piece)
	RecordMove(Piece, From, To)


## One piece's move, if it has one: straight down if the cell below is open; otherwise diagonally, but only when a
## Blocker is directly below it or the cell it would enter is in a column nothing can be refilled into from above.
func TryMove(Piece: PieceData, VCol: int, VRow: int) -> bool:
	if CanEnter(VCol, VRow + 1):
		MovePiece(Piece, Vector2i(VCol, VRow), Vector2i(VCol, VRow + 1))
		return true
	if VRow < 0:
		return false
	var BlockerBelow := VBlocker(VCol, VRow + 1)
	var Key := Vector2i(VCol, VRow)
	var Flip: bool = FlipToggles.get(Key, false)
	var Sides: Array = [1, -1] if Flip else [-1, 1]
	for Side in Sides:
		var TargetCol: int = VCol + Side
		if not CanEnter(TargetCol, VRow + 1):
			continue
		if BlockerBelow or ColumnSealed(TargetCol, VRow + 1):
			FlipToggles[Key] = not Flip
			MovePiece(Piece, Key, Vector2i(TargetCol, VRow + 1))
			return true
	return false


## Gravity, one row at a time from the bottom, repeated until a full pass moves nothing. Returns how many moves.
func Settle() -> int:
	var MoveCount := 0
	var Changed := true
	while Changed:
		Changed = false
		for VRow in range(VirtualHeight() - 2, -Pad - 1, -1):
			for VCol in VirtualWidth():
				var Piece := VGet(VCol, VRow)
				if Piece != null and TryMove(Piece, VCol, VRow):
					Changed = true
					MoveCount += 1
	return MoveCount


## New pieces queue off the board (on the side gravity pulls away from), one per open cell that can be refilled from
## there. A column with a Blocker on its first row gets none. Returns how many pieces were created.
func SpawnAbove() -> int:
	var Spawned := 0
	for VCol in VirtualWidth():
		var Needed := 0
		for VRow in VirtualHeight():
			if not ColumnSealed(VCol, VRow) and VGet(VCol, VRow) == null:
				Needed += 1
		Needed = mini(Needed, Pad)
		for Index in Needed:
			var Piece := NewPiece(RandomKind())
			var Cell := Vector2i(VCol, -1 - Index)
			VSet(Cell.x, Cell.y, Piece)
			Paths[Piece.Id] = [Cell]
			PathPieces[Piece.Id] = Piece
			Spawned += 1
	return Spawned


## Removes any piece still queued off the board once everything has settled. Spawning counts each column's open cells
## up front, and a piece resting on a Blocker can step sideways into a neighboring column's gap, so a column can be
## sent one piece more than it has room for. That extra piece never reaches the board.
func DiscardQueued() -> void:
	for Cell in Queue.keys():
		var Piece: PieceData = Queue[Cell]
		Paths.erase(Piece.Id)
		PathPieces.erase(Piece.Id)
	Queue.clear()


## Closes every gap: existing pieces fall (toward `GravityDir`), new ones queue off the opposite edge and fall in, until
## nothing more moves. Returns [{Piece, Path: Array[Vector2i]}] for every piece that moved or was created, with the path
## in real cells - a new piece's path starts just off the board.
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
		var RealPath: Array = []
		for Cell in Paths[Id]:
			RealPath.append(ToReal(Cell.x, Cell.y))
		Result.append({"Piece": PathPieces[Id], "Path": RealPath})
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
