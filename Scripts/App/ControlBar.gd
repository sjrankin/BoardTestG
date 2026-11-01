class_name ControlBar
extends ControlBarSettings

## Builds the controls with their starting values.
func Setup(Width: int, Height: int, Colors: int, Blockers: int, ShapeIndex: int, RemovalSpeed: float, Lightning: bool, BlockerZaps: bool, Specular: bool, FrameRate: int, RemovalEffect: int, ShapeNames: Array[String]) -> void:
	BuildReadouts()
	BuildGear()
	BuildReplayPrompt()
	BuildPlayButton()
	NextButton = BuildBigButton("Next Level", 340.0, func() -> void: NextLevelPressed.emit())
	TestOverlay = DifficultyOverlay.new()
	if OS.get_name() == "macOS":
		BuildCamera()
	BuildSettingsWindow(Width, Height, Colors, Blockers, ShapeIndex, RemovalSpeed, Lightning, BlockerZaps, Specular, FrameRate, RemovalEffect, ShapeNames)
	# The safe area and the stretched viewport settle a moment after the window changes size (a phone turned on its side), so
	# the insets are worked out once the frame is over, and again when the viewport itself changes.
	get_window().size_changed.connect(PlaceInsetsLater)
	add_child(TestOverlay)
	PlaceInsets()
