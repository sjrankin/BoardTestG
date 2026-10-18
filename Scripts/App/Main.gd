extends Node3D
## BoardTestG - the 2D board of BoardTestRK, in Godot. Builds the whole scene in code and connects the parts:
## `SceneSetup` (sky, light, camera, floor), `BoardView` (the board; its rules are in `BoardModel`), `ControlBar` (the
## controls), `GameSettings` (what is remembered). It also turns the mouse into taps, turns and zoom.

const DefaultWidth := 11
const DefaultHeight := 11
const DefaultColors := 5
const DefaultBlockers := 0
const AttractDelay := 0.25
## The 3D scene is drawn at least this many pixels tall before being scaled down to the window, whatever the window's
## size: a small window gets more supersampling, a window already this tall gets none.
const TargetRenderHeight := 2400.0
const MaxSuperSampling := 2.0
## A press that moves more than this many pixels is a turn of the board, not a tap.
const DragThreshold := 6.0
const DragRadiansPerPixel := 0.008
const MinCameraDistance := 4.0
const MaxCameraDistance := 60.0

var View: BoardView
var Bar: ControlBar
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
	SceneSetup.BuildFloor(self)
	View = BoardView.new()
	add_child(View)
	View.ScoreChanged.connect(func(Score: int) -> void: Bar.SetScore(Score))
	View.BoardRebuilt.connect(FrameCamera)

	var Width := clampi(int(GameSettings.Load("Width", DefaultWidth)), 3, 15)
	var Height := clampi(int(GameSettings.Load("Height", DefaultHeight)), 3, 15)
	var Colors := clampi(int(GameSettings.Load("Colors", DefaultColors)), 3, 8)
	var Blockers := clampi(int(GameSettings.Load("Blockers", DefaultBlockers)), 0, 20)
	var ShapeIndex := int(GameSettings.Load("BlockShape", 0))
	var Speed := clampf(float(GameSettings.Load("RemovalSpeed", 1.0)), ControlBar.MinRemovalSpeed, ControlBar.MaxRemovalSpeed)
	var Lightning := bool(GameSettings.Load("Lightning", true))
	Bar = ControlBar.new()
	add_child(Bar)
	Bar.Setup(Width, Height, Colors, Blockers, ShapeIndex, Speed, Lightning, BlockStyles.ShapeNames)
	Bar.ShapeSelected.connect(OnShapeSelected)
	Bar.ShufflePressed.connect(func() -> void: View.ShuffleNow())
	Bar.RecenterPressed.connect(OnRecenterPressed)
	Bar.AutoRotateToggled.connect(func(On: bool) -> void: View.AutoRotate = On)
	Bar.BoardSetPressed.connect(OnBoardSet)
	Bar.RemovalSpeedChanged.connect(OnRemovalSpeedChanged)
	Bar.LightningToggled.connect(OnLightningToggled)
	View.RemovalSpeed = Speed
	View.LightningEnabled = Lightning
	View.SetBlockShape(ShapeIndex)
	View.NewGame(Width, Height, Colors, Blockers)

	var Runner := CaptureRunner.FromCommandLine(View, Bar)
	if Runner != null:
		add_child(Runner)


# MARK: Scene

## Keeps edges smooth at any window size. Resizing the window changes how many pixels the 3D scene gets, and the
## edge smoothing (MSAA) alone is not enough when the scene is drawn at a low resolution, so the scene is drawn
## larger than the window when the window is small, and scaled down - supersampling.
func UpdateSuperSampling() -> void:
	var PixelHeight := float(maxi(DisplayServer.window_get_size().y, 1))
	get_viewport().scaling_3d_scale = clampf(TargetRenderHeight / PixelHeight, 1.0, MaxSuperSampling)


## Backs the camera off far enough to see the whole board, aimed at its middle.
func FrameCamera() -> void:
	CameraDistance = maxf(View.Model.Width, View.Model.Height) * 2.5
	PlaceCamera()


func PlaceCamera() -> void:
	var Middle := Vector3(0, View.Model.Height * 0.38, 0)
	CameraNode.position = Middle + Vector3(0, CameraDistance * 0.34, CameraDistance)
	CameraNode.look_at(Middle, Vector3.UP)


# MARK: Controls

func OnShapeSelected(Index: int) -> void:
	View.SetBlockShape(Index)
	GameSettings.Save("BlockShape", Index)


func OnRecenterPressed() -> void:
	Bar.AutoRotateCheck.button_pressed = false
	View.Recenter()


func OnBoardSet(Width: int, Height: int, Colors: int, Blockers: int) -> void:
	GameSettings.Save("Width", Width)
	GameSettings.Save("Height", Height)
	GameSettings.Save("Colors", Colors)
	GameSettings.Save("Blockers", Blockers)
	View.NewGame(Width, Height, Colors, Blockers)


func OnLightningToggled(On: bool) -> void:
	View.LightningEnabled = On
	GameSettings.Save("Lightning", On)


## Applies the slider's value to every piece removed from now on, and remembers it between launches.
func OnRemovalSpeedChanged(Value: float) -> void:
	View.RemovalSpeed = Value
	GameSettings.Save("RemovalSpeed", Value)


# MARK: Input and per-frame

func _unhandled_input(Event: InputEvent) -> void:
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
	View.UserDown = -CameraNode.global_basis.y
	Bar.SetFps(int(Engine.get_frames_per_second()))
	if Bar.AttractCheck.button_pressed and not View.Busy:
		AttractClock += Delta
		if AttractClock >= AttractDelay:
			AttractClock = 0.0
			View.AttractStep()
