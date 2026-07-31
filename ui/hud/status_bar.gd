class_name StatusBar
extends Control

const BACKDROP := Color(0.08, 0.09, 0.11, 0.7)
const FRAME := Color(0.75, 0.8, 0.86, 0.4)

var fraction: float = 1.0
var colour: Color = Color.WHITE


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func setup(width: float, height: float, tint: Color) -> void:
	custom_minimum_size = Vector2(width, height)
	size = Vector2(width, height)
	colour = tint
	queue_redraw()


func set_fraction(value: float) -> void:
	var clamped := clampf(value, 0.0, 1.0)
	if is_equal_approx(clamped, fraction):
		return
	fraction = clamped
	queue_redraw()


func set_colour(tint: Color) -> void:
	if tint == colour:
		return
	colour = tint
	queue_redraw()


func _draw() -> void:
	var box := Rect2(Vector2.ZERO, size)
	draw_rect(box, BACKDROP, true)
	if fraction > 0.0:
		draw_rect(Rect2(Vector2.ZERO, Vector2(size.x * fraction, size.y)), colour, true)
	draw_rect(box, FRAME, false, 1.0)
