class_name ControlBarRows
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

## The "Next Level" button shown in Zen once the goal is reached (play can go on, or the player can move on).
signal NextLevelPressed

## The "Start" button of Settings > Level Difficulty.
signal DifficultyStartPressed

## One of the seven Settings > Malicious switches (0 spinning light, 1 moving Blockers, 2 veil, 3 turned and locked board, 4 swapped colors, 5 drained colors, 6 all white).
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

## Metallic pieces on or off.
signal MetallicToggled(On: bool)

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

const RemovalEffectNames: Array[String] = ["Fly Away", "Mini Me", "Explode", "Disappear", "Spin and Shrink", "Spin then Vanish", "Puff of Smoke"]

const EdgeMargin := 14.0

const SettingsFontSize := 24

const RowHeight := 48.0

var AttractCheck: Button

var AutoRotateCheck: Button

var AttractSpinCheck: Button

var LightningCheck: Button

var BlockerZapsCheck: Button

var SpecularCheck: Button

var MetallicCheck: Button

var GoalBox: VBoxContainer

## Goal color (`Kind`) -> its badge, while pieces of it are still to remove.
var GoalBadges: Dictionary = {}

var ClockLabel: Label

var StatusLabel: Label

var LevelLabel: Label

var ReplayPrompt: Control

var PlayButton: Button

var NextButton: Button

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

## Building rows for the settings window.

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


# MARK: The settings window
func OpenSettings() -> void:
	Overlay.visible = true


func CloseSettings() -> void:
	Overlay.visible = false


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
