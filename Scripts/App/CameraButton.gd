class_name CameraButton
extends Button
## A round-cornered button with a camera drawn on it (a body, a lens and a little viewfinder bump), like `GearButton`.
## It takes a screenshot of the game.

const IconColor := Color(0.95, 0.95, 0.97)
const BackColor := Color(0.12, 0.12, 0.15, 0.78)
const HoverColor := Color(0.22, 0.22, 0.27, 0.9)
const PressedColor := Color(0.3, 0.3, 0.38, 0.95)


func _init() -> void:
	text = ""
	focus_mode = Control.FOCUS_NONE
	for StyleName in ["normal", "hover", "pressed", "focus"]:
		var Style := StyleBoxFlat.new()
		Style.bg_color = BackColor
		if StyleName == "hover":
			Style.bg_color = HoverColor
		elif StyleName == "pressed":
			Style.bg_color = PressedColor
		Style.set_corner_radius_all(14)
		add_theme_stylebox_override(StyleName, Style)


func _draw() -> void:
	var Unit := minf(size.x, size.y) / 64.0
	var Center := size / 2.0
	var Hole := BackColor
	if is_pressed():
		Hole = PressedColor
	elif is_hovered():
		Hole = HoverColor
	Hole = Color(Hole.r, Hole.g, Hole.b, 1.0)
	# The viewfinder bump on top, then the body, then the lens ring and glass.
	draw_rect(Rect2(Center + Vector2(-9, -17) * Unit, Vector2(18, 8) * Unit), IconColor)
	draw_rect(Rect2(Center + Vector2(-22, -11) * Unit, Vector2(44, 28) * Unit), IconColor)
	draw_circle(Center + Vector2(0, 3) * Unit, 10.0 * Unit, Hole)
	draw_circle(Center + Vector2(0, 3) * Unit, 6.5 * Unit, IconColor)
	draw_circle(Center + Vector2(0, 3) * Unit, 3.0 * Unit, Hole)
