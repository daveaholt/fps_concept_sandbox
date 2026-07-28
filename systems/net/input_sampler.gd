class_name InputSampler
extends Node

const PITCH_LIMIT := deg_to_rad(89.0)

@export var invert_look_y: bool = true
@export var mouse_sensitivity_deg_per_px: float = 0.12
@export var stick_look_speed_deg: float = 200.0
@export var stick_look_exponent: float = 2.0

var tick: int = 0
var yaw: float = 0.0
var pitch: float = 0.0

var _latched_buttons: int = 0
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

	if event.is_action_pressed("weapon_cycle_up"):
		_latched_buttons |= InputCommand.WEAPON_CYCLE_UP
	elif event.is_action_pressed("weapon_cycle_down"):
		_latched_buttons |= InputCommand.WEAPON_CYCLE_DOWN

	if event.is_action_pressed("ui_cancel"):
		release_mouse()
		return

	if event is InputEventMouseButton and event.pressed \
			and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		capture_mouse()
		return

	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var scale := deg_to_rad(mouse_sensitivity_deg_per_px)
		_add_look(-event.relative.x * scale, -event.relative.y * scale)


func aim_vector() -> Vector3:
	var cp := cos(pitch)
	return Vector3(-sin(yaw) * cp, sin(pitch), -cos(yaw) * cp)


func _add_look(delta_yaw: float, delta_pitch: float) -> void:
	yaw = wrapf(yaw + delta_yaw, -PI, PI)
	var applied := -delta_pitch if invert_look_y else delta_pitch
	pitch = clampf(pitch + applied, -PITCH_LIMIT, PITCH_LIMIT)


func _apply_stick_look(delta: float) -> void:
	var stick := Vector2(
		Input.get_action_strength("look_right") - Input.get_action_strength("look_left"),
		Input.get_action_strength("look_down") - Input.get_action_strength("look_up"))
	var magnitude := minf(stick.length(), 1.0)
	if magnitude < 0.001:
		return
	var shaped := stick.normalized() * pow(magnitude, stick_look_exponent)
	var rate := deg_to_rad(stick_look_speed_deg) * delta
	_add_look(-shaped.x * rate, -shaped.y * rate)


func _physics_process(delta: float) -> void:
	if not has_focus():
		_latched_buttons = 0
		return

	_apply_stick_look(delta)
	tick += 1
	var cmd := InputCommand.make(tick, _move_vector(), _button_mask(), aim_vector())
	_latched_buttons = 0
	GameClient.send_command(cmd)
	_poll_dev_keys()


func _move_vector() -> Vector2:
	return Vector2(
		Input.get_action_strength("move_right") - Input.get_action_strength("move_left"),
		Input.get_action_strength("move_forward") - Input.get_action_strength("move_back"))


func _button_mask() -> int:
	var bits := _latched_buttons
	if Input.is_action_pressed("jump"): bits |= InputCommand.JUMP
	if Input.is_action_pressed("sprint"): bits |= InputCommand.SPRINT
	if Input.is_action_pressed("fire"): bits |= InputCommand.FIRE
	if Input.is_action_pressed("interact"): bits |= InputCommand.INTERACT
	if Input.is_action_pressed("exit_vehicle"): bits |= InputCommand.EXIT
	if Input.is_action_pressed("brake"): bits |= InputCommand.BRAKE
	if Input.is_action_pressed("toggle_engine"): bits |= InputCommand.ENGINE
	if Input.is_action_pressed("weapon_primary"): bits |= InputCommand.WEAPON_PRIMARY
	if Input.is_action_pressed("weapon_secondary"): bits |= InputCommand.WEAPON_SECONDARY
	return bits


func _poll_dev_keys() -> void:
	var down := Input.is_physical_key_pressed(KEY_K)
	if down and not _dev_damage_latch:
		GameClient.request_dev_damage(25.0)
	_dev_damage_latch = down
