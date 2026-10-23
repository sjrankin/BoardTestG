class_name ColorGoalBadge
extends Control
## One color of the goal: a circle in that color with the number of pieces still to remove inside it.

const Diameter := 84.0
const FontSize := 36

var Tint: Color = Color.WHITE
var Remaining: int = 0:
	set(Value):
		if Value != Remaining:
			Remaining = Value
			queue_redraw()


func _init() -> void:
	custom_minimum_size = Vector2(Diameter, Diameter)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _draw() -> void:
	var Middle := Vector2(Diameter, Diameter) / 2.0
	draw_circle(Middle, Diameter / 2.0, Color(0, 0, 0, 0.55))
	draw_circle(Middle, Diameter / 2.0 - 3.0, Tint)
	var Font := ThemeDB.fallback_font
	var Text := str(Remaining)
	var Size := Font.get_string_size(Text, HORIZONTAL_ALIGNMENT_LEFT, -1, FontSize)
	var At := Vector2(Middle.x - Size.x / 2.0, Middle.y + Font.get_ascent(FontSize) - Size.y / 2.0)
	draw_string_outline(Font, At, Text, HORIZONTAL_ALIGNMENT_LEFT, -1, FontSize, 8, Color(0, 0, 0, 0.8))
	draw_string(Font, At, Text, HORIZONTAL_ALIGNMENT_LEFT, -1, FontSize, Color.WHITE)
