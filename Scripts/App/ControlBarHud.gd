class_name ControlBarHud
extends ControlBarRows

## The readouts, buttons and prompts around the board.

## Shows a badge for each goal color (`Remaining`: Kind -> pieces still to remove, `Order`: the kinds in the level's order,
## `Palette`: Kind -> color); a color that is done shows a checkmark in place of its number.
func SetGoals(Remaining: Dictionary, Order: Array[int], Palette: Array[Color]) -> void:
	for Kind in Order:
		var Left := int(Remaining[Kind])
		if not GoalBadges.has(Kind):
			var Badge := ColorGoalBadge.new()
			Badge.Tint = Palette[Kind]
			GoalBox.add_child(Badge)
			GoalBadges[Kind] = Badge
		(GoalBadges[Kind] as ColorGoalBadge).Remaining = Left


## Takes every badge away (a new game).
func ClearGoals() -> void:
	for Badge in GoalBadges.values():
		(Badge as Control).queue_free()
	GoalBadges.clear()


## The game's readouts: the clock (with its title, which depends on the play mode) and a status line.
func SetGame(ClockTitle: String, ClockText: String, StatusText: String) -> void:
	(ClockLabel.get_parent().get_child(0) as Label).text = ClockTitle
	ClockLabel.get_parent().visible = not ClockTitle.is_empty()
	ClockLabel.text = ClockText
	StatusLabel.text = StatusText


## The level's number, centered at the top ("" shows nothing).
func SetLevel(Text: String) -> void:
	LevelLabel.text = Text


func SetFps(Fps: int) -> void:
	FpsLabel.text = "FPS %d" % Fps


# MARK: The top of the screen

## The clock with the goal's color badges under it, large, at the top left; the frame rate small at the bottom right.
func BuildReadouts() -> void:
	Readouts = VBoxContainer.new()
	Readouts.mouse_filter = Control.MOUSE_FILTER_IGNORE
	Readouts.add_theme_constant_override("separation", 8)
	add_child(Readouts)
	ClockLabel = AddReadout("", "")
	GoalBox = VBoxContainer.new()
	GoalBox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	GoalBox.add_theme_constant_override("separation", 12)
	Readouts.add_child(GoalBox)
	FpsLabel = Label.new()
	FpsLabel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	FpsLabel.add_theme_font_size_override("font_size", 24)
	# An opaque plate, so the number can be read over any background.
	var Plate := StyleBoxFlat.new()
	Plate.bg_color = Color(0.1, 0.1, 0.13, 1.0)
	Plate.set_corner_radius_all(8)
	Plate.content_margin_left = 10.0
	Plate.content_margin_right = 10.0
	Plate.content_margin_top = 4.0
	Plate.content_margin_bottom = 4.0
	FpsLabel.add_theme_stylebox_override("normal", Plate)
	FpsLabel.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	FpsLabel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	FpsLabel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	add_child(FpsLabel)
	LevelLabel = AddTopCenterLabel(44, 10.0)
	StatusLabel = AddTopCenterLabel(56, 70.0)


## "Replay?  Yes  No", near the bottom of the window; hidden until a level is failed (`ShowReplayPrompt`).
func BuildReplayPrompt() -> void:
	# A strip across the bottom of the window with the panel centered in it; the strip lets clicks through, the panel does not.
	ReplayPrompt = CenterContainer.new()
	ReplayPrompt.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ReplayPrompt.visible = false
	add_child(ReplayPrompt)
	ReplayPrompt.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	ReplayPrompt.offset_top = -170.0
	ReplayPrompt.offset_bottom = -50.0
	var Panel := PanelContainer.new()
	var Back := StyleBoxFlat.new()
	Back.bg_color = Color(0.13, 0.14, 0.17, 0.92)
	Back.set_corner_radius_all(16)
	Back.set_content_margin_all(16)
	Panel.add_theme_stylebox_override("panel", Back)
	var Row := HBoxContainer.new()
	Row.add_theme_constant_override("separation", 20)
	var Question := Label.new()
	Question.text = "Replay?"
	Question.add_theme_font_size_override("font_size", 36)
	Question.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	Row.add_child(Question)
	for Answer in [true, false]:
		var Choice := Button.new()
		Choice.text = "Yes" if Answer else "No"
		Choice.custom_minimum_size = Vector2(130, 60)
		Choice.add_theme_font_size_override("font_size", 30)
		var Face := StyleBoxFlat.new()
		Face.bg_color = Color(0.2, 0.5, 0.9) if Answer else Color(0.3, 0.32, 0.38)
		Face.set_corner_radius_all(10)
		Choice.add_theme_stylebox_override("normal", Face)
		Choice.add_theme_stylebox_override("hover", Face)
		Choice.add_theme_stylebox_override("pressed", Face)
		Choice.pressed.connect(func() -> void:
			ReplayPrompt.visible = false
			ReplayAnswered.emit(Answer))
		Row.add_child(Choice)
	Panel.add_child(Row)
	ReplayPrompt.add_child(Panel)


## "Play", near the bottom of the window: shown while Attract Mode is on (the game's title state), `Main` decides when.
func BuildPlayButton() -> void:
	PlayButton = BuildBigButton("Play", 240.0, func() -> void: PlayPressed.emit())


## A large blue button, hidden until shown, centered near the bottom of the window.
func BuildBigButton(Text: String, ButtonWidth: float, OnPressed: Callable) -> Button:
	var Big := Button.new()
	Big.text = Text
	Big.visible = false
	Big.add_theme_font_size_override("font_size", 48)
	Big.custom_minimum_size = Vector2(ButtonWidth, 90)
	var Face := StyleBoxFlat.new()
	Face.bg_color = Color(0.2, 0.5, 0.9)
	Face.set_corner_radius_all(16)
	for Look in ["normal", "hover", "pressed", "focus"]:
		Big.add_theme_stylebox_override(Look, Face)
	Big.pressed.connect(OnPressed)
	add_child(Big)
	Big.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM, Control.PRESET_MODE_MINSIZE)
	Big.grow_horizontal = Control.GROW_DIRECTION_BOTH
	Big.grow_vertical = Control.GROW_DIRECTION_BEGIN
	Big.offset_bottom = -60.0
	Big.offset_top = -150.0
	Big.offset_left = -ButtonWidth / 2.0
	Big.offset_right = ButtonWidth / 2.0
	return Big


## While the "Replay?" question is up nothing else may be done: the Settings gear (and with it Shuffle, Attract Mode, the level
## and board pickers) is dimmed and does not answer until the question is.
func ShowReplayPrompt(On: bool) -> void:
	ReplayPrompt.visible = On
	Gear.disabled = On
	Gear.modulate.a = 0.35 if On else 1.0
	if Camera != null:
		Camera.disabled = On
		Camera.modulate.a = 0.35 if On else 1.0


## The gear that opens the settings window, at the top right.
func BuildGear() -> void:
	Gear = GearButton.new()
	Gear.anchor_left = 1.0
	Gear.anchor_right = 1.0
	Gear.custom_minimum_size = Vector2(GearSize, GearSize)
	Gear.pressed.connect(OpenSettings)
	add_child(Gear)


## The screenshot button, just under the gear. Only on a Mac: the pictures are saved to its Pictures folder.
func BuildCamera() -> void:
	Camera = CameraButton.new()
	Camera.anchor_left = 1.0
	Camera.anchor_right = 1.0
	Camera.custom_minimum_size = Vector2(GearSize, GearSize)
	Camera.tooltip_text = "Save a screenshot to your Pictures folder"
	Camera.pressed.connect(func() -> void: ScreenshotPressed.emit())
	add_child(Camera)


## Places the insets once the frame is over (the window is its own viewport, so one signal covers both).
func PlaceInsetsLater() -> void:
	PlaceInsets.call_deferred()


## Keeps the readouts and the gear clear of the status bar, the notch and the rounded corners on a phone or tablet. (On a
## desktop the window has none of those.)
func PlaceInsets() -> void:
	var Left := 0.0
	var Top := 0.0
	var Right := 0.0
	if OS.has_feature("ios") or OS.has_feature("android"):
		var Safe := DisplayServer.get_display_safe_area()
		var WindowSize := Vector2(DisplayServer.window_get_size())
		var Visible := get_viewport().get_visible_rect().size
		var Scale := WindowSize.y / maxf(Visible.y, 1.0)
		if Safe.size.x > 0 and Scale > 0.0:
			Left = Safe.position.x / Scale
			Top = Safe.position.y / Scale
			Right = maxf(WindowSize.x - Safe.end.x, 0.0) / Scale
			# A cutout or gesture bar may be on either side once the phone is turned, so keep both sides clear of the larger one.
			Left = maxf(Left, Right)
			Right = Left
	Readouts.position = Vector2(EdgeMargin + Left, EdgeMargin + Top)
	FpsLabel.offset_right = -(EdgeMargin + Right)
	FpsLabel.offset_bottom = -EdgeMargin
	Gear.offset_right = -(EdgeMargin + Right)
	Gear.offset_left = Gear.offset_right - GearSize
	Gear.offset_top = EdgeMargin + Top
	Gear.offset_bottom = Gear.offset_top + GearSize
	if Camera != null:
		Camera.offset_right = Gear.offset_right
		Camera.offset_left = Gear.offset_left
		Camera.offset_top = Gear.offset_bottom + 10.0
		Camera.offset_bottom = Camera.offset_top + GearSize
