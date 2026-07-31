class_name DeployReticle
extends Control

const COLOUR := Color(0.4, 1.0, 0.6, 0.95)
const THICKNESS := 2.0
const ARM := 13.0
const PAD := 7.0

var _target := Rect2()


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	visible = false


func aim_at(rect: Rect2) -> void:
	_target = rect.grow(PAD)
	visible = true
	queue_redraw()


func clear_target() -> void:
	if not visible:
		return
	visible = false
	queue_redraw()


func target_rect() -> Rect2:
	return _target


func _draw() -> void:
	if not visible:
		return
	var box := _target
	var corners := [
		[box.position, 1.0, 1.0],
		[Vector2(box.end.x, box.position.y), -1.0, 1.0],
		[Vector2(box.position.x, box.end.y), 1.0, -1.0],
		[box.end, -1.0, -1.0],
	]
	for corner in corners:
		var origin: Vector2 = corner[0]
		draw_line(origin, origin + Vector2(float(corner[1]) * ARM, 0.0), COLOUR,
			THICKNESS, true)
		draw_line(origin, origin + Vector2(0.0, float(corner[2]) * ARM), COLOUR,
			THICKNESS, true)
