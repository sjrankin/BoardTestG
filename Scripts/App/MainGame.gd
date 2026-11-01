class_name MainGame
extends MainMalicious

## Starting, playing and winning games.

## Starts a new game on the board being played, with its own size.
func StartGame() -> void:
	SequenceId += 1
	if Malicious[4]:
		# A new game, a new swap of the colors.
		Board2D.Styles.Reshuffle(ActiveGroups())
		Board2D.Styles.RefreshColors()
	Advancing = false
	VeilShown = false
	VeilClock = 0.0
	VeilNext = VeilEvery
	Bar.ShowReplayPrompt(false)
	Bar.ClearGoals()
	if LevelIndex >= 0 and not Is3D:
		var Level := Levels.All()[LevelIndex]
		Session.Start(PlayMode, Level)
		ApplyLevelLook(Level)
		View.NewGame(Level.Dimensions.x, Level.Dimensions.y, Level.ColorCount, Level.PresetBlockers.size(), Level.PresetBlockers, Level.PresetGaps, Level.PresetPieces, Level.Flow)
		return
	ApplyLevelLook(null)
	var LayoutName := CurrentLayoutName()
	var Size2D := BoardLayouts.Size(LayoutName) if not LayoutName.is_empty() else Dimensions2D
	Session.Start(PlayMode, LevelDefinition.Default(Is3D, Dimensions3D if Is3D else Vector3i(Size2D.x, Size2D.y, 0)))
	if Is3D:
		View.NewGame(Dimensions3D.x, Dimensions3D.y, Dimensions3D.z, Colors)
	else:
		var NoBlockers: Array[Vector3i] = []
		View.NewGame(Size2D.x, Size2D.y, Colors, Blockers, NoBlockers, BoardLayouts.Gaps(LayoutName))


## The piece shape and removal effect a game is played with: the level's own, if it names one and the player has not turned on the
## override for it in Settings > Game, else the player's choice in Settings (which is what `null` - no level - gets). The pickers show the
## player's choice either way, and nothing here is saved.
func ApplyLevelLook(Level: LevelDefinition) -> void:
	var Shape := Bar.ShapePicker.selected
	if Level != null and Level.Shape >= 0 and not Bar.OverrideShapeCheck.button_pressed:
		Shape = Level.Shape
	if Shape != View.Styles.CurrentShape:
		View.SetBlockShape(Shape)
	var Effect := Bar.RemovalEffectPicker.selected
	if Level != null and Level.RemovalEffect >= 0 and not Bar.OverrideEffectCheck.button_pressed:
		Effect = Level.RemovalEffect
	Both("RemovalEffect", Effect)


## Settings > Game > "Read the level files again": the levels are read from the files once more and the Level list is refilled.
func OnLevelsReloadPressed() -> void:
	Levels.Reload()
	Bar.FillLevelPicker()
	if LevelIndex >= Levels.Count():
		ClearLevel()
	Bar.LevelPicker.selected = LevelIndex + 1
	Bar.ShowLevelProblems()


## The irregular layout of the 2D board set in Settings, or "" for the plain rectangle.
func CurrentLayoutName() -> String:
	if Layout <= 0:
		return ""
	return BoardLayouts.Names()[Layout]


## Settings > Board > Layout: the 2D board plays the layout (index 0 is the plain rectangle) in a new game.
func OnLayoutSelected(Index: int) -> void:
	Layout = Index
	GameSettings.Save("BoardLayout", Layout)
	ClearLevel()
	ShowBoardType()
	StartGame()


## Switches between the 2D board and the 3D cube. The board left behind is taken out of the scene (with whatever was flying
## off it), and the other starts a new game with its own size.
func SwitchBoardType(To3D: bool) -> void:
	if To3D == Is3D:
		return
	Bar.AttractCheck.button_pressed = false
	if To3D:
		ClearLevel()
	View.Flyers.Reset()
	remove_child(View)
	Is3D = To3D
	View = Board3D if Is3D else Board2D
	add_child(View)
	View.SetBlockShape(Board2D.Styles.CurrentShape)
	GameSettings.Save("BoardType", 1 if Is3D else 0)
	ShowBoardType()
	StartGame()


func OnGameModeSelected(Index: int) -> void:
	PlayMode = Index as GameMode.Kinds
	GameSettings.Save("PlayMode", Index)
	Bar.AttractCheck.button_pressed = false
	StartGame()


func OnAttractToggled(On: bool) -> void:
	if On:
		if LevelIndex >= 0:
			ResumeLevel = LevelIndex
		OnBoardSet(int(Bar.WidthField.value), int(Bar.HeightField.value), int(Bar.DepthField.value), int(Bar.ColorsField.value), int(Bar.BlockersField.value))


func OnSessionState(NewState: GameSession.States) -> void:
	if NewState == GameSession.States.Won:
		WinSequence()
	elif NewState == GameSession.States.Lost:
		Bar.ShowReplayPrompt(true)


## "Replay? Yes" plays the same level again; "No" goes back to Attract Mode (with its Play button), which comes back to this
## level.
func OnReplayAnswered(Yes: bool) -> void:
	if Yes:
		StartGame()
	else:
		Bar.AttractCheck.button_pressed = true


## Whether nothing is left flying: no removal effect playing and no shards or pieces in the air. (Not `Busy`: that stays set on
## an exploded board, which is never played again.)
func ShardsSettled() -> bool:
	return View.InPlaceActive == 0 and (View.Flyers == null or View.Flyers.Flyers.is_empty())


## Waits (up to `Seconds`) until `Needs` is true; false if a new game began meanwhile.
func WaitForBoard(Id: int, Seconds: float, Needs: Callable) -> bool:
	var Waited := 0.0
	while not Needs.call() and Waited < Seconds:
		await get_tree().process_frame
		Waited += get_process_delta_time()
		if Id != SequenceId:
			return false
	return Id == SequenceId


## "Next Level" (Zen, once the goal is reached): ends the level the way a win does, then the next one starts.
func OnNextLevelPressed() -> void:
	Advancing = true
	WinSequence()


## A won level: once the last group's drop and refill are done, every piece explodes; when the shards have settled the next
## level starts (the last level is followed by the first).
func WinSequence() -> void:
	var Id := SequenceId
	if not await WaitForBoard(Id, 12.0, func() -> bool: return not View.Busy):
		return
	View.ExplodeAll()
	await get_tree().process_frame
	if not await WaitForBoard(Id, 12.0, ShardsSettled):
		return
	if LevelIndex >= 0 and not Is3D:
		LevelIndex = (LevelIndex + 1) % Levels.Count()
		Bar.LevelPicker.selected = LevelIndex + 1
	StartGame()


## Attract Mode's game: it goes on while any group can be removed, and is over as soon as none can. "Game over" shows, and after
## 2 seconds every piece explodes; when the shards have settled a new game fills the board with new pieces.
func OnNoPlayableGroups() -> void:
	if not Bar.AttractCheck.button_pressed:
		return
	var Id := SequenceId
	AttractGameOver = true
	await get_tree().create_timer(2.0).timeout
	if Id != SequenceId or not Bar.AttractCheck.button_pressed:
		AttractGameOver = false
		return
	View.ExplodeAll()
	await get_tree().process_frame
	var Settled := await WaitForBoard(Id, 12.0, ShardsSettled)
	AttractGameOver = false
	if Settled and Bar.AttractCheck.button_pressed:
		StartGame()


func ClearLevel() -> void:
	LevelIndex = -1
	Bar.LevelPicker.selected = 0


func OnLevelSelected(Index: int) -> void:
	LevelIndex = Index - 1
	Bar.AttractCheck.button_pressed = false
	if LevelIndex >= 0 and Is3D:
		Bar.BoardTypePicker.selected = 0
		SwitchBoardType(false)
	else:
		StartGame()


func OnBoardSet(Width: int, Height: int, Depth: int, NewColors: int, NewBlockers: int) -> void:
	Colors = NewColors
	GameSettings.Save("Colors", Colors)
	# A board set by hand is not a level.
	ClearLevel()
	if Is3D:
		Dimensions3D = Vector3i(Width, Height, Depth)
		GameSettings.Save("CubeWidth", Width)
		GameSettings.Save("CubeHeight", Height)
		GameSettings.Save("CubeDepth", Depth)
	else:
		Dimensions2D = Vector2i(Width, Height)
		Blockers = NewBlockers
		GameSettings.Save("Width", Width)
		GameSettings.Save("Height", Height)
		GameSettings.Save("Blockers", Blockers)
	StartGame()
