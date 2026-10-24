class_name GameSession
extends Node
## One game in progress: the play mode, the level, and the turns and time used so far. A turn is a tap that removes a group.
## The goal is color removal: `Remaining` says how many pieces of each goal color are still to go. The boards report each
## removal (`RecordRemoval`); `Main` asks `CanPlay` before passing a tap on. The clock starts at the
## first removal and is counted in every mode (it ends a game only in Timed), and waits while Settings is open.

enum States { Playing, Won, Lost }

signal StateChanged(NewState: States)

var Mode: GameMode.Kinds = GameMode.Default
var Level: LevelDefinition = LevelDefinition.new()
var State: States = States.Playing
var Turns: int = 0
var Elapsed: float = 0.0
## Goal color (`Kind`) -> pieces still to remove (0 once done). `GoalOrder` is the goal colors in the level's order.
var Remaining: Dictionary = {}
var GoalOrder: Array[int] = []
## True once the goal has been reached (in Zen play goes on after it).
var GoalMet: bool = false
## Set by `Main` while Attract Mode is on: turns are counted, but no goal, turn limit or time limit ends the game (Attract Mode is
## over only when no group is left to remove).
var Unlimited: bool = false
## Set by `Main` while the Settings window is open: the clock waits.
var Paused: bool = false
var ClockStarted: bool = false


func Start(NewMode: GameMode.Kinds, NewLevel: LevelDefinition) -> void:
	Mode = NewMode
	Level = NewLevel
	State = States.Playing
	Turns = 0
	Elapsed = 0.0
	Remaining.clear()
	GoalOrder.clear()
	for Goal in Level.ColorGoals:
		if not Remaining.has(Goal.x):
			GoalOrder.append(Goal.x)
		Remaining[Goal.x] = int(Remaining.get(Goal.x, 0)) + Goal.y
	GoalMet = false
	ClockStarted = false
	StateChanged.emit(State)


## False once a Timed or Turn game is won or lost; Zen always plays.
func CanPlay() -> bool:
	return State == States.Playing


## A tap removed a group of `Size` pieces of color `Kind`.
func RecordRemoval(Kind: int, Size: int) -> void:
	if not CanPlay():
		return
	ClockStarted = true
	Turns += 1
	if Remaining.has(Kind):
		Remaining[Kind] = maxi(int(Remaining[Kind]) - Size, 0)
	if Unlimited:
		return
	if AllDone():
		GoalMet = true
		if Mode != GameMode.Kinds.Zen:
			Finish(States.Won)
			return
	if Mode == GameMode.Kinds.Turn and Turns >= Level.TurnCount:
		Finish(States.Lost)


## Whether every goal color has had enough pieces removed.
func AllDone() -> bool:
	for Kind in Remaining:
		if int(Remaining[Kind]) > 0:
			return false
	return true


## The goal colors that still need pieces removed, in the level's order.
func WantedKinds() -> Array[int]:
	var Wanted: Array[int] = []
	for Kind in GoalOrder:
		if int(Remaining[Kind]) > 0:
			Wanted.append(Kind)
	return Wanted


func Finish(NewState: States) -> void:
	State = NewState
	StateChanged.emit(State)


func TurnsLeft() -> int:
	return maxi(Level.TurnCount - Turns, 0)


func TimeLeft() -> float:
	return maxf(Level.TimeCount - Elapsed, 0.0)


func _process(Delta: float) -> void:
	if not ClockStarted or Paused or not CanPlay():
		return
	Elapsed += Delta
	if Mode == GameMode.Kinds.Timed and Elapsed >= Level.TimeCount:
		Elapsed = Level.TimeCount
		Finish(States.Lost)


## The readout beside the score: time left in Timed, turns left in Turn, none (empty title) in Zen.
func ClockTitle() -> String:
	match Mode:
		GameMode.Kinds.Timed:
			return "Time"
		GameMode.Kinds.Turn:
			return "Turns left"
	return ""


func ClockText() -> String:
	match Mode:
		GameMode.Kinds.Timed:
			return "%d" % ceili(TimeLeft())
		GameMode.Kinds.Turn:
			return str(TurnsLeft())
	return ""


func StatusText() -> String:
	if State == States.Won:
		return "Goal reached!"
	if State == States.Lost:
		return "Out of time" if Mode == GameMode.Kinds.Timed else "Out of turns"
	if GoalMet:
		return "Goal reached - keep playing"
	return ""
