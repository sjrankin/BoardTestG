extends Node3D
## BoardTestG - the 2D board of BoardTestRK, in Godot. Builds the whole scene in code and connects the parts:
## `SceneSetup` (sky, light, camera, floor), `BoardView` (the board; its rules are in `BoardModel`), `ControlBar` (the
## controls), `GameSettings` (what is remembered). It also turns the mouse into taps, turns and zoom.

const DefaultWidth := 11
const DefaultHeight := 11
const DefaultColors := 5
const DefaultBlockers := 0
const AttractDelay := 0.25
## The frame-rate limit a phone or tablet starts with (per second).
const DefaultMobileFrameRate := 60
## The 3D scene is drawn at least this many pixels tall before being scaled down to the window, whatever the window's
## size: a small window gets more supersampling, a window already this tall gets none.
const TargetRenderHeight := 2400.0
const MaxSuperSampling := 2.0
## A press that moves more than this many pixels is a turn of the board, not a tap.
const DragThreshold := 6.0
## Two taps this close in time (milliseconds) and place (pixels) are a double tap.
const DoubleTapTime := 400
const DoubleTapDistance := 40.0
const DragRadiansPerPixel := 0.008
const MinCameraDistance := 4.0
const MaxCameraDistance := 60.0

## The two boards: the 2D board and the 3D cube. `View` is the one being played (the other is out of the scene); both have the
## same outside, so most of this file does not care which.
var Board2D: BoardView
var Board3D: CubeView
var View
var Is3D: bool = false
var Dimensions2D := Vector2i(DefaultWidth, DefaultHeight)
var Dimensions3D := Vector3i(DefaultWidth, DefaultHeight, DefaultWidth)
var Colors: int = DefaultColors
var Blockers: int = DefaultBlockers
var Bar: ControlBar
## The game in progress: play mode, level, turns and time.
var Session := GameSession.new()
var Difficulty := DifficultyRun.new()
var PlayMode: GameMode.Kinds = GameMode.Default
## Which of `Levels.All()` is being played; -1 plays the board set in Settings with the default level. Every launch starts on
## Level 1 (on the 2D board, as levels are 2D).
var LevelIndex: int = 0
## Bumped by every new game, so a win or loss waiting to carry on (`WinSequence`) knows its game is gone.
var SequenceId: int = 0
## The level the Play button starts: Level 1 at first, then the level the player was on when Attract Mode came on (a failed
## level they declined to replay, or the one they were playing when they turned it on).
var ResumeLevel: int = 0
## Attract Mode: the game just ended (no group left to remove) and the next one has not started.
var AttractGameOver: bool = false
## The Settings > Malicious switches (see `ControlBar.MaliciousToggled`) and the GameSettings key each is saved under.
const MaliciousKeys: Array[String] = ["MaliciousLight", "MaliciousBlockers", "MaliciousVeil", "MaliciousTurn"]
## The spinning light turns once round in this many seconds; the veil comes down every `VeilEvery` seconds and stays `VeilFor`.
const LightPeriod := 30.0
const VeilEvery := 20.0
const VeilFor := 10.0
var Malicious: Array[bool] = [false, false, false, false]
var LightAngle: float = 0.0
## The veil's clock (seconds of play) and when it next changes; whether it is down now.
var VeilClock: float = 0.0
var VeilNext: float = VeilEvery
var VeilShown: bool = false
## `--level=N` starts straight on that level instead of in Attract Mode (for captures).
var SkipTitle: bool = false
var CameraNode: Camera3D
var CameraDistance: float = 0.0
var AttractClock: float = 0.0
var PressPosition: Vector2 = Vector2.ZERO
var Pressed: bool = false
var Dragging: bool = false
## The last tap that missed the board: when it happened (`Time.get_ticks_msec`, 0 = none) and where.
var LastMissTime: int = 0
var LastMissPosition: Vector2 = Vector2.ZERO


func _ready() -> void:
	UpdateSuperSampling()
	get_window().size_changed.connect(UpdateSuperSampling)
	CameraNode = SceneSetup.BuildEnvironment(self)
	var Background := clampi(int(GameSettings.Load("Background", Backgrounds.Kinds.Gray)), 0, Backgrounds.Names.size() - 1)
	for Argument in OS.get_cmdline_user_args():
		if Argument.begins_with("--background="):
			Background = clampi(int(Argument.trim_prefix("--background=")), 0, Backgrounds.Names.size() - 1)
	SceneSetup.BackgroundKind = Background
	SceneSetup.BuildFloor(self)
	UpdateBackgroundAspect()
	get_viewport().size_changed.connect(UpdateBackgroundAspect)
	Board2D = BoardView.new()
	Board3D = CubeView.new()
	Board3D.Styles = Board2D.Styles
	for Board in [Board2D, Board3D]:
		Board.BoardRebuilt.connect(FrameCamera)
		Board.NoPlayableGroups.connect(OnNoPlayableGroups)
		Board.GroupRemoved.connect(Session.RecordRemoval)
	add_child(Session)
	PlayMode = clampi(int(GameSettings.Load("PlayMode", GameMode.Default)), 0, GameMode.Names.size() - 1) as GameMode.Kinds

	var Width := clampi(int(GameSettings.Load("Width", DefaultWidth)), 3, 15)
	var Height := clampi(int(GameSettings.Load("Height", DefaultHeight)), 3, 15)
	Colors = clampi(int(GameSettings.Load("Colors", DefaultColors)), 3, 8)
	Blockers = clampi(int(GameSettings.Load("Blockers", DefaultBlockers)), 0, 20)
	Dimensions2D = Vector2i(Width, Height)
	Dimensions3D = Vector3i(clampi(int(GameSettings.Load("CubeWidth", DefaultWidth)), 3, 15), clampi(int(GameSettings.Load("CubeHeight", DefaultHeight)), 3, 15), clampi(int(GameSettings.Load("CubeDepth", DefaultWidth)), 3, 15))
	Is3D = false
	LevelIndex = 0
	for Argument in OS.get_cmdline_user_args():
		if Argument == "--cube":
			Is3D = true
		elif Argument.begins_with("--level="):
			# Plays that level (1 to 10) on the 2D board.
			LevelIndex = clampi(int(Argument.trim_prefix("--level=")) - 1, -1, Levels.Count() - 1)
			Is3D = LevelIndex < 0 and Is3D
			SkipTitle = true
		elif Argument.begins_with("--dims="):
			var Parts := Argument.trim_prefix("--dims=").split("x")
			if Parts.size() == 3:
				Dimensions3D = Vector3i(clampi(int(Parts[0]), 3, 15), clampi(int(Parts[1]), 3, 15), clampi(int(Parts[2]), 3, 15))
	var ShapeIndex := int(GameSettings.Load("BlockShape", 0))
	var Speed := clampf(float(GameSettings.Load("RemovalSpeed", 1.0)), ControlBar.MinRemovalSpeed, ControlBar.MaxRemovalSpeed)
	var Lightning := bool(GameSettings.Load("Lightning", true))
	var BlockerZaps := bool(GameSettings.Load("BlockerZaps", true))
	var Specular := bool(GameSettings.Load("Specular", false))
	# A phone or tablet (which may run at 120 Hz) gets a 60 per second limit unless the user picks otherwise: drawing
	# faster only makes the device warm and drains the battery. Elsewhere there is no limit.
	var RemovalEffect := int(GameSettings.Load("RemovalEffect", 0))
	var FrameRate := int(GameSettings.Load("FrameRate", DefaultMobileFrameRate if OS.has_feature("mobile") else 0))
	Engine.max_fps = FrameRate
	Bar = ControlBar.new()
	add_child(Bar)
	Bar.Setup(Width, Height, Colors, Blockers, ShapeIndex, Speed, Lightning, BlockerZaps, Specular, FrameRate, RemovalEffect, BlockStyles.ShapeNames)
	Bar.GameModePicker.selected = PlayMode
	if Is3D:
		LevelIndex = -1
	Bar.LevelPicker.selected = LevelIndex + 1
	Bar.GameModeSelected.connect(OnGameModeSelected)
	Bar.LevelSelected.connect(OnLevelSelected)
	# The game starts in Attract Mode (on the Settings board) with a Play button; Play begins Level 1.
	ResumeLevel = maxi(LevelIndex, 0)
	if not SkipTitle:
		LevelIndex = -1
		Bar.LevelPicker.selected = 0
		Bar.AttractCheck.button_pressed = true
	Bar.AttractCheck.toggled.connect(OnAttractToggled)
	for Index in MaliciousKeys.size():
		Malicious[Index] = bool(GameSettings.Load(MaliciousKeys[Index], false))
		Bar.MaliciousChecks[Index].button_pressed = Malicious[Index]
	Bar.MaliciousToggled.connect(OnMaliciousToggled)
	Bar.PlayPressed.connect(func() -> void: OnLevelSelected(ResumeLevel + 1))
	Bar.ReplayAnswered.connect(OnReplayAnswered)
	add_child(Difficulty)
	Bar.DifficultyStartPressed.connect(func() -> void:
		Bar.TestOverlay.Begin()
		Difficulty.Start())
	Difficulty.Progress.connect(Bar.TestOverlay.ShowProgress)
	Difficulty.LevelDone.connect(Bar.TestOverlay.ShowResult)
	Difficulty.Finished.connect(Bar.TestOverlay.Finish)
	Bar.TestOverlay.ClosePressed.connect(func() -> void:
		if Difficulty.Running:
			Difficulty.Cancelled = true
		else:
			Bar.TestOverlay.visible = false)
	Session.StateChanged.connect(OnSessionState)
	Bar.BoardTypeSelected.connect(func(Index: int) -> void: SwitchBoardType(Index == 1))
	Bar.AttractSpinToggled.connect(OnAttractSpinToggled)
	Bar.ShapeSelected.connect(OnShapeSelected)
	Bar.ShufflePressed.connect(func() -> void: View.ShuffleNow())
	Bar.RecenterPressed.connect(OnRecenterPressed)
	Bar.AutoRotateToggled.connect(func(On: bool) -> void: Both("AutoRotate", On))
	Bar.BoardSetPressed.connect(OnBoardSet)
	Bar.RemovalSpeedChanged.connect(OnRemovalSpeedChanged)
	Bar.LightningToggled.connect(OnLightningToggled)
	Bar.BlockerZapsToggled.connect(OnBlockerZapsToggled)
	Bar.SpecularToggled.connect(OnSpecularToggled)
	Bar.FrameRateChanged.connect(OnFrameRateChanged)
	Bar.ScreenshotPressed.connect(TakeScreenshot)
	Bar.RemovalEffectChanged.connect(OnRemovalEffectChanged)
	var AttractSpin := bool(GameSettings.Load("AttractSpin", true))
	Bar.AttractSpinCheck.button_pressed = AttractSpin
	Board3D.AttractSpin = AttractSpin
	Both("RemovalSpeed", Speed)
	Both("LightningEnabled", Lightning)
	Both("RemovalEffect", RemovalEffect)
	Both("BlockerZapsEnabled", BlockerZaps)
	Board2D.Styles.SetSpecular(Specular)
	SceneSetup.SetSpecular(Specular)
	SceneSetup.SetBackground(Background)
	Bar.BackgroundPicker.selected = Background
	Bar.BackgroundSelected.connect(OnBackgroundSelected)
	Board2D.Styles.CurrentShape = clampi(ShapeIndex, 0, BlockStyles.Shapes.size() - 1)
	View = Board3D if Is3D else Board2D
	add_child(View)
	View.SetBlockShape(ShapeIndex)
	for Index in MaliciousKeys.size():
		if Malicious[Index]:
			ApplyMalicious(Index)
	ShowBoardType()
	StartGame()

	var Runner := CaptureRunner.FromCommandLine(View, Bar)
	if Runner != null:
		add_child(Runner)


# MARK: Scene

## Keeps edges smooth at any window size. Resizing the window changes how many pixels the 3D scene gets, and the
## edge smoothing (MSAA) alone is not enough when the scene is drawn at a low resolution, so the scene is drawn
## larger than the window when the window is small, and scaled down - supersampling.
func UpdateSuperSampling() -> void:
	# A phone's GPU can't afford drawing the scene at twice the screen's size (nor 8x MSAA): draw it at the screen's own size.
	if OS.has_feature("ios"):
		get_viewport().scaling_3d_scale = 1.0
		get_viewport().msaa_3d = Viewport.MSAA_4X
		return
	var PixelHeight := float(maxi(DisplayServer.window_get_size().y, 1))
	get_viewport().scaling_3d_scale = clampf(TargetRenderHeight / PixelHeight, 1.0, MaxSuperSampling)


## Backs the camera off far enough to see the whole board, aimed at its middle.
func FrameCamera() -> void:
	CameraDistance = View.FrameDistance()
	PlaceCamera()


func PlaceCamera() -> void:
	var Middle: Vector3 = View.FrameMiddle()
	CameraNode.position = Middle + Vector3(0, CameraDistance * 0.34, CameraDistance)
	CameraNode.look_at(Middle, Vector3.UP)


# MARK: Controls

## Tells the sky shaders the window's shape.
func UpdateBackgroundAspect() -> void:
	var Size := get_viewport().get_visible_rect().size
	Backgrounds.SetAspect(Size.x / maxf(Size.y, 1.0))


func OnBackgroundSelected(Index: int) -> void:
	SceneSetup.SetBackground(Index)
	GameSettings.Save("Background", Index)


func OnShapeSelected(Index: int) -> void:
	View.SetBlockShape(Index)
	GameSettings.Save("BlockShape", Index)


func OnRecenterPressed() -> void:
	Bar.AutoRotateCheck.button_pressed = false
	View.Recenter()


## Applies a setting to both boards (the one not being played keeps it for when it is switched to).
func Both(Name: String, Value: Variant) -> void:
	Board2D.set(Name, Value)
	Board3D.set(Name, Value)


## Starts a new game on the board being played, with its own size.
func StartGame() -> void:
	SequenceId += 1
	VeilShown = false
	VeilClock = 0.0
	VeilNext = VeilEvery
	Bar.ShowReplayPrompt(false)
	Bar.ClearGoals()
	if LevelIndex >= 0 and not Is3D:
		var Level := Levels.All()[LevelIndex]
		Session.Start(PlayMode, Level)
		View.NewGame(Level.Dimensions.x, Level.Dimensions.y, Level.ColorCount, Level.PresetBlockers.size(), Level.PresetBlockers)
		return
	Session.Start(PlayMode, LevelDefinition.Default(Is3D, Dimensions3D if Is3D else Vector3i(Dimensions2D.x, Dimensions2D.y, 0)))
	if Is3D:
		View.NewGame(Dimensions3D.x, Dimensions3D.y, Dimensions3D.z, Colors)
	else:
		View.NewGame(Dimensions2D.x, Dimensions2D.y, Colors, Blockers)


## Shows the size fields of the board being played.
func ShowBoardType() -> void:
	if Is3D:
		Bar.ShowBoardType(true, Dimensions3D.x, Dimensions3D.y, Dimensions3D.z, Blockers)
	else:
		Bar.ShowBoardType(false, Dimensions2D.x, Dimensions2D.y, Dimensions3D.z, Blockers)


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


## Plays level `Index` (0 is "no level": the Settings board). Levels are 2D, so this switches to the 2D board.
## Attract Mode plays the board the Settings window shows (its size, colors and Blockers; the block shape is already shared),
## not a level's: turning it on starts a new game with those values.
func OnMaliciousToggled(Index: int, On: bool) -> void:
	Malicious[Index] = On
	GameSettings.Save(MaliciousKeys[Index], On)
	ApplyMalicious(Index)


func ApplyMalicious(Index: int) -> void:
	var On := Malicious[Index]
	match Index:
		0:
			if not On:
				LightAngle = 0.0
				SceneSetup.Sun.rotation_degrees = SceneSetup.SunDirection
		1:
			Board2D.BlockersMove = On
		2:
			if not On and VeilShown:
				View.VeilOff()
				VeilShown = false
			VeilClock = 0.0
			VeilNext = VeilEvery
		3:
			Board2D.SetTurnLocked(On)
			Board3D.SetTurnLocked(On)
			if On:
				Bar.AutoRotateCheck.button_pressed = false
			Bar.AutoRotateCheck.disabled = On


## The veil comes down over every piece of one color: a color the goal still needs, if there is one, else any on the board.
func ShowVeil() -> void:
	var Kinds: Array[int] = Session.WantedKinds()
	if Kinds.is_empty():
		for Node in View.PieceNodes.values():
			if is_instance_valid(Node) and not Kinds.has(Node.get_meta("Kind")):
				Kinds.append(Node.get_meta("Kind"))
	if Kinds.is_empty():
		return
	View.VeilOn(Kinds.pick_random())
	VeilShown = true


func HideVeil() -> void:
	View.VeilOff()
	VeilShown = false


## Malicious, once a frame: the spinning light and the veil's timing.
func MaliciousStep(Delta: float) -> void:
	if Malicious[0]:
		LightAngle = fmod(LightAngle + TAU / LightPeriod * Delta, TAU)
		SceneSetup.Sun.rotation = Vector3(deg_to_rad(SceneSetup.SunDirection.x), deg_to_rad(SceneSetup.SunDirection.y) + LightAngle, 0.0)
	if Malicious[2] and Session.CanPlay() and not Bar.Overlay.visible and not Bar.TestOverlay.visible and not AttractGameOver:
		VeilClock += Delta
		if VeilClock >= VeilNext:
			if VeilShown:
				HideVeil()
			else:
				ShowVeil()
			VeilNext += VeilFor if VeilShown else VeilEvery - VeilFor


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


## Saves the game's picture (without the on-screen controls) as a PNG in the Pictures folder, named with the date and time.
func TakeScreenshot() -> void:
	Bar.visible = false
	await RenderingServer.frame_post_draw
	var Picture := get_viewport().get_texture().get_image()
	Bar.visible = true
	var Folder := OS.get_system_dir(OS.SYSTEM_DIR_PICTURES)
	if Folder.is_empty():
		Folder = OS.get_user_data_dir()
	var Stamp := Time.get_datetime_string_from_system().replace(":", "-").replace("T", " ")
	var Path := "%s/BoardTestG %s.png" % [Folder, Stamp]
	var Result := Picture.save_png(Path)
	print("Screenshot ", "saved to " + Path if Result == OK else "failed (%d)" % Result)


func OnRemovalEffectChanged(Index: int) -> void:
	Both("RemovalEffect", Index)
	GameSettings.Save("RemovalEffect", Index)


func OnFrameRateChanged(Limit: int) -> void:
	Engine.max_fps = Limit
	GameSettings.Save("FrameRate", Limit)


func OnSpecularToggled(On: bool) -> void:
	Board2D.Styles.SetSpecular(On)
	SceneSetup.SetSpecular(On)
	GameSettings.Save("Specular", On)


func OnBlockerZapsToggled(On: bool) -> void:
	Board2D.SetBlockerZaps(On)
	Board3D.SetBlockerZaps(On)
	GameSettings.Save("BlockerZaps", On)


func OnAttractSpinToggled(On: bool) -> void:
	Board3D.AttractSpin = On
	GameSettings.Save("AttractSpin", On)


func OnLightningToggled(On: bool) -> void:
	Both("LightningEnabled", On)
	GameSettings.Save("Lightning", On)


## Applies the slider's value to every piece removed from now on, and remembers it between launches.
func OnRemovalSpeedChanged(Value: float) -> void:
	Both("RemovalSpeed", Value)
	GameSettings.Save("RemovalSpeed", Value)


# MARK: Input and per-frame

## What counts as the player being there, for the idle hint's clock: a click or wheel turn, a drag (the mouse moving with a
## button held), a key, or a touch. The mouse merely moving with nothing pressed does not. None of it removes a hint that is
## already showing - only a tap on a piece of the board does (`BoardView.HandleTapRay`).
func _input(Event: InputEvent) -> void:
	var Counts := false
	if Event is InputEventMouseButton or Event is InputEventKey or Event is InputEventScreenTouch or Event is InputEventScreenDrag:
		Counts = true
	elif Event is InputEventMouseMotion and Event.button_mask != 0:
		Counts = true
	if Counts and View is BoardView:
		View.Hint.RecordActivity()


func _unhandled_input(Event: InputEvent) -> void:
	# While the Settings window is open the board behind it ignores the mouse: no taps, turns or zoom.
	if Bar.Overlay.visible:
		Pressed = false
		Dragging = false
		return
	if Event is InputEventMouseButton:
		if Event.button_index == MOUSE_BUTTON_LEFT:
			if Event.pressed:
				Pressed = true
				Dragging = false
				PressPosition = Event.position
			else:
				# A press and release without much movement in between is a tap; otherwise it was a turn.
				if Pressed and not Dragging:
					OnTap(Event.position)
				Pressed = false
				Dragging = false
		elif Event.pressed and Event.button_index == MOUSE_BUTTON_WHEEL_UP:
			CameraDistance = maxf(CameraDistance * 0.93, MinCameraDistance)
			PlaceCamera()
		elif Event.pressed and Event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			CameraDistance = minf(CameraDistance * 1.07, MaxCameraDistance)
			PlaceCamera()
	elif Event is InputEventMouseMotion and Pressed:
		if not Dragging and Event.position.distance_to(PressPosition) > DragThreshold:
			Dragging = true
			Bar.AutoRotateCheck.button_pressed = false
		if Dragging:
			View.RotateBy(Event.relative.x * DragRadiansPerPixel, Event.relative.y * DragRadiansPerPixel)


## A press and release without a turn in between. A tap on the board plays it (the board ignores it while the game is locked);
## two quick taps in the view but off the board recenter the board, as the Recenter button does.
func OnTap(At: Vector2) -> void:
	var Origin := CameraNode.project_ray_origin(At)
	var Direction := CameraNode.project_ray_normal(At)
	if View.HitsBoard(Origin, Direction):
		LastMissTime = 0
		View.HandleTapRay(Origin, Direction)
		return
	var Now := Time.get_ticks_msec()
	if LastMissTime > 0 and Now - LastMissTime <= DoubleTapTime and At.distance_to(LastMissPosition) <= DoubleTapDistance:
		LastMissTime = 0
		OnRecenterPressed()
	else:
		LastMissTime = Now
		LastMissPosition = At


func _process(Delta: float) -> void:
	MaliciousStep(Delta)
	Session.Paused = Bar.Overlay.visible or Bar.TestOverlay.visible
	Session.Unlimited = Bar.AttractCheck.button_pressed
	Board2D.InputLocked = not Session.CanPlay()
	Board3D.InputLocked = Board2D.InputLocked
	# In Attract Mode (the title state) the game's goal and clock are hidden and the Play button is shown.
	Bar.PlayButton.visible = Bar.AttractCheck.button_pressed and not Bar.Overlay.visible and not Bar.TestOverlay.visible
	Bar.Readouts.visible = not Bar.AttractCheck.button_pressed
	Bar.SetLevel("Level %d" % (LevelIndex + 1) if LevelIndex >= 0 and not Is3D else "")
	Bar.SetGoals(Session.Remaining, Session.GoalOrder, BlockStyles.Palette)
	Board2D.Hint.WantedKinds = Session.WantedKinds()
	Bar.SetGame(Session.ClockTitle(), Session.ClockText(), "Game over" if AttractGameOver else Session.StatusText())
	View.UserDown = -CameraNode.global_basis.y
	View.AttractActive = Bar.AttractCheck.button_pressed
	Bar.SetFps(int(Engine.get_frames_per_second()))
	if Bar.AttractCheck.button_pressed and not View.Busy and Session.CanPlay() and not Bar.TestOverlay.visible:
		AttractClock += Delta
		if AttractClock >= AttractDelay:
			AttractClock = 0.0
			View.AttractStep()
