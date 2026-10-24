class_name DifficultyOverlay
extends Control
## The screen shown while the difficulty test runs (`DifficultyRun`): which level and trial it is on, a progress bar, and a line for
## every level finished so far. It covers the window, so nothing under it can be tapped. The button cancels the test, then closes it.

signal ClosePressed

const FontSize := 26

var StatusLabel: Label
var Bar: ProgressBar
var ResultsLabel: Label
var CloseButton: Button
var Lines: Array[String] = []


func _init() -> void:
	visible = false
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var Dim := ColorRect.new()
	Dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	Dim.color = Color(0, 0, 0, 0.78)
	add_child(Dim)
	var Center := CenterContainer.new()
	Center.set_anchors_preset(Control.PRESET_FULL_RECT)
	Center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(Center)
	var Panel := PanelContainer.new()
	Panel.custom_minimum_size = Vector2(900, 0)
	var Look := Theme.new()
	Look.default_font_size = FontSize
	Panel.theme = Look
	var Back := StyleBoxFlat.new()
	Back.bg_color = Color(0.13, 0.14, 0.17, 0.98)
	Back.set_corner_radius_all(20)
	Back.set_content_margin_all(24)
	Panel.add_theme_stylebox_override("panel", Back)
	Center.add_child(Panel)
	var Column := VBoxContainer.new()
	Column.add_theme_constant_override("separation", 14)
	Panel.add_child(Column)
	var Title := Label.new()
	Title.text = "Level Difficulty Test"
	Title.add_theme_font_size_override("font_size", 36)
	Column.add_child(Title)
	StatusLabel = Label.new()
	Column.add_child(StatusLabel)
	Bar = ProgressBar.new()
	Bar.custom_minimum_size = Vector2(0, 30)
	Bar.show_percentage = false
	Bar.max_value = Levels.Count() * DifficultyRun.Trials
	Column.add_child(Bar)
	ResultsLabel = Label.new()
	ResultsLabel.custom_minimum_size = Vector2(0, 340)
	Column.add_child(ResultsLabel)
	CloseButton = Button.new()
	CloseButton.custom_minimum_size = Vector2(200, 56)
	CloseButton.size_flags_horizontal = Control.SIZE_SHRINK_END
	CloseButton.pressed.connect(func() -> void: ClosePressed.emit())
	Column.add_child(CloseButton)


func Begin() -> void:
	Lines.clear()
	Bar.value = 0
	StatusLabel.text = "Starting..."
	ResultsLabel.text = ""
	CloseButton.text = "Cancel"
	visible = true


func ShowProgress(LevelIndex: int, Trial: int, LastTurns: int, Mean: float) -> void:
	StatusLabel.text = "Level %d of %d - trial %d of %d - last game %d turns, mean so far %.1f" % [LevelIndex + 1, Levels.Count(), Trial, DifficultyRun.Trials, LastTurns, Mean]
	Bar.value = LevelIndex * DifficultyRun.Trials + Trial


func ShowResult(LevelIndex: int, Mean: float, WinRate: float, Difficulty: int) -> void:
	var Allowed := Levels.All()[LevelIndex].TurnCount
	Lines.append("Level %2d   mean %5.1f turns of %2d allowed   won %3d%%   difficulty %d" % [LevelIndex + 1, Mean, Allowed, roundi(WinRate * 100.0), Difficulty])
	ResultsLabel.text = "\n".join(Lines)


func Finish(Cancelled: bool) -> void:
	StatusLabel.text = "Cancelled (finished levels were kept)." if Cancelled else "Done - difficulties and mean turns saved."
	CloseButton.text = "Close"
