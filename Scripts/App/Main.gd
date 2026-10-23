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
var PlayMode: GameMode.Kinds = GameMode.Default
## Which of `Levels.All()` is being played; -1 plays the board set in Settings with the default level. Every launch starts on
## Level 1 (on the 2D board, as levels are 2D).
var LevelIndex: int = 0
var CameraNode: Camera3D
var CameraDistance: float = 0.0
var AttractClock: float = 0.0
var PressPosition: Vector2 = Vector2.ZERO
var Pressed: bool = false
var Dragging: bool = false


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
					View.HandleTapRay(CameraNode.project_ray_origin(Event.position), CameraNode.project_ray_normal(Event.position))
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


func _process(Delta: float) -> void:
	Session.Paused = Bar.Overlay.visible
	Bar.SetGoals(Session.Remaining, Session.GoalOrder, BlockStyles.Palette)
	Board2D.Hint.WantedKinds = Session.WantedKinds()
	Bar.SetGame(Session.ClockTitle(), Session.ClockText(), Session.StatusText())
	View.UserDown = -CameraNode.global_basis.y
	View.AttractActive = Bar.AttractCheck.button_pressed
	Bar.SetFps(int(Engine.get_frames_per_second()))
	if Bar.AttractCheck.button_pressed and not View.Busy and Session.CanPlay():
		AttractClock += Delta
		if AttractClock >= AttractDelay:
			AttractClock = 0.0
			View.AttractStep()
