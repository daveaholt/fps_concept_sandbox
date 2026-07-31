class_name Minimap
extends Control

const SIZE := 190.0
const RANGE_METRES := 130.0
const FRIENDLY := Color(0.35, 0.95, 0.5)
const ENEMY := Color(1.0, 0.35, 0.3)
const NEUTRAL := Color(0.62, 0.66, 0.72)
const FRAME := Color(0.75, 0.8, 0.86, 0.55)
const BACKDROP := Color(0.05, 0.07, 0.09, 0.55)
const SELF_ARROW := 7.0
const MATE_DOT := 4.0
const SPAWN_DOT := 3.0
const PING_MAX := 9.0

var _origin := Vector3.ZERO
var _yaw := 0.0
var _live := false
var _mates: Array = []
var _spawns: Array = []
var _pings: Array = []


func _ready() -> void:
	custom_minimum_size = Vector2(SIZE, SIZE)
	size = Vector2(SIZE, SIZE)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func show_world(origin: Vector3, yaw: float, mates: Array, spawns: Array,
		pings: Array) -> void:
	_origin = origin
	_yaw = yaw
	_mates = mates
	_spawns = spawns
	_pings = pings
	_live = true
	queue_redraw()


func go_dark() -> void:
	if not _live:
		return
	_live = false
	queue_redraw()


func centre() -> Vector2:
	return Vector2(SIZE, SIZE) * 0.5


func scale_factor() -> float:
	return (SIZE * 0.5) / RANGE_METRES


func to_map(world: Vector3, origin: Vector3) -> Vector2:
	var delta := world - origin
	return centre() + Vector2(delta.x, delta.z) * scale_factor()


func on_map(point: Vector2) -> bool:
	return point.distance_to(centre()) <= SIZE * 0.5


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, Vector2(SIZE, SIZE)), BACKDROP, true)
	draw_rect(Rect2(Vector2.ZERO, Vector2(SIZE, SIZE)), FRAME, false, 1.5)
	if not _live:
		return

	for spawn in _spawns:
		_dot(to_map(spawn, _origin), SPAWN_DOT, NEUTRAL)

	for mate in _mates:
		_dot(to_map(mate, _origin), MATE_DOT, FRIENDLY)

	for ping in _pings:
		var fade: float = ping["fade"]
		var point := to_map(ping["position"], _origin)
		if not on_map(point):
			continue
		var colour := ENEMY
		colour.a = fade
		draw_arc(point, PING_MAX * (1.0 - fade) + 2.0, 0.0, TAU, 18, colour, 1.6, true)

	_draw_self()


func _draw_self() -> void:
	var facing := Vector2(sin(_yaw), -cos(_yaw))
	var side := Vector2(-facing.y, facing.x)
	var tip := centre() + facing * SELF_ARROW
	var left := centre() - facing * SELF_ARROW * 0.6 + side * SELF_ARROW * 0.55
	var right := centre() - facing * SELF_ARROW * 0.6 - side * SELF_ARROW * 0.55
	draw_colored_polygon(PackedVector2Array([tip, left, right]), FRIENDLY)


func _dot(point: Vector2, radius: float, colour: Color) -> void:
	if not on_map(point):
		return
	draw_circle(point, radius, colour)
