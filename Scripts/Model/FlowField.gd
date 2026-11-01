class_name FlowField
extends RefCounted
## A level's own flow, for maps where pieces do not simply fall down every column. Each open cell has a direction its piece moves in when
## the cell ahead is empty, and/or a *link*: the cell its pieces go to instead of the one ahead, wherever that is - so one column can feed
## another, or an area can feed one far away. These are absolute (in the board's own frame): they override the board's gravity, which
## plays no part in a level with a flow, however the board is turned.
##
## It is all or nothing: a level has a flow only if *every* open cell (not a gap, not a Blocker) has a direction or a link
## (`CoversEveryCell`); a level that overrides some cells and leaves others to gravity is read as having no overrides at all.
##
## A piece steps into the cell ahead if that is open (not a gap or Blocker, on the board) and empty. If a Blocker is in the way it goes
## round it diagonally, as on an ordinary board. A cell nothing flows into is a *source*: whenever it is empty a new piece appears
## there, falling in from the cell behind it. So a column that flows up is fed at its bottom, and the cells just under a gap in the
## middle of a column are fed there. Everything repeats until nothing more moves.
##
## `Drop` returns the same {Piece, Path} moves as `BoardModel.Drop`, with the paths in real cells (a step through a link can be a long
## one). A piece never steps into a cell it has already been in during one drop, and a flow that loops is refused when it is read
## (`Loop`).

## Direction of each cell: Dirs[Col][Row] -> Vector2i, one of the four unit steps, or (0, 0) for a cell with no direction of its own.
var Dirs: Array = []
## Link: Vector2i cell -> Vector2i cell its pieces go to.
var Links: Dictionary = {}
var Width: int
var Height: int

const Symbols := {"v": Vector2i(0, 1), "^": Vector2i(0, -1), "<": Vector2i(-1, 0), ">": Vector2i(1, 0)}


func _init(NewWidth: int, NewHeight: int) -> void:
	Width = NewWidth
	Height = NewHeight
	for Col in Width:
		var Column: Array = []
		Column.resize(Height)
		Column.fill(Vector2i.ZERO)
		Dirs.append(Column)


## The cell a piece in `Cell` moves to (or tries to): its link, else the neighbour ahead. May be off the board.
func Ahead(Cell: Vector2i) -> Vector2i:
	if Links.has(Cell):
		return Links[Cell]
	return Cell + Dirs[Cell.x][Cell.y]


## The cell behind a source: where its new pieces come from.
func Behind(Cell: Vector2i) -> Vector2i:
	return Cell - Dirs[Cell.x][Cell.y]


## Whether every open cell has a direction or a link (so the flow can stand in for gravity).
func CoversEveryCell(Model: BoardModel) -> bool:
	for Col in Model.Width:
		for Row in Model.Height:
			if Model.IsOpen(Col, Row) and Dirs[Col][Row] == Vector2i.ZERO and not Links.has(Vector2i(Col, Row)):
				return false
	return true


## A cell on a loop of the flow, or (-1, -1) if there is none.
func Loop(Model: BoardModel) -> Vector2i:
	var Done := {}
	for Col in Model.Width:
		for Row in Model.Height:
			var Start := Vector2i(Col, Row)
			if not Model.IsOpen(Col, Row) or Done.has(Start):
				continue
			var OnWalk := {}
			var Cur := Start
			while Model.IsOpen(Cur.x, Cur.y) and not Done.has(Cur):
				if OnWalk.has(Cur):
					return Cur
				OnWalk[Cur] = true
				Cur = Ahead(Cur)
			for Cell in OnWalk:
				Done[Cell] = true
	return Vector2i(-1, -1)


## Closes every gap by the flow. See the class comment.
func Drop(Model: BoardModel) -> Array:
	Model.Paths.clear()
	Model.PathPieces.clear()
	var Open: Array[Vector2i] = []
	var Inflow := {}
	for Col in Model.Width:
		for Row in Model.Height:
			if Model.IsOpen(Col, Row):
				var Cell := Vector2i(Col, Row)
				Open.append(Cell)
				var Target := Ahead(Cell)
				if Model.IsOpen(Target.x, Target.y) and Target != Cell:
					Inflow[Target] = true
	var Order := DownstreamFirst(Model, Open)
	var Sources: Array[Vector2i] = []
	for Cell in Open:
		if not Inflow.has(Cell):
			Sources.append(Cell)
	var Changed := true
	var Steps := 0
	var Limit := Open.size() * maxi(Model.Width, Model.Height) * 4 + 100
	while Changed and Steps < Limit:
		Changed = false
		for Cell in Order:
			var Piece := Model.GetPiece(Cell.x, Cell.y)
			if Piece != null and Step(Model, Cell, Piece):
				Changed = true
				Steps += 1
		for Cell in Sources:
			if Model.GetPiece(Cell.x, Cell.y) == null:
				var Fresh := Model.NewPiece(Model.RandomKind())
				Model.SetPiece(Cell.x, Cell.y, Fresh)
				Model.Paths[Fresh.Id] = [Behind(Cell), Cell]
				Model.PathPieces[Fresh.Id] = Fresh
				Changed = true
	var Result: Array = []
	for Id in Model.Paths:
		Result.append({"Piece": Model.PathPieces[Id], "Path": Model.Paths[Id]})
	# A cell the flow cannot reach (a safety net; a valid flow reaches every cell) still gets a piece.
	Result.append_array(Model.FillDeadCells())
	return Result


## Moves the piece in `Cell` one step if it can. True if it moved.
func Step(Model: BoardModel, Cell: Vector2i, Piece: BoardModel.PieceData) -> bool:
	var Target := Ahead(Cell)
	var Visited: Array = Model.Paths.get(Piece.Id, [Cell])
	if Model.IsOpen(Target.x, Target.y):
		if Model.GetPiece(Target.x, Target.y) == null and not Visited.has(Target):
			Move(Model, Piece, Cell, Target)
			return true
		return false
	if not Model.IsBlocker(Target.x, Target.y) or Links.has(Cell):
		return false
	# A Blocker straight ahead: go round it, to the side that is free (the sides take turns being tried first).
	var Dir: Vector2i = Dirs[Cell.x][Cell.y]
	var Side := Vector2i(-Dir.y, Dir.x)
	var Flip: bool = Model.FlipToggles.get(Cell, false)
	for Sign in ([-1, 1] if Flip else [1, -1]):
		var Round: Vector2i = Cell + Dir + Side * Sign
		if Model.IsOpen(Round.x, Round.y) and Model.GetPiece(Round.x, Round.y) == null and not Visited.has(Round):
			Model.FlipToggles[Cell] = not Flip
			Move(Model, Piece, Cell, Round)
			return true
	return false


func Move(Model: BoardModel, Piece: BoardModel.PieceData, From: Vector2i, To: Vector2i) -> void:
	Model.SetPiece(From.x, From.y, null)
	Model.SetPiece(To.x, To.y, Piece)
	Model.RecordMove(Piece, From, To)


## The open cells, those nearest the end of their flow first, so a row of pieces all step forward in one pass.
func DownstreamFirst(Model: BoardModel, Open: Array[Vector2i]) -> Array[Vector2i]:
	var Depth := {}
	for Start in Open:
		if Depth.has(Start):
			continue
		var Chain: Array[Vector2i] = []
		var OnChain := {}
		var Cur := Start
		var Base := 0
		while true:
			if Depth.has(Cur):
				Base = Depth[Cur] + 1
				break
			if OnChain.has(Cur):
				break
			OnChain[Cur] = true
			Chain.append(Cur)
			var Target := Ahead(Cur)
			if not Model.IsOpen(Target.x, Target.y):
				break
			Cur = Target
		for Index in range(Chain.size() - 1, -1, -1):
			Depth[Chain[Index]] = Base
			Base += 1
	var Sorted: Array[Vector2i] = Open.duplicate()
	Sorted.sort_custom(func(A: Vector2i, B: Vector2i) -> bool: return Depth[A] < Depth[B])
	return Sorted
