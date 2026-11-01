extends MainGame

## Start-up, input and the per-frame step.

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
	UpdateOrientation()
	get_window().size_changed.connect(UpdateOrientation)
	Board2D = BoardView.new()
	Board3D = CubeView.new()
	Board3D.Styles = Board2D.Styles
	for Board in [Board2D, Board3D]:
		Board.BoardRebuilt.connect(FrameCamera)
		Board.NoPlayableGroups.connect(OnNoPlayableGroups)
		Board.GroupRemoved.connect(Session.RecordRemoval)
		Board.PiecesExpired.connect(Session.RecordExpired)
	add_child(Session)
	PlayMode = clampi(int(GameSettings.Load("PlayMode", GameMode.Default)), 0, GameMode.Names.size() - 1) as GameMode.Kinds

	var Width := clampi(int(GameSettings.Load("Width", DefaultWidth)), 3, 15)
	var Height := clampi(int(GameSettings.Load("Height", DefaultHeight)), 3, 15)
	Colors = clampi(int(GameSettings.Load("Colors", DefaultColors)), 3, 8)
	Blockers = clampi(int(GameSettings.Load("Blockers", DefaultBlockers)), 0, 20)
	Dimensions2D = Vector2i(Width, Height)
	Layout = clampi(int(GameSettings.Load("BoardLayout", 0)), 0, BoardLayouts.Names().size() - 1)
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
		elif Argument.begins_with("--layout="):
			# Plays that irregular layout (by name, e.g. --layout=Ring) on the 2D board Settings, without saving the choice.
			Layout = maxi(BoardLayouts.Names().find(Argument.trim_prefix("--layout=")), 0)
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
	Bar.NextLevelPressed.connect(OnNextLevelPressed)
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
	Bar.LayoutSelected.connect(OnLayoutSelected)
	Bar.LevelsReloadPressed.connect(OnLevelsReloadPressed)
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
	Bar.MetallicToggled.connect(OnMetallicToggled)
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
	Bar.MetallicCheck.button_pressed = bool(GameSettings.Load("Metallic", false))
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
	Bar.NextButton.visible = Session.GoalMet and Session.CanPlay() and not Advancing and not Bar.AttractCheck.button_pressed and not Bar.Overlay.visible and not Bar.TestOverlay.visible
	Bar.SetLevel(Levels.All()[LevelIndex].Name if LevelIndex >= 0 and not Is3D else "")
	Bar.SetGoals(Session.Remaining, Session.GoalOrder, BlockStyles.Palette)
	Board2D.Hint.WantedKinds = Session.WantedKinds()
	Bar.SetGame(Session.ClockTitle(), Session.ClockText(), "Game over" if AttractGameOver else ("No More Moves, Reshuffling" if View.NoMovesNotice else Session.StatusText()))
	View.UserDown = -CameraNode.global_basis.y
	View.AttractActive = Bar.AttractCheck.button_pressed
	Bar.SetFps(int(Engine.get_frames_per_second()))
	if Bar.AttractCheck.button_pressed and not View.Busy and Session.CanPlay() and not Bar.TestOverlay.visible:
		AttractClock += Delta
		if AttractClock >= AttractDelay:
			AttractClock = 0.0
			View.AttractStep()
