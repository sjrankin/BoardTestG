class_name ControlBar
extends CanvasLayer
## The on-screen controls: the score and frame rate at the top left, a gear button at the top right (below the status bar
## on a phone or tablet), and the settings window the gear opens - the settings in labelled groups, with touch-sized
## controls. It owns no game logic: it shows values and reports what the user did through signals.

signal ShapeSelected(Index: int)
## The play mode (`GameMode.Kinds`) picked in Settings > Game.
signal GameModeSelected(Index: int)
## A level picked in Settings > Game: 0 is none, 1 is `Levels.All()[0]`, and so on.
signal LevelSelected(Index: int)
## The answer to the "Replay?" question shown after a failed level.
signal ReplayAnswered(Yes: bool)
## The "Play" button shown while Attract Mode is on.
signal PlayPressed
## The "Start" button of Settings > Level Difficulty.
signal DifficultyStartPressed
## One of the four Settings > Malicious switches (0 spinning light, 1 moving Blockers, 2 veil, 3 turned and locked board).
signal MaliciousToggled(Index: int, On: bool)
signal ShufflePressed
signal RecenterPressed
signal AutoRotateToggled(On: bool)
## Whether Attract Mode also turns the 3D cube slowly (random rotation).
signal AttractSpinToggled(On: bool)
## 0 is the 2D board, 1 the 3D cube.
signal BoardTypeSelected(Index: int)
signal BoardSetPressed(Width: int, Height: int, Depth: int, Colors: int, Blockers: int)
signal RemovalSpeedChanged(Value: float)
signal LightningToggled(On: bool)
## The index into `RemovalEffectNames` (the order of `BoardView.RemovalEffects`).
signal RemovalEffectChanged(Index: int)
signal BlockerZapsToggled(On: bool)
signal SpecularToggled(On: bool)
## The index into `Backgrounds.Names`.
signal BackgroundSelected(Index: int)
## The most frames per second to draw; 0 means no limit.
signal FrameRateChanged(Limit: int)
## The camera button (Mac only) was pressed.
signal ScreenshotPressed

const MinRemovalSpeed := 0.25
const MaxRemovalSpeed := 3.0
const WidthRange := Vector2i(3, 15)
const ColorsRange := Vector2i(3, 8)
const BlockersRange := Vector2i(0, 20)
const BoardTypeNames: Array[String] = ["2D Board", "3D Cube"]
## The choices in the Frame Rate list (0 is "No Limit").
const FrameRateLimits: Array[int] = [30, 60, 120, 0]
const GearSize := 64.0
const RemovalEffectNames: Array[String] = ["Fly Away", "Mini Me", "Explode", "Disappear", "Spin and Shrink", "Spin then Vanish"]
const EdgeMargin := 14.0
const SettingsFontSize := 24
const RowHeight := 48.0

var AttractCheck: Button
var AutoRotateCheck: Button
var AttractSpinCheck: Button
var LightningCheck: Button
var BlockerZapsCheck: Button
var SpecularCheck: Button
var GoalBox: VBoxContainer
## Goal color (`Kind`) -> its badge, while pieces of it are still to remove.
var GoalBadges: Dictionary = {}
var ClockLabel: Label
var StatusLabel: Label
var LevelLabel: Label
var ReplayPrompt: Control
var PlayButton: Button
## The screen shown while the difficulty test runs.
var TestOverlay: DifficultyOverlay
var MaliciousChecks: Array[Button] = []
var GameModePicker: OptionButton
var LevelPicker: OptionButton
var FpsLabel: Label
var ShapePicker: OptionButton
var BackgroundPicker: OptionButton
var FrameRatePicker: OptionButton
var RemovalEffectPicker: OptionButton
var WidthField: SpinBox
var HeightField: SpinBox
var ColorsField: SpinBox
var BlockersField: SpinBox
var DepthField: SpinBox
var BoardTypePicker: OptionButton
var SpeedSlider: HSlider
var SpeedLabel: Label
var Readouts: VBoxContainer
var Gear: GearButton
var Camera: CameraButton
var Overlay: Control


## Builds the controls with their starting values.
func Setup(Width: int, Height: int, Colors: int, Blockers: int, ShapeIndex: int, RemovalSpeed: float, Lightning: bool, BlockerZaps: bool, Specular: bool, FrameRate: int, RemovalEffect: int, ShapeNames: Array[String]) -> void:
	BuildReadouts()
	BuildGear()
	BuildReplayPrompt()
	BuildPlayButton()
	TestOverlay = DifficultyOverlay.new()
	if OS.get_name() == "macOS":
		BuildCamera()
	BuildSettingsWindow(Width, Height, Colors, Blockers, ShapeIndex, RemovalSpeed, Lightning, BlockerZaps, Specular, FrameRate, RemovalEffect, ShapeNames)
	get_window().size_changed.connect(PlaceInsets)
	add_child(TestOverlay)
	PlaceInsets()


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
	PlayButton = Button.new()
	PlayButton.text = "Play"
	PlayButton.visible = false
	PlayButton.add_theme_font_size_override("font_size", 48)
	PlayButton.custom_minimum_size = Vector2(240, 90)
	var Face := StyleBoxFlat.new()
	Face.bg_color = Color(0.2, 0.5, 0.9)
	Face.set_corner_radius_all(16)
	for Look in ["normal", "hover", "pressed", "focus"]:
		PlayButton.add_theme_stylebox_override(Look, Face)
	PlayButton.pressed.connect(func() -> void: PlayPressed.emit())
	add_child(PlayButton)
	PlayButton.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM, Control.PRESET_MODE_MINSIZE)
	PlayButton.grow_horizontal = Control.GROW_DIRECTION_BOTH
	PlayButton.grow_vertical = Control.GROW_DIRECTION_BEGIN
	PlayButton.offset_bottom = -60.0
	PlayButton.offset_top = -150.0
	PlayButton.offset_left = -120.0
	PlayButton.offset_right = 120.0


## While the "Replay?" question is up nothing else may be done: the Settings gear (and with it Shuffle, Attract Mode, the level
## and board pickers) is dimmed and does not answer until the question is.
func ShowReplayPrompt(On: bool) -> void:
	ReplayPrompt.visible = On
	Gear.disabled = On
	Gear.modulate.a = 0.35 if On else 1.0
	if Camera != null:
		Camera.disabled = On
		Camera.modulate.a = 0.35 if On else 1.0


## A label across the top of the window with its text centered, `Top` pixels from the top.
func AddTopCenterLabel(FontSize: int, Top: float) -> Label:
	var Line := Label.new()
	Line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	Line.add_theme_font_size_override("font_size", FontSize)
	Line.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	Line.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	Line.offset_top = Top
	Line.offset_bottom = Top + FontSize * 1.4
	add_child(Line)
	return Line


func AddReadout(Title: String, Value: String) -> Label:
	var Box := VBoxContainer.new()
	Box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var TitleLabel := Label.new()
	TitleLabel.text = Title
	Box.add_child(TitleLabel)
	var ValueLabel := Label.new()
	ValueLabel.text = Value
	ValueLabel.add_theme_font_size_override("font_size", 40)
	Box.add_child(ValueLabel)
	Readouts.add_child(Box)
	return ValueLabel


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


# MARK: The settings window

func OpenSettings() -> void:
	Overlay.visible = true


func CloseSettings() -> void:
	Overlay.visible = false


## A dimmed backdrop (a tap on it closes the window) with a centered panel: a title, a scrolling list of settings in groups,
## and a Done button. While it is open it swallows every click, so nothing reaches the board behind it.
func BuildSettingsWindow(Width: int, Height: int, Colors: int, Blockers: int, ShapeIndex: int, RemovalSpeed: float, Lightning: bool, BlockerZaps: bool, Specular: bool, FrameRate: int, RemovalEffect: int, ShapeNames: Array[String]) -> void:
	Overlay = Control.new()
	Overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	Overlay.visible = false
	add_child(Overlay)
	var Dim := ColorRect.new()
	Dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	Dim.color = Color(0, 0, 0, 0.55)
	Dim.gui_input.connect(OnBackdropInput)
	Overlay.add_child(Dim)
	var Center := CenterContainer.new()
	Center.set_anchors_preset(Control.PRESET_FULL_RECT)
	Center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	Overlay.add_child(Center)
	var Dialog := PanelContainer.new()
	Dialog.custom_minimum_size = Vector2(900, 0)
	# The default look (buttons, toggles, spin boxes) at a larger text size, on a solid dark panel.
	var Look := ThemeDB.get_default_theme().duplicate() as Theme
	Look.default_font_size = SettingsFontSize
	for TypeName in ["Label", "Button", "OptionButton", "LineEdit", "SpinBox"]:
		Look.set_font_size("font_size", TypeName, SettingsFontSize)
	Dialog.theme = Look
	var Back := StyleBoxFlat.new()
	Back.bg_color = Color(0.13, 0.14, 0.17, 0.98)
	Back.set_corner_radius_all(20)
	Dialog.add_theme_stylebox_override("panel", Back)
	Center.add_child(Dialog)
	var Margins := MarginContainer.new()
	for Side in ["left", "right", "top", "bottom"]:
		Margins.add_theme_constant_override("margin_" + Side, 20)
	Dialog.add_child(Margins)
	var Page := VBoxContainer.new()
	Page.add_theme_constant_override("separation", 14)
	Margins.add_child(Page)
	var Header := HBoxContainer.new()
	Page.add_child(Header)
	var Title := Label.new()
	Title.text = "Settings"
	Title.add_theme_font_size_override("font_size", 34)
	Title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	Header.add_child(Title)
	var Done := Button.new()
	Done.text = "Done"
	Done.custom_minimum_size = Vector2(120, RowHeight)
	Done.pressed.connect(CloseSettings)
	Header.add_child(Done)
	var Scroller := ScrollContainer.new()
	Scroller.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	Scroller.custom_minimum_size = Vector2(0, 460)
	Scroller.size_flags_vertical = Control.SIZE_EXPAND_FILL
	Page.add_child(Scroller)
	var Sections := VBoxContainer.new()
	Sections.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	Sections.add_theme_constant_override("separation", 22)
	Scroller.add_child(Sections)
	BuildGameSection(AddSection(Sections, "Game"))
	BuildBoardSection(AddSection(Sections, "Board"), Width, Height, Colors, Blockers)
	BuildPiecesSection(AddSection(Sections, "Pieces"), ShapeIndex, Specular, ShapeNames)
	BuildSceneSection(AddSection(Sections, "Scene"))
	BuildEffectsSection(AddSection(Sections, "Effects"), Lightning, BlockerZaps, RemovalSpeed, RemovalEffect)
	BuildPerformanceSection(AddSection(Sections, "Performance"), FrameRate)
	BuildMaliciousSection(AddSection(Sections, "Malicious"))
	BuildDifficultySection(AddSection(Sections, "Level Difficulty"))
	get_window().size_changed.connect(FitSettingsWindow.bind(Dialog, Scroller))
	FitSettingsWindow(Dialog, Scroller)


## Sizes the window to the screen: up to 900 wide, and the scrolling list up to what fits under the title.
func FitSettingsWindow(Dialog: Control, Scroller: Control) -> void:
	var Visible := get_viewport().get_visible_rect().size
	Dialog.custom_minimum_size.x = minf(900.0, Visible.x - 40.0)
	Scroller.custom_minimum_size.y = clampf(Visible.y - 190.0, 160.0, 800.0)


func OnBackdropInput(Event: InputEvent) -> void:
	if Event is InputEventMouseButton and Event.pressed:
		CloseSettings()


func BuildGameSection(Section: VBoxContainer) -> void:
	GameModePicker = OptionButton.new()
	for Name in GameMode.Names:
		GameModePicker.add_item(Name)
	GameModePicker.item_selected.connect(func(Index: int) -> void:
		CloseSettings()
		GameModeSelected.emit(Index))
	AddRow(Section, "Play Mode (starts a new game)", GameModePicker)
	LevelPicker = OptionButton.new()
	LevelPicker.add_item("None (Board settings)")
	for Index in Levels.Count():
		LevelPicker.add_item("Level %d" % (Index + 1))
	LevelPicker.item_selected.connect(func(Index: int) -> void:
		CloseSettings()
		LevelSelected.emit(Index))
	AddRow(Section, "Level (2D board, starts a new game)", LevelPicker)
	AddButtonRow(Section, "Shuffle the pieces", "Shuffle", func() -> void:
		CloseSettings()
		ShufflePressed.emit())
	AttractCheck = AddCheckRow(Section, "Attract Mode (plays itself)", false)
	AttractSpinCheck = AddCheckRow(Section, "Random rotation in Attract Mode (3D)", true)
	AttractSpinCheck.toggled.connect(func(On: bool) -> void: AttractSpinToggled.emit(On))
	AutoRotateCheck = AddCheckRow(Section, "Auto Rotate the board", false)
	AutoRotateCheck.toggled.connect(func(On: bool) -> void: AutoRotateToggled.emit(On))
	AddButtonRow(Section, "Turn the board back to face you", "Recenter", func() -> void:
		CloseSettings()
		RecenterPressed.emit())


func BuildBoardSection(Section: VBoxContainer, Width: int, Height: int, Colors: int, Blockers: int) -> void:
	BoardTypePicker = OptionButton.new()
	for Name in BoardTypeNames:
		BoardTypePicker.add_item(Name)
	BoardTypePicker.item_selected.connect(func(Index: int) -> void: BoardTypeSelected.emit(Index))
	AddRow(Section, "Board Type", BoardTypePicker)
	WidthField = AddFieldRow(Section, "Width", Width, WidthRange)
	HeightField = AddFieldRow(Section, "Height", Height, WidthRange)
	DepthField = AddFieldRow(Section, "Depth", Width, WidthRange)
	ColorsField = AddFieldRow(Section, "Colors", Colors, ColorsRange)
	BlockersField = AddFieldRow(Section, "Blockers", Blockers, BlockersRange)
	AddButtonRow(Section, "Start a new game with these", "New Game", OnSetPressed)


## Shows the fields of the board type: the 2D board's width, height and Blockers, or the cube's width, height and depth.
func ShowBoardType(Is3D: bool, Width: int, Height: int, Depth: int, Blockers: int) -> void:
	BoardTypePicker.selected = 1 if Is3D else 0
	WidthField.value = Width
	HeightField.value = Height
	DepthField.value = Depth
	BlockersField.value = Blockers
	DepthField.get_parent().visible = Is3D
	BlockersField.get_parent().visible = not Is3D
	AttractSpinCheck.get_parent().visible = Is3D


func BuildPiecesSection(Section: VBoxContainer, ShapeIndex: int, Specular: bool, ShapeNames: Array[String]) -> void:
	ShapePicker = OptionButton.new()
	for Name in ShapeNames:
		ShapePicker.add_item(Name)
	ShapePicker.selected = ShapeIndex
	ShapePicker.item_selected.connect(func(Index: int) -> void: ShapeSelected.emit(Index))
	AddRow(Section, "Block Shape", ShapePicker)
	SpecularCheck = AddCheckRow(Section, "Specular (glossy pieces)", Specular)
	SpecularCheck.toggled.connect(func(On: bool) -> void: SpecularToggled.emit(On))


func BuildSceneSection(Section: VBoxContainer) -> void:
	BackgroundPicker = OptionButton.new()
	for Name in Backgrounds.Names:
		BackgroundPicker.add_item(Name)
	BackgroundPicker.item_selected.connect(func(Index: int) -> void: BackgroundSelected.emit(Index))
	AddRow(Section, "Background", BackgroundPicker)


func BuildEffectsSection(Section: VBoxContainer, Lightning: bool, BlockerZaps: bool, RemovalSpeed: float, RemovalEffect: int) -> void:
	RemovalEffectPicker = OptionButton.new()
	for Name in RemovalEffectNames:
		RemovalEffectPicker.add_item(Name)
	RemovalEffectPicker.selected = clampi(RemovalEffect, 0, RemovalEffectNames.size() - 1)
	RemovalEffectPicker.item_selected.connect(func(Index: int) -> void: RemovalEffectChanged.emit(Index))
	AddRow(Section, "Removal Effect", RemovalEffectPicker)
	LightningCheck = AddCheckRow(Section, "Lightning when a group clears", Lightning)
	LightningCheck.toggled.connect(func(On: bool) -> void: LightningToggled.emit(On))
	BlockerZapsCheck = AddCheckRow(Section, "Zaps on the Blockers", BlockerZaps)
	BlockerZapsCheck.toggled.connect(func(On: bool) -> void: BlockerZapsToggled.emit(On))
	var SpeedBox := HBoxContainer.new()
	SpeedBox.add_theme_constant_override("separation", 12)
	SpeedSlider = HSlider.new()
	SpeedSlider.min_value = MinRemovalSpeed
	SpeedSlider.max_value = MaxRemovalSpeed
	SpeedSlider.step = 0.05
	SpeedSlider.custom_minimum_size = Vector2(260, RowHeight)
	SpeedSlider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	SpeedSlider.value = RemovalSpeed
	SpeedSlider.value_changed.connect(OnSpeedChanged)
	SpeedBox.add_child(SpeedSlider)
	SpeedLabel = Label.new()
	SpeedLabel.custom_minimum_size = Vector2(80, 0)
	SpeedBox.add_child(SpeedLabel)
	AddRow(Section, "Removal Speed", SpeedBox)
	OnSpeedChanged(SpeedSlider.value)


func BuildPerformanceSection(Section: VBoxContainer, FrameRate: int) -> void:
	FrameRatePicker = OptionButton.new()
	for Limit in FrameRateLimits:
		FrameRatePicker.add_item("No Limit" if Limit == 0 else "%d per second" % Limit)
	FrameRatePicker.selected = maxi(FrameRateLimits.find(FrameRate), 0)
	FrameRatePicker.item_selected.connect(func(Index: int) -> void: FrameRateChanged.emit(FrameRateLimits[Index]))
	AddRow(Section, "Frame Rate Limit", FrameRatePicker)
	var Note := Label.new()
	Note.text = "A lower limit keeps a phone or tablet cooler and saves battery."
	Note.add_theme_font_size_override("font_size", 18)
	Note.modulate = Color(1, 1, 1, 0.6)
	Note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	Section.add_child(Note)


## Switches that make the game harder for the player.
func BuildMaliciousSection(Section: VBoxContainer) -> void:
	var Titles: Array[String] = ["Spin the light around the board (30 s a turn)", "Move the Blockers after every group (2D)", "Hide one color behind a veil (every 20 s, for 10 s)", "Turn the board 45\u00B0 and lock it"]
	for Index in Titles.size():
		var Check := AddCheckRow(Section, Titles[Index], false)
		Check.toggled.connect(func(On: bool) -> void: MaliciousToggled.emit(Index, On))
		MaliciousChecks.append(Check)


func BuildDifficultySection(Section: VBoxContainer) -> void:
	AddButtonRow(Section, "Test every level 30 times", "Start", func() -> void:
		CloseSettings()
		DifficultyStartPressed.emit())
	var Note := Label.new()
	Note.text = "A bot plays each level, always taking the largest group of a color the goal needs. Its mean turns are saved in the level table and set each level's difficulty (its turns against the turns the level allows)."
	Note.add_theme_font_size_override("font_size", 18)
	Note.modulate = Color(1, 1, 1, 0.6)
	Note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	Section.add_child(Note)


# MARK: Building rows

## A titled group: a heading, a thin rule, and the box the group's rows go in.
func AddSection(Parent: Control, Title: String) -> VBoxContainer:
	var Group := VBoxContainer.new()
	Group.add_theme_constant_override("separation", 8)
	var Heading := Label.new()
	Heading.text = Title
	Heading.add_theme_font_size_override("font_size", 28)
	Heading.modulate = Color(0.75, 0.85, 1.0)
	Group.add_child(Heading)
	Group.add_child(HSeparator.new())
	var Rows := VBoxContainer.new()
	Rows.add_theme_constant_override("separation", 10)
	Group.add_child(Rows)
	Parent.add_child(Group)
	return Rows


## A row with a label on the left (taking the spare width) and `Control` on the right.
func AddRow(Parent: Control, Title: String, Item: Control) -> void:
	var Row := HBoxContainer.new()
	Row.custom_minimum_size = Vector2(0, RowHeight)
	var Caption := Label.new()
	Caption.text = Title
	Caption.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	Caption.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	Row.add_child(Caption)
	Row.add_child(Item)
	Parent.add_child(Row)


## A row with a label and an On/Off toggle button on the right (large, and clear at a glance). Returns the button: its
## `toggled` signal and `button_pressed` work as for a check box.
func AddCheckRow(Parent: Control, Title: String, On: bool) -> Button:
	var Toggle := Button.new()
	Toggle.toggle_mode = true
	Toggle.custom_minimum_size = Vector2(110, RowHeight)
	Toggle.button_pressed = On
	Toggle.text = "On" if On else "Off"
	Toggle.toggled.connect(func(Pressed: bool) -> void: Toggle.text = "On" if Pressed else "Off")
	var OnStyle := StyleBoxFlat.new()
	OnStyle.bg_color = Color(0.2, 0.5, 0.9)
	OnStyle.set_corner_radius_all(8)
	Toggle.add_theme_stylebox_override("pressed", OnStyle)
	Toggle.add_theme_stylebox_override("hover_pressed", OnStyle)
	AddRow(Parent, Title, Toggle)
	return Toggle


func AddFieldRow(Parent: Control, Title: String, Value: int, Limits: Vector2i) -> SpinBox:
	var Field := SpinBox.new()
	Field.min_value = Limits.x
	Field.max_value = Limits.y
	Field.value = Value
	Field.custom_minimum_size = Vector2(170, RowHeight)
	AddRow(Parent, Title, Field)
	return Field


func AddButtonRow(Parent: Control, Title: String, ButtonText: String, Action: Callable) -> void:
	var ActionButton := Button.new()
	ActionButton.text = ButtonText
	ActionButton.custom_minimum_size = Vector2(170, RowHeight)
	ActionButton.pressed.connect(Action)
	AddRow(Parent, Title, ActionButton)


# MARK: Reporting

func OnSetPressed() -> void:
	AttractCheck.button_pressed = false
	CloseSettings()
	BoardSetPressed.emit(int(WidthField.value), int(HeightField.value), int(DepthField.value), int(ColorsField.value), int(BlockersField.value))


func OnSpeedChanged(NewSpeed: float) -> void:
	SpeedLabel.text = "%.2fx" % NewSpeed
	RemovalSpeedChanged.emit(NewSpeed)
