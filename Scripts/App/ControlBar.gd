class_name ControlBar
extends CanvasLayer
## The on-screen controls: the score and frame rate at the top left, a gear button at the top right (below the status bar
## on a phone or tablet), and the settings window the gear opens - the settings in labelled groups, with touch-sized
## controls. It owns no game logic: it shows values and reports what the user did through signals.

signal ShapeSelected(Index: int)
signal ShufflePressed
signal RecenterPressed
signal AutoRotateToggled(On: bool)
## 0 is the 2D board, 1 the 3D cube.
signal BoardTypeSelected(Index: int)
signal BoardSetPressed(Width: int, Height: int, Depth: int, Colors: int, Blockers: int)
signal RemovalSpeedChanged(Value: float)
signal LightningToggled(On: bool)
## 0 is Fly Away, 1 is Mini Me, 2 is Explode (the order of `RemovalEffectNames`).
signal RemovalEffectChanged(Index: int)
signal BlockerZapsToggled(On: bool)
signal SpecularToggled(On: bool)
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
const RemovalEffectNames: Array[String] = ["Fly Away", "Mini Me", "Explode"]
const EdgeMargin := 14.0
const SettingsFontSize := 24
const RowHeight := 48.0

var AttractCheck: Button
var AutoRotateCheck: Button
var LightningCheck: Button
var BlockerZapsCheck: Button
var SpecularCheck: Button
var ScoreLabel: Label
var FpsLabel: Label
var ShapePicker: OptionButton
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
var Readouts: HBoxContainer
var Gear: GearButton
var Camera: CameraButton
var Overlay: Control


## Builds the controls with their starting values.
func Setup(Width: int, Height: int, Colors: int, Blockers: int, ShapeIndex: int, RemovalSpeed: float, Lightning: bool, BlockerZaps: bool, Specular: bool, FrameRate: int, RemovalEffect: int, ShapeNames: Array[String]) -> void:
	BuildReadouts()
	BuildGear()
	if OS.get_name() == "macOS":
		BuildCamera()
	BuildSettingsWindow(Width, Height, Colors, Blockers, ShapeIndex, RemovalSpeed, Lightning, BlockerZaps, Specular, FrameRate, RemovalEffect, ShapeNames)
	get_window().size_changed.connect(PlaceInsets)
	PlaceInsets()


func SetScore(Score: int) -> void:
	ScoreLabel.text = str(Score)


func SetFps(Fps: int) -> void:
	FpsLabel.text = str(Fps)


# MARK: The top of the screen

## The score and the frame rate, large, at the top left.
func BuildReadouts() -> void:
	Readouts = HBoxContainer.new()
	Readouts.mouse_filter = Control.MOUSE_FILTER_IGNORE
	Readouts.add_theme_constant_override("separation", 18)
	add_child(Readouts)
	ScoreLabel = AddReadout("Score", "0")
	FpsLabel = AddReadout("FPS", "")


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
	BuildEffectsSection(AddSection(Sections, "Effects"), Lightning, BlockerZaps, RemovalSpeed, RemovalEffect)
	BuildPerformanceSection(AddSection(Sections, "Performance"), FrameRate)
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
	AddButtonRow(Section, "Shuffle the pieces", "Shuffle", func() -> void:
		CloseSettings()
		ShufflePressed.emit())
	AttractCheck = AddCheckRow(Section, "Attract Mode (plays itself)", false)
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


func BuildPiecesSection(Section: VBoxContainer, ShapeIndex: int, Specular: bool, ShapeNames: Array[String]) -> void:
	ShapePicker = OptionButton.new()
	for Name in ShapeNames:
		ShapePicker.add_item(Name)
	ShapePicker.selected = ShapeIndex
	ShapePicker.item_selected.connect(func(Index: int) -> void: ShapeSelected.emit(Index))
	AddRow(Section, "Block Shape", ShapePicker)
	SpecularCheck = AddCheckRow(Section, "Specular (glossy pieces)", Specular)
	SpecularCheck.toggled.connect(func(On: bool) -> void: SpecularToggled.emit(On))


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
