class_name GearButton
extends Button
## A round button with a gear drawn on it (Godot has no built-in gear icon at run time, so it is drawn here from a circle,
## eight teeth and a hole). It is the button that opens the settings window.

const ToothCount := 8
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
	var Center := size / 2.0
	var Radius := minf(size.x, size.y) * 0.34
	var BodyRadius := Radius * 0.78
	# Each tooth is a short wide wedge sticking out of the body.
	for Tooth in ToothCount:
		var Angle := TAU * Tooth / ToothCount
		var Half := TAU / ToothCount * 0.2
		var Points := PackedVector2Array([
			Center + Vector2.from_angle(Angle - Half) * BodyRadius * 0.9,
			Center + Vector2.from_angle(Angle - Half * 0.7) * Radius * 1.12,
			Center + Vector2.from_angle(Angle + Half * 0.7) * Radius * 1.12,
			Center + Vector2.from_angle(Angle + Half) * BodyRadius * 0.9,
		])
		draw_colored_polygon(Points, IconColor)
	draw_circle(Center, BodyRadius, IconColor)
	# The hole, in the color of whatever the button is showing behind it.
	var Hole := BackColor
	if is_pressed():
		Hole = PressedColor
	elif is_hovered():
		Hole = HoverColor
	draw_circle(Center, BodyRadius * 0.42, Color(Hole.r, Hole.g, Hole.b, 1.0))
