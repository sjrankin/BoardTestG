class_name ControlBar
extends CanvasLayer
## The on-screen controls: the score and frame rate at the top left, and the row of controls along the bottom. It owns
## no game logic - it shows values and reports what the user did through signals.

signal ShapeSelected(Index: int)
signal ShufflePressed
signal RecenterPressed
signal AutoRotateToggled(On: bool)
signal BoardSetPressed(Width: int, Height: int, Colors: int, Blockers: int)
signal RemovalSpeedChanged(Value: float)
signal LightningToggled(On: bool)
signal BlockerZapsToggled(On: bool)
signal SpecularToggled(On: bool)

const MinRemovalSpeed := 0.25
const MaxRemovalSpeed := 3.0
const WidthRange := Vector2i(3, 15)
const ColorsRange := Vector2i(3, 8)
const BlockersRange := Vector2i(0, 20)

var AttractCheck: CheckButton
var AutoRotateCheck: CheckButton
var LightningCheck: CheckButton
var BlockerZapsCheck: CheckButton
var SpecularCheck: CheckButton
var ScoreLabel: Label
var FpsLabel: Label
var ShapePicker: OptionButton
var WidthField: SpinBox
var HeightField: SpinBox
var ColorsField: SpinBox
var BlockersField: SpinBox
var SpeedSlider: HSlider
var SpeedLabel: Label


## Builds the controls with their starting values. They sit in a row along the bottom that wraps onto more lines when the
## window is too narrow for one, and a label always stays with the control it names.
func Setup(Width: int, Height: int, Colors: int, Blockers: int, ShapeIndex: int, RemovalSpeed: float, Lightning: bool, BlockerZaps: bool, Specular: bool, ShapeNames: Array[String]) -> void:
	BuildReadouts()
	var Controls := BuildControlArea()
	var ShapeGroup := AddGroup(Controls)
	AddLabel(ShapeGroup, "Block Shape")
	ShapePicker = OptionButton.new()
	for Name in ShapeNames:
		ShapePicker.add_item(Name)
	ShapePicker.selected = ShapeIndex
	ShapePicker.item_selected.connect(func(Index: int) -> void: ShapeSelected.emit(Index))
	ShapeGroup.add_child(ShapePicker)
	AddButton(Controls, "Shuffle", func() -> void: ShufflePressed.emit())
	AddButton(Controls, "Recenter", func() -> void: RecenterPressed.emit())
	AutoRotateCheck = AddCheck(Controls, "Auto Rotate")
	AutoRotateCheck.toggled.connect(func(On: bool) -> void: AutoRotateToggled.emit(On))
	AttractCheck = AddCheck(Controls, "Attract Mode")
	LightningCheck = AddCheck(Controls, "Removal Lightning")
	LightningCheck.button_pressed = Lightning
	LightningCheck.toggled.connect(func(On: bool) -> void: LightningToggled.emit(On))
	BlockerZapsCheck = AddCheck(Controls, "Blocker Zaps")
	BlockerZapsCheck.button_pressed = BlockerZaps
	BlockerZapsCheck.toggled.connect(func(On: bool) -> void: BlockerZapsToggled.emit(On))
	SpecularCheck = AddCheck(Controls, "Specular")
	SpecularCheck.button_pressed = Specular
	SpecularCheck.toggled.connect(func(On: bool) -> void: SpecularToggled.emit(On))
	WidthField = AddField(Controls, "Width", Width, WidthRange)
	HeightField = AddField(Controls, "Height", Height, WidthRange)
	ColorsField = AddField(Controls, "Colors", Colors, ColorsRange)
	BlockersField = AddField(Controls, "Blockers", Blockers, BlockersRange)
	AddButton(Controls, "Set", OnSetPressed)
	var SpeedGroup := AddGroup(Controls)
	AddLabel(SpeedGroup, "Removal Speed")
	SpeedSlider = HSlider.new()
	SpeedSlider.min_value = MinRemovalSpeed
	SpeedSlider.max_value = MaxRemovalSpeed
	SpeedSlider.step = 0.05
	SpeedSlider.custom_minimum_size = Vector2(180, 0)
	SpeedSlider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	SpeedSlider.value = RemovalSpeed
	SpeedSlider.value_changed.connect(OnSpeedChanged)
	SpeedGroup.add_child(SpeedSlider)
	SpeedLabel = AddLabel(SpeedGroup, "")
	OnSpeedChanged(SpeedSlider.value)


## The area along the bottom of the window the controls live in: full width, flowing onto extra lines as needed, with its
## last line at the bottom. The containers around it ignore the mouse, so a click beside the controls still reaches the board.
func BuildControlArea() -> HFlowContainer:
	var Root := Control.new()
	Root.set_anchors_preset(Control.PRESET_FULL_RECT)
	Root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(Root)
	var Margins := MarginContainer.new()
	Margins.set_anchors_preset(Control.PRESET_FULL_RECT)
	Margins.mouse_filter = Control.MOUSE_FILTER_IGNORE
	Margins.add_theme_constant_override("margin_left", 16)
	Margins.add_theme_constant_override("margin_right", 16)
	Margins.add_theme_constant_override("margin_bottom", 10)
	Root.add_child(Margins)
	var Controls := HFlowContainer.new()
	Controls.mouse_filter = Control.MOUSE_FILTER_IGNORE
	Controls.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	Controls.size_flags_vertical = Control.SIZE_SHRINK_END
	Controls.add_theme_constant_override("h_separation", 14)
	Controls.add_theme_constant_override("v_separation", 6)
	Margins.add_child(Controls)
	return Controls


func SetScore(Score: int) -> void:
	ScoreLabel.text = str(Score)


func SetFps(Fps: int) -> void:
	FpsLabel.text = str(Fps)


# MARK: Building

## The score and the frame rate, large, at the top left.
func BuildReadouts() -> void:
	var Bar := HBoxContainer.new()
	Bar.position = Vector2(16, 12)
	Bar.add_theme_constant_override("separation", 18)
	add_child(Bar)
	ScoreLabel = AddReadout(Bar, "Score", "0")
	FpsLabel = AddReadout(Bar, "FPS", "")


func AddReadout(Parent: Control, Title: String, Value: String) -> Label:
	var Box := VBoxContainer.new()
	AddLabel(Box, Title)
	var ValueLabel := AddLabel(Box, Value)
	ValueLabel.add_theme_font_size_override("font_size", 40)
	Parent.add_child(Box)
	return ValueLabel


## A little row that keeps a label and its control together when the controls wrap.
func AddGroup(Parent: Control) -> HBoxContainer:
	var Group := HBoxContainer.new()
	Group.mouse_filter = Control.MOUSE_FILTER_IGNORE
	Group.add_theme_constant_override("separation", 8)
	Parent.add_child(Group)
	return Group


func AddLabel(Parent: Control, Text: String) -> Label:
	var NewLabel := Label.new()
	NewLabel.text = Text
	NewLabel.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	Parent.add_child(NewLabel)
	return NewLabel


func AddButton(Parent: Control, Text: String, Action: Callable) -> Button:
	var NewButton := Button.new()
	NewButton.text = Text
	NewButton.pressed.connect(Action)
	Parent.add_child(NewButton)
	return NewButton


func AddCheck(Parent: Control, Text: String) -> CheckButton:
	var Check := CheckButton.new()
	Check.text = Text
	Parent.add_child(Check)
	return Check


func AddField(Parent: Control, Title: String, Value: int, Limits: Vector2i) -> SpinBox:
	var Group := AddGroup(Parent)
	AddLabel(Group, Title)
	var Field := SpinBox.new()
	Field.min_value = Limits.x
	Field.max_value = Limits.y
	Field.value = Value
	Group.add_child(Field)
	return Field


# MARK: Reporting

func OnSetPressed() -> void:
	AttractCheck.button_pressed = false
	BoardSetPressed.emit(int(WidthField.value), int(HeightField.value), int(ColorsField.value), int(BlockersField.value))


func OnSpeedChanged(NewSpeed: float) -> void:
	SpeedLabel.text = "%.2fx" % NewSpeed
	RemovalSpeedChanged.emit(NewSpeed)
