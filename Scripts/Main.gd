extends Node3D
## BoardTestG - the 2D board of BoardTestRK, in Godot. Builds the whole scene in code: camera, light, checkerboard
## floor, the board, and the controls. Rules live in `BoardModel`; drawing and animation in `BoardView`.
##
## For a visual check without a person at the keyboard: run with `-- --capture=/some/dir` and it plays itself in
## Attract Mode, saves screenshots, and quits. `--shape=N` picks the block shape (0 cube, 1 sphere, 2 cone, 3 cylinder).

const DefaultWidth := 11
const DefaultHeight := 11
const DefaultColors := 5
const DefaultBlockers := 0
const AttractDelay := 0.25
## The 3D scene is drawn at least this many pixels tall before being scaled down to the window, whatever the window's
## size: a small window gets more supersampling, a window already this tall gets none.
const TargetRenderHeight := 2400.0
const MaxSuperSampling := 2.0
const SettingsPath := "user://Settings.cfg"
const MinRemovalSpeed := 0.25
const MaxRemovalSpeed := 3.0

var View: BoardView
var CameraNode: Camera3D
var ScoreLabel: Label
var FpsLabel: Label
var AttractCheck: CheckButton
var WidthField: SpinBox
var HeightField: SpinBox
var ColorsField: SpinBox
var BlockersField: SpinBox
var ShapePicker: OptionButton
## The board's size, colors and Blockers - the defaults the first time, then whatever was last set.
var BoardWidth: int = DefaultWidth
var BoardHeight: int = DefaultHeight
var BoardColors: int = DefaultColors
var BoardBlockers: int = DefaultBlockers
var SpeedSlider: HSlider
var SpeedLabel: Label
var AttractClock: float = 0.0
var CameraDistance: float = 0.0
var CaptureDirectory: String = ""
var FrameCount: int = 0


func _ready() -> void:
	UpdateSuperSampling()
	get_window().size_changed.connect(UpdateSuperSampling)
	BuildEnvironment()
	BuildFloor()
	View = BoardView.new()
	add_child(View)
	View.ScoreChanged.connect(OnScoreChanged)
	View.BoardRebuilt.connect(FrameCamera)
	BoardWidth = clampi(int(LoadSetting("Width", DefaultWidth)), 3, 15)
	BoardHeight = clampi(int(LoadSetting("Height", DefaultHeight)), 3, 15)
	BoardColors = clampi(int(LoadSetting("Colors", DefaultColors)), 3, 8)
	BoardBlockers = clampi(int(LoadSetting("Blockers", DefaultBlockers)), 0, 20)
	BuildHud()
	View.CurrentShape = ShapePicker.selected
	View.NewGame(BoardWidth, BoardHeight, BoardColors, BoardBlockers)
	for Argument in OS.get_cmdline_user_args():
		if Argument.begins_with("--shape="):
			ShapePicker.selected = int(Argument.trim_prefix("--shape="))
			View.SetBlockShape(ShapePicker.selected)
		if Argument.begins_with("--capture="):
			CaptureDirectory = Argument.trim_prefix("--capture=")
			DirAccess.make_dir_recursive_absolute(CaptureDirectory)
			AttractCheck.button_pressed = true


# MARK: Scene

## Keeps edges smooth at any window size. Resizing the window changes how many pixels the 3D scene gets, and the
## edge smoothing (MSAA) alone is not enough when the scene is drawn at a low resolution, so the scene is drawn
## larger than the window when the window is small, and scaled down - supersampling.
func UpdateSuperSampling() -> void:
	var PixelHeight := float(maxi(DisplayServer.window_get_size().y, 1))
	get_viewport().scaling_3d_scale = clampf(TargetRenderHeight / PixelHeight, 1.0, MaxSuperSampling)

func BuildEnvironment() -> void:
	var Sky := Environment.new()
	Sky.background_mode = Environment.BG_COLOR
	Sky.background_color = Color(0.42, 0.42, 0.44)
	Sky.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	Sky.ambient_light_color = Color(0.75, 0.75, 0.8)
	Sky.ambient_light_energy = 0.55
	var WorldEnv := WorldEnvironment.new()
	WorldEnv.environment = Sky
	add_child(WorldEnv)
	var Sun := DirectionalLight3D.new()
	Sun.rotation_degrees = Vector3(-40, 25, 0)
	Sun.light_energy = 1.1
	Sun.shadow_enabled = true
	add_child(Sun)
	CameraNode = Camera3D.new()
	CameraNode.fov = 45.0
	add_child(CameraNode)


func BuildFloor() -> void:
	var Checker := Image.create(2, 2, false, Image.FORMAT_RGB8)
	Checker.set_pixel(0, 0, Color(0.16, 0.16, 0.17))
	Checker.set_pixel(1, 1, Color(0.16, 0.16, 0.17))
	Checker.set_pixel(1, 0, Color(0.05, 0.05, 0.06))
	Checker.set_pixel(0, 1, Color(0.05, 0.05, 0.06))
	var Material := StandardMaterial3D.new()
	Material.albedo_texture = ImageTexture.create_from_image(Checker)
	Material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS
	Material.uv1_scale = Vector3(40, 40, 1)
	Material.roughness = 0.9
	var Plane := PlaneMesh.new()
	Plane.size = Vector2(80, 80)
	var Ground := MeshInstance3D.new()
	Ground.mesh = Plane
	Ground.material_override = Material
	add_child(Ground)
	var Body := StaticBody3D.new()
	var Shape := CollisionShape3D.new()
	var Slab := BoxShape3D.new()
	Slab.size = Vector3(80, 1, 80)
	Shape.shape = Slab
	Shape.position = Vector3(0, -0.5, 0)
	Body.add_child(Shape)
	var Physical := PhysicsMaterial.new()
	Physical.friction = 0.9
	Physical.bounce = 0.15
	Body.physics_material_override = Physical
	add_child(Body)


## Backs the camera off far enough to see the whole board, aimed at its middle.
func FrameCamera() -> void:
	var Size := maxf(View.Model.Width, View.Model.Height)
	CameraDistance = Size * 2.5
	PlaceCamera()


func PlaceCamera() -> void:
	var Middle := Vector3(0, View.Model.Height * 0.38, 0)
	CameraNode.position = Middle + Vector3(0, CameraDistance * 0.34, CameraDistance)
	CameraNode.look_at(Middle, Vector3.UP)


# MARK: Controls

func BuildHud() -> void:
	var Layer := CanvasLayer.new()
	add_child(Layer)
	var Bar := HBoxContainer.new()
	Bar.position = Vector2(16, 12)
	Bar.add_theme_constant_override("separation", 18)
	Layer.add_child(Bar)
	var ScoreBox := VBoxContainer.new()
	var ScoreTitle := Label.new()
	ScoreTitle.text = "Score"
	ScoreLabel = Label.new()
	ScoreLabel.text = "0"
	ScoreLabel.add_theme_font_size_override("font_size", 40)
	ScoreBox.add_child(ScoreTitle)
	ScoreBox.add_child(ScoreLabel)
	Bar.add_child(ScoreBox)
	var FpsBox := VBoxContainer.new()
	var FpsTitle := Label.new()
	FpsTitle.text = "FPS"
	FpsLabel = Label.new()
	FpsLabel.add_theme_font_size_override("font_size", 40)
	FpsBox.add_child(FpsTitle)
	FpsBox.add_child(FpsLabel)
	Bar.add_child(FpsBox)

	var Controls := HBoxContainer.new()
	Controls.add_theme_constant_override("separation", 14)
	Controls.anchor_left = 0.0
	Controls.anchor_top = 1.0
	Controls.anchor_bottom = 1.0
	Controls.position = Vector2(16, -52)
	Layer.add_child(Controls)
	var ShapeCaption := Label.new()
	ShapeCaption.text = "Block Shape"
	Controls.add_child(ShapeCaption)
	ShapePicker = OptionButton.new()
	for Name in BoardView.ShapeNames:
		ShapePicker.add_item(Name)
	ShapePicker.selected = LoadSetting("BlockShape", 0)
	ShapePicker.item_selected.connect(OnShapeSelected)
	Controls.add_child(ShapePicker)
	var ShuffleButton := Button.new()
	ShuffleButton.text = "Shuffle"
	ShuffleButton.pressed.connect(func() -> void: View.ShuffleNow())
	Controls.add_child(ShuffleButton)
	AttractCheck = CheckButton.new()
	AttractCheck.text = "Attract Mode"
	Controls.add_child(AttractCheck)
	WidthField = AddField(Controls, "Width", BoardWidth, 3, 15)
	HeightField = AddField(Controls, "Height", BoardHeight, 3, 15)
	ColorsField = AddField(Controls, "Colors", BoardColors, 3, 8)
	BlockersField = AddField(Controls, "Blockers", BoardBlockers, 0, 20)
	var SetButton := Button.new()
	SetButton.text = "Set"
	SetButton.pressed.connect(OnSetPressed)
	Controls.add_child(SetButton)
	var SpeedCaption := Label.new()
	SpeedCaption.text = "Removal Speed"
	Controls.add_child(SpeedCaption)
	SpeedSlider = HSlider.new()
	SpeedSlider.min_value = MinRemovalSpeed
	SpeedSlider.max_value = MaxRemovalSpeed
	SpeedSlider.step = 0.05
	SpeedSlider.custom_minimum_size = Vector2(180, 0)
	SpeedSlider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	SpeedSlider.value = LoadRemovalSpeed()
	SpeedSlider.value_changed.connect(OnSpeedChanged)
	Controls.add_child(SpeedSlider)
	SpeedLabel = Label.new()
	Controls.add_child(SpeedLabel)
	OnSpeedChanged(SpeedSlider.value)


func AddField(Parent: Control, Title: String, Value: int, Low: int, High: int) -> SpinBox:
	var Caption := Label.new()
	Caption.text = Title
	Parent.add_child(Caption)
	var Field := SpinBox.new()
	Field.min_value = Low
	Field.max_value = High
	Field.value = Value
	Parent.add_child(Field)
	return Field


func OnSetPressed() -> void:
	AttractCheck.button_pressed = false
	BoardWidth = int(WidthField.value)
	BoardHeight = int(HeightField.value)
	BoardColors = int(ColorsField.value)
	BoardBlockers = int(BlockersField.value)
	SaveSetting("Width", BoardWidth)
	SaveSetting("Height", BoardHeight)
	SaveSetting("Colors", BoardColors)
	SaveSetting("Blockers", BoardBlockers)
	View.NewGame(BoardWidth, BoardHeight, BoardColors, BoardBlockers)


## Applies the slider's value to every piece removed from now on, and remembers it between launches.
func OnSpeedChanged(NewSpeed: float) -> void:
	View.RemovalSpeed = NewSpeed
	SpeedLabel.text = "%.2fx" % NewSpeed
	var Settings := ConfigFile.new()
	Settings.load(SettingsPath)
	Settings.set_value("Game", "RemovalSpeed", NewSpeed)
	Settings.save(SettingsPath)


func OnShapeSelected(Index: int) -> void:
	View.SetBlockShape(Index)
	SaveSetting("BlockShape", Index)


func LoadSetting(Name: String, Default: Variant) -> Variant:
	var Settings := ConfigFile.new()
	if Settings.load(SettingsPath) != OK:
		return Default
	return Settings.get_value("Game", Name, Default)


func SaveSetting(Name: String, Value: Variant) -> void:
	var Settings := ConfigFile.new()
	Settings.load(SettingsPath)
	Settings.set_value("Game", Name, Value)
	Settings.save(SettingsPath)


func LoadRemovalSpeed() -> float:
	var Settings := ConfigFile.new()
	if Settings.load(SettingsPath) != OK:
		return 1.0
	return clampf(float(Settings.get_value("Game", "RemovalSpeed", 1.0)), MinRemovalSpeed, MaxRemovalSpeed)


func OnScoreChanged(NewScore: int) -> void:
	ScoreLabel.text = str(NewScore)


# MARK: Input and per-frame

func _unhandled_input(Event: InputEvent) -> void:
	if Event is InputEventMouseButton and Event.pressed:
		if Event.button_index == MOUSE_BUTTON_LEFT:
			var Origin := CameraNode.project_ray_origin(Event.position)
			var Direction := CameraNode.project_ray_normal(Event.position)
			View.HandleTapRay(Origin, Direction)
		elif Event.button_index == MOUSE_BUTTON_WHEEL_UP:
			CameraDistance = maxf(CameraDistance * 0.93, 4.0)
			PlaceCamera()
		elif Event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			CameraDistance = minf(CameraDistance * 1.07, 60.0)
			PlaceCamera()


func _process(Delta: float) -> void:
	FrameCount += 1
	FpsLabel.text = str(int(Engine.get_frames_per_second()))
	if AttractCheck.button_pressed and not View.Busy:
		AttractClock += Delta
		if AttractClock >= AttractDelay:
			AttractClock = 0.0
			View.AttractStep()
	if CaptureDirectory != "":
		RunCapture()


## Presses Shuffle early, saves screenshots at a few moments of an Attract Mode run, then quits.
func RunCapture() -> void:
	if FrameCount == 2:
		AttractCheck.button_pressed = false
	if FrameCount == 8:
		View.ShuffleNow()
	if FrameCount == 120:
		AttractCheck.button_pressed = true
	for Moment in [20, 35, 150, 330, 900]:
		if FrameCount == Moment:
			var Shot := get_viewport().get_texture().get_image()
			Shot.save_png("%s/Shot%04d.png" % [CaptureDirectory, FrameCount])
	if FrameCount > 905:
		print("Score after the run: ", View.Model.Score)
		get_tree().quit()
