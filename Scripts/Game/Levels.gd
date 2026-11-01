class_name Levels
extends RefCounted
## The list of levels, read at run time from JSON files (see `Levels/README.md`): `PrimaryLevelIndex.json` lists level files, and each
## level file holds a set of levels, each with a map of the board (gaps, Blockers, fixed pieces) and its goal, turns, time, difficulty and
## optional piece shape and removal effect. Level N has the Nth place in the order the index lists the files.
##
## The index is looked for in `user://Levels/` first (the folder a player or author edits; `ExportBuiltIn` copies the shipped files
## there to start from) and then in `res://Levels/` (the shipped set). A problem in a file (bad JSON, a missing field) drops that
## level or file, is printed and is kept in `Problems`; the others still load.

const IndexName := "PrimaryLevelIndex.json"
const UserDirectory := "user://Levels/"
const BuiltInDirectory := "res://Levels/"
## The most a map can be, either way (cells), and the fewest cells a level can have open.
const MaxMapSize := 20
const MinMapSize := 3
const MinOpenCells := 3
const MaxColors := 8
const MinColors := 3

## Extra turns on top of the taps the goal needs, as a fraction of them: the most for the smallest board, the least for the largest.
const FudgeMostPieces := 0.25
const FudgeFewestPieces := 0.5
## Seconds per piece to remove, in Timed mode.
const SecondsPerPiece := 1.0
## The goal pieces a turn is expected to clear. A group is at least 3, but a turn often cannot be spent on a group of a goal color
## (there may be none to play), so this is well under 3: 1.6 is about what the difficulty test's bot managed (1.1 to 2.7 on the
## ten levels) less a margin. Used for a level that does not give its own `Turns`.
const PiecesPerTurn := 1.6
## The board sizes `TurnsFor` scales its fudge between (pieces on the board).
const FewestBoardPieces := 9
const MostBoardPieces := 195

## Where the difficulty test's results are kept between launches (one section per level, named by its `Id`).
const StatsPath := "user://LevelDifficulty.cfg"
## Difficulty is worked out from how many turns the test bot needed (its mean) against the turns the level allows: a ratio of
## `EasyRatio` or less is difficulty 1, `HardRatio` or more (the bot needs every turn the level allows, or more) is difficulty 10,
## and the ratios between spread evenly over 2 to 9.
const EasyRatio := 0.3
const HardRatio := 1.0

static var Cache: Array[LevelDefinition] = []
static var Loaded: bool = false
## What went wrong while reading the files, one line each; empty when everything loaded.
static var Problems: Array[String] = []
## The folder the index was read from.
static var Directory: String = BuiltInDirectory


static func All() -> Array[LevelDefinition]:
	if not Loaded:
		Reload()
	return Cache


static func Count() -> int:
	return All().size()


## Reads the index and every level file again (after the files were edited).
static func Reload() -> void:
	Cache = []
	Problems = []
	Loaded = true
	Directory = UserDirectory if FileAccess.file_exists(UserDirectory + IndexName) else BuiltInDirectory
	var Index: Variant = ReadJson(Directory + IndexName)
	if not (Index is Dictionary) or not (Index as Dictionary).get("Files") is Array:
		Problem("%s: needs an object with a \"Files\" list" % (Directory + IndexName))
		return
	for Entry in (Index as Dictionary)["Files"]:
		var FileName := ""
		if Entry is String:
			FileName = Entry
		elif Entry is Dictionary and (Entry as Dictionary).get("File") is String:
			FileName = (Entry as Dictionary)["File"]
		else:
			Problem("%s: a \"Files\" entry must be a file name or {\"File\": name}" % IndexName)
			continue
		LoadFile(FileName)
	LoadStats()


## Copies the shipped level files into `user://Levels/` (those not already there), so they can be edited. Returns that folder's real path.
static func ExportBuiltIn() -> String:
	DirAccess.make_dir_recursive_absolute(UserDirectory)
	for Name in DirAccess.get_files_at(BuiltInDirectory):
		if not Name.ends_with(".json") or FileAccess.file_exists(UserDirectory + Name):
			continue
		var Text := FileAccess.get_file_as_string(BuiltInDirectory + Name)
		var Out := FileAccess.open(UserDirectory + Name, FileAccess.WRITE)
		if Out != null:
			Out.store_string(Text)
	return ProjectSettings.globalize_path(UserDirectory)


static func Problem(Text: String) -> void:
	Problems.append(Text)
	push_warning("Levels: " + Text)


## The parsed JSON of a file, or null (with a problem noted) if it is missing or is not valid JSON.
static func ReadJson(Path: String) -> Variant:
	if not FileAccess.file_exists(Path):
		Problem("%s: no such file" % Path)
		return null
	var Parser := JSON.new()
	if Parser.parse(FileAccess.get_file_as_string(Path)) != OK:
		Problem("%s: line %d: %s" % [Path, Parser.get_error_line(), Parser.get_error_message()])
		return null
	return Parser.data


static func LoadFile(FileName: String) -> void:
	var Data: Variant = ReadJson(Directory + FileName)
	if not (Data is Dictionary) or not (Data as Dictionary).get("Levels") is Array:
		if Data != null:
			Problem("%s: needs an object with a \"Levels\" list" % FileName)
		return
	var Position := 0
	for Entry in (Data as Dictionary)["Levels"]:
		Position += 1
		var Where := "%s, level %d" % [FileName, Position]
		if not Entry is Dictionary:
			Problem("%s: a level must be an object" % Where)
			continue
		var Level := Parse(Entry, FileName, Position, Cache.size() + 1, Where)
		if Level == null:
			continue
		if Cache.any(func(Other: LevelDefinition) -> bool: return Other.Id == Level.Id):
			Problem("%s: the Id \"%s\" is already used by another level" % [Where, Level.Id])
			continue
		Cache.append(Level)


## What a file's level entry says as a `LevelDefinition`, or null (with the problems noted) if it cannot be played.
## `Position` is the level's place in its file, `Number` its place in the whole list; `Where` names it in messages.
static func Parse(Data: Dictionary, FileName: String, Position: int, Number: int, Where: String) -> LevelDefinition:
	var Level := LevelDefinition.new()
	Level.Source = FileName
	Level.Id = str(Data.get("Id", "%s %d" % [FileName.get_basename(), Position]))
	Level.Name = str(Data.get("Name", "Level %d" % Number))
	Level.ShapeType = LevelDefinition.ShapeTypes.TwoD
	Level.Difficulty = int(Data.get("Difficulty", InitialDifficulty(Number)))
	var Colors := int(Data.get("Colors", 0))
	if Colors < MinColors or Colors > MaxColors:
		Problem("%s: \"Colors\" must be %d to %d" % [Where, MinColors, MaxColors])
		return null
	Level.ColorCount = Colors
	if not ParseMap(Data, Level, Where):
		return null
	var Total := 0
	if not Data.get("Goals") is Array or (Data["Goals"] as Array).is_empty():
		Problem("%s: needs a \"Goals\" list of {\"Group\": n, \"Remove\": pieces}" % Where)
		return null
	for Goal in Data["Goals"]:
		var Group := int(Goal.get("Group", -1)) if Goal is Dictionary else -1
		var Pieces := int(Goal.get("Remove", 0)) if Goal is Dictionary else 0
		if Group < 0 or Group >= Colors or Pieces <= 0:
			Problem("%s: a goal needs a \"Group\" from 0 to %d and a \"Remove\" above 0" % [Where, Colors - 1])
			return null
		Level.ColorGoals.append(Vector2i(Group, Pieces))
		Total += Pieces
	var BoardPieces := Level.Dimensions.x * Level.Dimensions.y - Level.PresetGaps.size() - Level.PresetBlockers.size()
	Level.TurnCount = int(Data["Turns"]) if Data.has("Turns") else TurnsFor(Total, BoardPieces)
	Level.TimeCount = float(Data["Time"]) if Data.has("Time") else Total * SecondsPerPiece
	if Level.TurnCount <= 0 or Level.TimeCount <= 0.0:
		Problem("%s: \"Turns\" and \"Time\" must be above 0" % Where)
		return null
	if Data.has("Shape"):
		Level.Shape = IndexOfName(BlockStyles.ShapeNames, Data["Shape"])
		if Level.Shape < 0:
			Problem("%s: unknown \"Shape\" %s (use one of %s)" % [Where, str(Data["Shape"]), ", ".join(BlockStyles.ShapeNames)])
			return null
	if Data.has("RemovalEffect"):
		Level.RemovalEffect = IndexOfName(ControlBarRows.RemovalEffectNames, Data["RemovalEffect"])
		if Level.RemovalEffect < 0:
			Problem("%s: unknown \"RemovalEffect\" %s (use one of %s)" % [Where, str(Data["RemovalEffect"]), ", ".join(ControlBarRows.RemovalEffectNames)])
			return null
	return Level


## A name from `Names` (any case) or its index, as the index; -1 if it is neither.
static func IndexOfName(Names: Array[String], Value: Variant) -> int:
	if Value is String:
		for Index in Names.size():
			if Names[Index].to_lower() == (Value as String).to_lower():
				return Index
		return -1
	if (Value is float or Value is int) and int(Value) >= 0 and int(Value) < Names.size():
		return int(Value)
	return -1


## Reads "Map" and "Legend" into the level's size, gaps, Blockers and fixed pieces. False (with the problem noted) if the map cannot
## be played.
static func ParseMap(Data: Dictionary, Level: LevelDefinition, Where: String) -> bool:
	if not Data.get("Map") is Array or (Data["Map"] as Array).is_empty():
		Problem("%s: needs a \"Map\": a list of text rows" % Where)
		return false
	var Rows: Array = Data["Map"]
	var Width := 0
	for Row in Rows:
		if not Row is String:
			Problem("%s: every row of the \"Map\" must be text" % Where)
			return false
		Width = maxi(Width, (Row as String).length())
	var Height := Rows.size()
	if Width < MinMapSize or Height < MinMapSize or Width > MaxMapSize or Height > MaxMapSize:
		Problem("%s: the map must be %d to %d cells each way (it is %d x %d)" % [Where, MinMapSize, MaxMapSize, Width, Height])
		return false
	var Legend := Legends(Data.get("Legend", {}), Level.ColorCount, Where)
	if Legend.is_empty():
		return false
	Level.Dimensions = Vector3i(Width, Height, 0)
	for Row in Height:
		var Line: String = Rows[Row]
		for Col in Width:
			# A short row is finished with gaps.
			var Symbol := Line[Col] if Col < Line.length() else "."
			if not Legend.has(Symbol):
				Problem("%s: the map has \"%s\" (row %d, column %d), which is not in the Legend" % [Where, Symbol, Row + 1, Col + 1])
				return false
			var Meaning: Dictionary = Legend[Symbol]
			var Cell := Vector3i(Col, Row, 0)
			match Meaning["Type"]:
				"Gap":
					Level.PresetGaps.append(Cell)
				"Blocker":
					Level.PresetBlockers.append(Cell)
				"Piece":
					if Meaning["Group"] >= 0:
						Level.PresetPieces.append({"Cell": Cell, "Kind": Meaning["Group"], "Count": Meaning["Count"]})
					elif Meaning["Count"] > 0:
						# A random color with a countdown: the color is picked now, so the level is the same every time.
						Level.PresetPieces.append({"Cell": Cell, "Kind": (Col * 7 + Row * 3) % Level.ColorCount, "Count": Meaning["Count"]})
	if not ParseFlow(Data, Level, Where):
		return false
	var Check := BoardModel.new(Width, Height, Level.ColorCount, 0, 1, Level.PresetBlockers, Level.PresetGaps, [], Level.Flow)
	var Open := Width * Height - Level.PresetGaps.size() - Level.PresetBlockers.size()
	if Open < MinOpenCells or Check.LargestRegion() < BoardModel.MinimumGroupSize:
		Problem("%s: no group of %d can ever form: at least %d open cells must touch" % [Where, BoardModel.MinimumGroupSize, BoardModel.MinimumGroupSize])
		return false
	if Level.Flow != null:
		var Loop := Level.Flow.Loop(Check)
		if Loop.x >= 0:
			Problem("%s: the flow loops back on itself at column %d, row %d" % [Where, Loop.x, Loop.y])
			return false
	return true


## Reads the optional "Flow" (rows of `v ^ < >`, the way pieces move in each cell; `.`, `-` or a space = no direction for that cell) and
## "Links" ([{"From": [col, row], "To": [col, row]}], 0-based: the pieces of From go to To) into `Level.Flow`. A level with neither has no
## flow of its own (null). The flow is all or nothing: unless every open cell has a direction or a link, the flow is ignored (null, with a
## note in `Problems`) and the level plays with the board's gravity. False (with the problem noted) if either is wrong.
static func ParseFlow(Data: Dictionary, Level: LevelDefinition, Where: String) -> bool:
	if not Data.has("Flow") and not Data.has("Links"):
		return true
	var Width := Level.Dimensions.x
	var Height := Level.Dimensions.y
	var Field := FlowField.new(Width, Height)
	if Data.has("Flow"):
		var Rows: Variant = Data["Flow"]
		if not Rows is Array or (Rows as Array).size() > Height:
			Problem("%s: \"Flow\" must be a list of text rows, no more than the map has" % Where)
			return false
		for Row in (Rows as Array).size():
			var Line: Variant = Rows[Row]
			if not Line is String or (Line as String).length() > Width:
				Problem("%s: \"Flow\" row %d must be text no longer than the map's rows" % [Where, Row + 1])
				return false
			for Col in (Line as String).length():
				var Symbol: String = Line[Col]
				if FlowField.Symbols.has(Symbol):
					Field.Dirs[Col][Row] = FlowField.Symbols[Symbol]
				elif not [".", "-", " "].has(Symbol):
					Problem("%s: \"Flow\" has \"%s\" (row %d, column %d); use v ^ < > or ." % [Where, Symbol, Row + 1, Col + 1])
					return false
	if Data.has("Links"):
		if not Data["Links"] is Array:
			Problem("%s: \"Links\" must be a list of {\"From\": [col, row], \"To\": [col, row]}" % Where)
			return false
		var Blocked := {}
		for Cell in Level.PresetGaps + Level.PresetBlockers:
			Blocked[Vector2i(Cell.x, Cell.y)] = true
		for Link in Data["Links"]:
			var From := CellOf(Link.get("From") if Link is Dictionary else null)
			var To := CellOf(Link.get("To") if Link is Dictionary else null)
			var Fits := From.x >= 0 and To.x >= 0 and From.x < Width and To.x < Width and From.y < Height and To.y < Height
			if not Fits or From == To or Blocked.has(From) or Blocked.has(To) or Field.Links.has(From):
				Problem("%s: a link needs a \"From\" and a different \"To\", each [col, row] on an open cell of the map, and one link per cell" % Where)
				return false
			Field.Links[From] = To
	var Open := BoardModel.new(Width, Height, Level.ColorCount, 0, 1, Level.PresetBlockers, Level.PresetGaps)
	if not Field.CoversEveryCell(Open):
		Problem("%s: note: not every open cell has a Flow direction or a Link, so the whole Flow is ignored and gravity applies" % Where)
		return true
	Level.Flow = Field
	return true


## [col, row] as a cell, or (-1, -1) if it is not two whole numbers.
static func CellOf(Value: Variant) -> Vector2i:
	if Value is Array and (Value as Array).size() == 2 and (Value[0] is float or Value[0] is int) and (Value[1] is float or Value[1] is int):
		return Vector2i(int(Value[0]), int(Value[1]))
	return Vector2i(-1, -1)


## The map symbols and what they mean: "." gap, "#" a piece of a random color, "B" a Blocker, plus the level's "Legend" entries
## ({"Type": "Gap" | "Blocker" | "Piece", "Group": color (Piece; leave out for random), "Count": countdown (Piece; 0 or left out
## for none)}; an entry with a "Group" or "Count" and no "Type" is a Piece). Returns {} (with the problem noted) if a Legend entry is wrong.
static func Legends(Given: Variant, Colors: int, Where: String) -> Dictionary:
	var Result := {
		".": {"Type": "Gap", "Group": -1, "Count": 0},
		"#": {"Type": "Piece", "Group": -1, "Count": 0},
		"B": {"Type": "Blocker", "Group": -1, "Count": 0},
	}
	if not Given is Dictionary:
		Problem("%s: \"Legend\" must be an object" % Where)
		return {}
	for Symbol in Given:
		var Entry: Variant = Given[Symbol]
		if (Symbol as String).length() != 1 or not Entry is Dictionary:
			Problem("%s: a Legend key is one character, and its value an object" % Where)
			return {}
		var Kind := str(Entry.get("Type", "Piece" if (Entry.has("Group") or Entry.has("Count")) else ""))
		if not ["Gap", "Blocker", "Piece"].has(Kind):
			Problem("%s: Legend \"%s\" needs a \"Type\" of Gap, Blocker or Piece" % [Where, Symbol])
			return {}
		var Group := int(Entry.get("Group", -1))
		var Count := int(Entry.get("Count", 0))
		if Group >= Colors or Count < 0:
			Problem("%s: Legend \"%s\": \"Group\" must be below %d and \"Count\" 0 or more" % [Where, Symbol, Colors])
			return {}
		if Kind == "Blocker" and (Entry.has("Count") or Entry.has("Group")):
			Problem("%s: Legend \"%s\": a Blocker has no Group and its count cannot go down, so it takes no \"Count\"" % [Where, Symbol])
			return {}
		Result[Symbol] = {"Type": Kind, "Group": Group, "Count": Count}
	return Result


## The difficulty a level has before the difficulty test has measured it: its number in the list, up to 10.
static func InitialDifficulty(Number: int) -> int:
	return clampi(Number, LevelDefinition.MinDifficulty, LevelDefinition.MaxDifficulty)


## The difficulty (1 easiest to 10 hardest) of a level that allows `AllowedTurns` and took the test bot `MeanTurns` on average.
static func DifficultyFor(MeanTurns: float, AllowedTurns: int) -> int:
	var Ratio := MeanTurns / maxf(float(AllowedTurns), 1.0)
	return clampi(roundi(1.0 + 9.0 * (Ratio - EasyRatio) / (HardRatio - EasyRatio)), 1, 10)


## Records a level's test result: the mean turns and win rate go in the table (`MeanTurns`, `WinRate`), the difficulty is
## updated from them, and all of it is saved for the next launch.
static func Record(Index: int, MeanTurns: float, WinRate: float) -> void:
	var Level := All()[Index]
	Level.MeanTurns = MeanTurns
	Level.WinRate = WinRate
	Level.Difficulty = DifficultyFor(MeanTurns, Level.TurnCount)
	var File := ConfigFile.new()
	File.load(StatsPath)
	File.set_value(Level.Id, "MeanTurns", MeanTurns)
	File.set_value(Level.Id, "WinRate", WinRate)
	File.set_value(Level.Id, "Difficulty", Level.Difficulty)
	File.set_value(Level.Id, "Turns", Level.TurnCount)
	File.save(StatsPath)


## Puts the saved test results back into the levels. A result measured for a different number of allowed turns is ignored.
static func LoadStats() -> void:
	var File := ConfigFile.new()
	if File.load(StatsPath) != OK:
		return
	for Level in Cache:
		if File.has_section_key(Level.Id, "MeanTurns") and int(File.get_value(Level.Id, "Turns", Level.TurnCount)) == Level.TurnCount:
			Level.MeanTurns = float(File.get_value(Level.Id, "MeanTurns"))
			Level.WinRate = float(File.get_value(Level.Id, "WinRate", -1.0))
			Level.Difficulty = DifficultyFor(Level.MeanTurns, Level.TurnCount)


## Turns for a goal of `Pieces` pieces on a board with this many pieces (cells that are not Blockers or gaps): the taps it takes at an
## average of `PiecesPerTurn`, plus a fudge that grows as the board shrinks.
static func TurnsFor(Pieces: int, BoardPieces: int) -> int:
	var Fraction := clampf(float(BoardPieces - FewestBoardPieces) / float(MostBoardPieces - FewestBoardPieces), 0.0, 1.0)
	var Base := ceili(Pieces / PiecesPerTurn)
	return Base + ceili(Base * lerpf(FudgeFewestPieces, FudgeMostPieces, Fraction))
