class_name DifficultyRun
extends Node
## The difficulty test (Settings > Level Difficulty): plays every level `Trials` times with a simple bot and records how many turns
## it took (`Levels.Record`). The bot always takes the largest group of a color the goal still needs - the same group the hint
## suggests - or, when none of those can be played, the largest group of any color, and shuffles when nothing can be played.
## Plays on `BoardModel` alone (no nodes, so it is fast); one trial runs per frame so the screen can show the progress.

signal Progress(LevelIndex: int, Trial: int, LastTurns: int, Mean: float)
signal LevelDone(LevelIndex: int, Mean: float, WinRate: float, Difficulty: int)
signal Finished(Cancelled: bool)

const Trials := 30
## A trial that has not reached the goal by now stops and counts as this many turns.
const TurnCap := 300

var Running: bool = false
var Cancelled: bool = false


func Start() -> void:
	if Running:
		return
	Running = true
	Cancelled = false
	for Index in Levels.Count():
		var Level := Levels.All()[Index]
		var Total := 0
		var Wins := 0
		for Trial in Trials:
			if Cancelled:
				Running = false
				Finished.emit(true)
				return
			var Turns := PlayOnce(Level)
			Total += Turns
			if Turns <= Level.TurnCount:
				Wins += 1
			Progress.emit(Index, Trial + 1, Turns, float(Total) / float(Trial + 1))
			await get_tree().process_frame
		var Mean := float(Total) / float(Trials)
		var WinRate := float(Wins) / float(Trials)
		Levels.Record(Index, Mean, WinRate)
		LevelDone.emit(Index, Mean, WinRate, Level.Difficulty)
	Running = false
	Finished.emit(false)


## One game of `Level` by the bot: the turns it took to reach the goal (`TurnCap` if it never did).
static func PlayOnce(Level: LevelDefinition) -> int:
	var Model := BoardModel.new(Level.Dimensions.x, Level.Dimensions.y, Level.ColorCount, Level.PresetBlockers.size(), 0, Level.PresetBlockers)
	var Remaining := {}
	for Goal in Level.ColorGoals:
		Remaining[Goal.x] = int(Remaining.get(Goal.x, 0)) + Goal.y
	var Turns := 0
	var Shuffles := 0
	while Turns < TurnCap and not AllDone(Remaining):
		if not Model.HasPlayableGroup():
			# Nothing to play: shuffle (no turn used); a board that cannot be made playable gives up.
			Shuffles += 1
			if Shuffles > TurnCap:
				break
			Model.Shuffle()
			continue
		var Wanted: Array[int] = []
		for Kind in Remaining:
			if int(Remaining[Kind]) > 0:
				Wanted.append(Kind)
		var Group := Model.LargestGroup(Wanted)
		var Kind := Model.GetPiece(Group[0].x, Group[0].y).Kind
		Model.Remove(Group)
		Turns += 1
		if Remaining.has(Kind):
			Remaining[Kind] = maxi(int(Remaining[Kind]) - Group.size(), 0)
		Model.Drop()
	return Turns if AllDone(Remaining) else TurnCap


static func AllDone(Remaining: Dictionary) -> bool:
	for Kind in Remaining:
		if int(Remaining[Kind]) > 0:
			return false
	return true
