class_name ControlBarSettings
extends ControlBarHud

## The settings window and its sections.

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
	LayoutPicker = OptionButton.new()
	for Name in BoardLayouts.Names():
		LayoutPicker.add_item(Name)
	LayoutPicker.item_selected.connect(func(Index: int) -> void: LayoutSelected.emit(Index))
	AddRow(Section, "Layout (2D board, gaps in the board)", LayoutPicker)
	WidthField = AddFieldRow(Section, "Width", Width, WidthRange)
	HeightField = AddFieldRow(Section, "Height", Height, WidthRange)
	DepthField = AddFieldRow(Section, "Depth", Width, WidthRange)
	ColorsField = AddFieldRow(Section, "Colors", Colors, ColorsRange)
	BlockersField = AddFieldRow(Section, "Blockers", Blockers, BlockersRange)
	AddButtonRow(Section, "Start a new game with these", "New Game", OnSetPressed)


## Shows the fields of the board type: the 2D board's layout, width, height and Blockers, or the cube's width, height and depth. An
## irregular layout brings its own width and height, so those fields are hidden while one is picked.
func ShowBoardType(Is3D: bool, Width: int, Height: int, Depth: int, Blockers: int, Layout: int = 0) -> void:
	BoardTypePicker.selected = 1 if Is3D else 0
	LayoutPicker.selected = Layout
	LayoutPicker.get_parent().visible = not Is3D
	WidthField.get_parent().visible = Is3D or Layout == 0
	HeightField.get_parent().visible = Is3D or Layout == 0
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
	MetallicCheck = AddCheckRow(Section, "Metallic (pieces look like polished metal)", false)
	MetallicCheck.toggled.connect(func(On: bool) -> void: MetallicToggled.emit(On))


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
	var Titles: Array[String] = ["Spin the light around the board (15 s a turn)", "Move the Blockers after every group (2D)", "Hide one color behind a filter veil (every 20 s, for 10 s)", "Turn the board 45\u00B0 and lock it", "Swap the groups' colors (pick the group by its real color)", "Drain the colors (nearly grey)", "Draw every piece white (work out the groups)"]
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
