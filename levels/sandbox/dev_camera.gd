extends Camera3D

@export var move_speed: float = 22.0
@export var boost_multiplier: float = 4.0
@export var mouse_sensitivity: float = 0.0025

var _looking: bool = false
var _yaw: float = 0.0
var _pitch: float = 0.0


func _ready() -> void:
	_yaw = rotation.y
	_pitch = rotation.x
	far = 2000.0


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT:
		_set_looking(event.pressed)
	elif event is InputEventMouseMotion and _looking:
		_yaw -= event.relative.x * mouse_sensitivity
		_pitch = clampf(_pitch - event.relative.y * mouse_sensitivity, -1.5, 1.5)
		rotation = Vector3(_pitch, _yaw, 0.0)
	elif event.is_action_pressed("ui_cancel"):
		_set_looking(false)


func _set_looking(active: bool) -> void:
	_looking = active
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if active else Input.MOUSE_MODE_VISIBLE


func _process(delta: float) -> void:
	var dir := Vector3.ZERO
	if Input.is_physical_key_pressed(KEY_W): dir -= basis.z
	if Input.is_physical_key_pressed(KEY_S): dir += basis.z
	if Input.is_physical_key_pressed(KEY_A): dir -= basis.x
	if Input.is_physical_key_pressed(KEY_D): dir += basis.x
	if Input.is_physical_key_pressed(KEY_R): dir += Vector3.UP
	if Input.is_physical_key_pressed(KEY_F): dir += Vector3.DOWN
	if dir == Vector3.ZERO:
		return

	var speed := move_speed
	if Input.is_key_pressed(KEY_SHIFT):
		speed *= boost_multiplier
	position += dir.normalized() * speed * delta
