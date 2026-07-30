class_name HitMarker
extends Control

const HOLD_SECONDS := 0.32
const INNER := 7.0
const OUTER := 15.0
const KILL_OUTER := 21.0
const THICKNESS := 2.0
const HIT_COLOUR := Color(1.0, 1.0, 1.0, 0.95)
const KILL_COLOUR := Color(1.0, 0.35, 0.28, 1.0)

var _remaining: float = 0.0
var _killed: bool = false


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false
	set_process(true)


func flash(killed: bool) -> void:
	_killed = killed or (_killed and _remaining > 0.0)
	_remaining = HOLD_SECONDS
	visible = true
	queue_redraw()


func _process(delta: float) -> void:
	if _remaining <= 0.0:
		return
	_remaining = maxf(0.0, _remaining - delta)
	if _remaining <= 0.0:
		visible = false
		_killed = false
	queue_redraw()


func _draw() -> void:
	if _remaining <= 0.0:
		return
	var fade := clampf(_remaining / HOLD_SECONDS, 0.0, 1.0)
	var colour: Color = KILL_COLOUR if _killed else HIT_COLOUR
	colour.a *= fade
	var outer: float = KILL_OUTER if _killed else OUTER
	for step in [Vector2(1, 1), Vector2(1, -1), Vector2(-1, 1), Vector2(-1, -1)]:
		draw_line(step * INNER, step * outer, colour, THICKNESS, true)
