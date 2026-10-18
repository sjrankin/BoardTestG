class_name CaptureRunner
extends Node
## A visual check without a person at the keyboard. Run the game with user arguments after `--`:
##
##   --capture=DIR   play in Attract Mode, press Shuffle early, save screenshots into DIR, then quit
##   --shape=N       start with block shape N (0 cube, 1 sphere, 2 cone, 3 cylinder, 4 glow)
##   --yaw=DEG --tilt=DEG   start with the board turned
##   --rotate        start with Auto Rotate on
##   --lightning     with --capture, just clear one group and save screenshots through the lightning, then quit
##   --burst         with --capture, also save a screenshot every few frames from frame 120 to 260 (to catch an effect)

## The frames at which a screenshot is saved, and when the run ends.
const ShotFrames: Array[int] = [20, 35, 150, 330, 900]
const LastFrame := 905

var View: BoardView
var Bar: ControlBar
var Directory: String = ""
var Burst: bool = false
var LightningDemo: bool = false
var FrameCount: int = 0


## Set by `--burst` while the arguments are read.
static var BurstRequested: bool = false
static var LightningRequested: bool = false


## Applies the startup options to the board and controls. Returns a runner if `--capture` was given, else null.
static func FromCommandLine(TheView: BoardView, TheBar: ControlBar) -> CaptureRunner:
	var Runner: CaptureRunner = null
	for Argument in OS.get_cmdline_user_args():
		if Argument.begins_with("--shape="):
			TheBar.ShapePicker.selected = int(Argument.trim_prefix("--shape="))
			TheView.SetBlockShape(TheBar.ShapePicker.selected)
		elif Argument.begins_with("--yaw="):
			TheView.Yaw = deg_to_rad(float(Argument.trim_prefix("--yaw=")))
			TheView.ApplyRotation()
		elif Argument.begins_with("--tilt="):
			TheView.Tilt = deg_to_rad(float(Argument.trim_prefix("--tilt=")))
			TheView.ApplyRotation()
		elif Argument == "--lightning":
			LightningRequested = true
		elif Argument == "--burst":
			BurstRequested = true
		elif Argument == "--rotate":
			TheBar.AutoRotateCheck.button_pressed = true
		elif Argument.begins_with("--capture="):
			Runner = CaptureRunner.new()
			Runner.View = TheView
			Runner.Bar = TheBar
			Runner.Directory = Argument.trim_prefix("--capture=")
			Runner.Burst = BurstRequested
			Runner.LightningDemo = LightningRequested
			DirAccess.make_dir_recursive_absolute(Runner.Directory)
			TheBar.AttractCheck.button_pressed = not LightningRequested
	return Runner


func _process(_Delta: float) -> void:
	FrameCount += 1
	if LightningDemo:
		RunLightningDemo()
		return
	if FrameCount == 2:
		Bar.AttractCheck.button_pressed = false
	if FrameCount == 8:
		View.ShuffleNow()
	if FrameCount == 120:
		Bar.AttractCheck.button_pressed = true
	if FrameCount in ShotFrames or (Burst and FrameCount >= 120 and FrameCount <= 260 and FrameCount % 3 == 0):
		var Shot := get_viewport().get_texture().get_image()
		Shot.save_png("%s/Shot%04d.png" % [Directory, FrameCount])
	if FrameCount > LastFrame:
		print("Score after the run: ", View.Model.Score)
		get_tree().quit()


## One group cleared at frame 30, then a screenshot every second frame through the lightning and the pieces leaving.
func RunLightningDemo() -> void:
	if FrameCount == 30:
		View.AttractStep()
	if FrameCount >= 31 and FrameCount <= 60 and FrameCount % 2 == 0:
		var Shot := get_viewport().get_texture().get_image()
		Shot.save_png("%s/Bolt%04d.png" % [Directory, FrameCount])
	if FrameCount > 62:
		get_tree().quit()
