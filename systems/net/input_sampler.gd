class_name InputSampler
extends Node

const PITCH_LIMIT := deg_to_rad(89.0)

@export var mouse_sensitivity_deg_per_px: float = 0.12

var tick: int = 0
var yaw: float = 0.0
var pitch: float = 0.0

var _dev_damage_latch: bool = false


func _ready() -> void:
	set_process_unhandled_input(true)


func has_focus() -> bool:
	return GameClient.my_entity != null


func capture_mouse() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func release_mouse() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _unhandled_input(event: InputEvent) -> void:
	if not has_focus():
		return

	if event.is_action_pressed("ui_cancel"):
		release_mouse()
		return

	if event is InputEventMouseButton and event.pressed \
			and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		capture_mouse()
		return

	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var scale := deg_to_rad(mouse_sensitivity_deg_per_px)
		yaw -= event.relative.x * scale
		yaw = wrapf(yaw, -PI, PI)
		pitch = clampf(pitch - event.relative.y * scale, -PITCH_LIMIT, PITCH_LIMIT)


func aim_vector() -> Vector3:
	var cp := cos(pitch)
	return Vector3(-sin(yaw) * cp, sin(pitch), -cos(yaw) * cp)


func _physics_process(_delta: float) -> void:
	if not has_focus():
		return

	tick += 1
	var cmd := InputCommand.make(tick, _move_vector(), _button_mask(), aim_vector())
	GameClient.send_command(cmd)
	_poll_dev_keys()


func _move_vector() -> Vector2:
	return Vector2(
		Input.get_action_strength("move_right") - Input.get_action_strength("move_left"),
		Input.get_action_strength("move_forward") - Input.get_action_strength("move_back"))


func _button_mask() -> int:
	var bits := 0
	if Input.is_action_pressed("jump"): bits |= InputCommand.JUMP
	if Input.is_action_pressed("sprint"): bits |= InputCommand.SPRINT
	if Input.is_action_pressed("fire"): bits |= InputCommand.FIRE
	if Input.is_action_pressed("interact"): bits |= InputCommand.INTERACT
	if Input.is_action_pressed("exit_vehicle"): bits |= InputCommand.EXIT
	if Input.is_action_pressed("brake"): bits |= InputCommand.BRAKE
	if Input.is_action_pressed("toggle_engine"): bits |= InputCommand.ENGINE
	if Input.is_action_pressed("weapon_primary"): bits |= InputCommand.WEAPON_PRIMARY
	if Input.is_action_pressed("weapon_secondary"): bits |= InputCommand.WEAPON_SECONDARY
	if Input.is_action_just_released("weapon_cycle_up"): bits |= InputCommand.WEAPON_CYCLE_UP
	if Input.is_action_just_released("weapon_cycle_down"): bits |= InputCommand.WEAPON_CYCLE_DOWN
	return bits


func _poll_dev_keys() -> void:
	var down := Input.is_physical_key_pressed(KEY_K)
	if down and not _dev_damage_latch:
		GameClient.request_dev_damage(25.0)
	_dev_damage_latch = down
