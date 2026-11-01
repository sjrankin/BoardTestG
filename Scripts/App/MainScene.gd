class_name MainScene
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

const LandscapeBaseSize := Vector2i(1920, 1200)

const PortraitBaseSize := Vector2i(1200, 1920)

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
const MaliciousKeys: Array[String] = ["MaliciousLight", "MaliciousBlockers", "MaliciousVeil", "MaliciousTurn", "MaliciousSwap", "MaliciousFade", "MaliciousWhite"]

## The spinning light turns once round in this many seconds; the veil comes down every `VeilEvery` seconds and stays `VeilFor`.
const LightPeriod := 15.0

const VeilEvery := 20.0

const VeilFor := 10.0

var Malicious: Array[bool] = [false, false, false, false, false, false, false]

var LightAngle: float = 0.0

## The veil's clock (seconds of play) and when it next changes; whether it is down now.
var VeilClock: float = 0.0

var VeilNext: float = VeilEvery

var VeilShown: bool = false

## `--level=N` starts straight on that level instead of in Attract Mode (for captures).
var SkipTitle: bool = false

var CameraNode: Camera3D

var CameraDistance: float = 0.0

## True from a tap on Next Level until the next game starts (the button stays hidden meanwhile).
var Advancing: bool = false

var AttractClock: float = 0.0

var PressPosition: Vector2 = Vector2.ZERO

var Pressed: bool = false

var Dragging: bool = false

## The last tap that missed the board: when it happened (`Time.get_ticks_msec`, 0 = none) and where.
var LastMissTime: int = 0

var LastMissPosition: Vector2 = Vector2.ZERO

## The scene (camera, sky) and the Settings switches.

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


## Fits the layout to the window's shape, so the game plays upright and sideways on a phone or tablet (and in a tall desktop
## window). The interface is laid out for a 1920x1200 landscape window or a 1200x1920 portrait one, and the camera keeps the
## board's width in view when the window is taller than it is wide (it keeps the height otherwise).
func UpdateOrientation() -> void:
	var WindowSize := get_window().size
	var Portrait := WindowSize.y > WindowSize.x
	get_window().content_scale_size = PortraitBaseSize if Portrait else LandscapeBaseSize
	if CameraNode != null:
		CameraNode.keep_aspect = Camera3D.KEEP_WIDTH if Portrait else Camera3D.KEEP_HEIGHT
	if Bar != null:
		Bar.PlaceInsetsLater()


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


## Shows the size fields of the board being played.
func ShowBoardType() -> void:
	if Is3D:
		Bar.ShowBoardType(true, Dimensions3D.x, Dimensions3D.y, Dimensions3D.z, Blockers)
	else:
		Bar.ShowBoardType(false, Dimensions2D.x, Dimensions2D.y, Dimensions3D.z, Blockers)


## How many groups (colors) the game being started has: the level's, else the Settings value.
func ActiveGroups() -> int:
	if LevelIndex >= 0 and not Is3D and Levels.All()[LevelIndex].ColorCount > 0:
		return Levels.All()[LevelIndex].ColorCount
	return Colors


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


func OnMetallicToggled(On: bool) -> void:
	Board2D.Styles.SetMetallic(On)
	SceneSetup.SetMetallic(On)
	GameSettings.Save("Metallic", On)


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
