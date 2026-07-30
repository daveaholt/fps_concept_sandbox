class_name HullIndicator
extends Control

const TRACK_HALF_SPACING := 17.0
const TRACK_HALF_LENGTH := 27.0
const NOSE_RISE := 11.0
const THICKNESS := 2.0
const COLOUR := Color(0.62, 0.88, 0.7, 0.7)


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_hull_angle(0.0)


func set_hull_angle(radians: float) -> void:
	rotation = radians
	queue_redraw()


func forward() -> Vector2:
	return Vector2(sin(rotation), -cos(rotation))


func _draw() -> void:
	var x := TRACK_HALF_SPACING
	var y := TRACK_HALF_LENGTH
	draw_line(Vector2(-x, -y), Vector2(-x, y), COLOUR, THICKNESS, true)
	draw_line(Vector2(x, -y), Vector2(x, y), COLOUR, THICKNESS, true)
	draw_line(Vector2(-x, -y), Vector2(0.0, -y - NOSE_RISE), COLOUR, THICKNESS, true)
	draw_line(Vector2(x, -y), Vector2(0.0, -y - NOSE_RISE), COLOUR, THICKNESS, true)
