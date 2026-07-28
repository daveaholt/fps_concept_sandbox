extends VehicleBody3D

signal fired(origin: Vector3, direction: Vector3, params_id: int)

@export var max_engine_force: float = 14000.0
@export var pivot_force: float = 10000.0
@export var steer_authority_low: float = 0.6
@export var steer_authority_high: float = 0.45
@export var max_speed: float = 14.0
@export var brake_force: float = 900.0
@export var idle_brake: float = 350.0
@export var wheel_friction_slip: float = 2.0
@export var suspension_rest_length: float = 0.55
@export var suspension_max_force_n: float = 20000.0
@export var suspension_damping_compression: float = 3.0
@export var suspension_damping_relaxation: float = 4.0
@export var max_yaw_rate: float = 1.35
@export var yaw_accel: float = 25.0
@export var yaw_inertia: float = 16667.0

@export var turret_yaw_speed_deg: float = 60.0
@export var cannon_pitch_speed_deg: float = 30.0
@export var cannon_pitch_min_deg: float = -8.0
@export var cannon_pitch_max_deg: float = 20.0

@export var armour_front: float = 1.0
@export var armour_side: float = 1.25
@export var armour_rear: float = 2.0
@export var armour_top: float = 1.5
@export var deck_height: float = 1.25

@export var shell_params_id: int = 2
@export var fire_cooldown_time: float = 2.5
@export var recoil_impulse: float = 9000.0
@export var camera_pivot_height: float = 1.85
@export var camera_spring_length: float = 8.0
@export var camera_pitch_min_deg: float = -8.0
@export var camera_pitch_max_deg: float = 20.0

var owner_peer: int = 0
var health: float = 500.0

var _common: VehicleCommon
var _turret_yaw: Node3D
var _cannon_pitch: Node3D
var _muzzle: Marker3D
var _left_wheels: Array[VehicleWheel3D] = []
var _right_wheels: Array[VehicleWheel3D] = []

var _pending: Array[InputCommand] = []
var _last_command: InputCommand = InputCommand.new()
var _aim: Vector3 = Vector3.FORWARD
var _turret_yaw_angle: float = 0.0
var _cannon_pitch_angle: float = 0.0
var _possessed: bool = false
var _server_authority: bool = true
var _predict_turret: bool = false
var _cooldown: float = 0.0
var _shots_fired: int = 0
var _spring: SpringArm3D
var _camera: Camera3D
var _history := PositionHistory.new()


func _ready() -> void:
	_server_authority = multiplayer.multiplayer_peer == null or multiplayer.is_server()
	add_to_group("controllable")
	add_to_group("vehicle")
	add_to_group("tank")

	_common = get_node_or_null("VehicleCommon")
	_turret_yaw = get_node_or_null("TurretYaw")
	_cannon_pitch = get_node_or_null("TurretYaw/CannonPitch")
	_muzzle = get_node_or_null("TurretYaw/CannonPitch/Muzzle")
	_spring = get_node_or_null("SeatCameraRig/SpringArm3D")
	_camera = get_node_or_null("SeatCameraRig/SpringArm3D/Camera3D")
	if _spring != null:
		_spring.spring_length = camera_spring_length
		_spring.top_level = true
	if _camera != null:
		_camera.current = false

	for wheel in find_children("*", "VehicleWheel3D", true, false):
		wheel.wheel_friction_slip = wheel_friction_slip
		wheel.wheel_rest_length = suspension_rest_length
		wheel.suspension_max_force = suspension_max_force_n
		wheel.damping_compression = suspension_damping_compression
		wheel.damping_relaxation = suspension_damping_relaxation
		if wheel.position.x < 0.0:
			_left_wheels.append(wheel)
		else:
			_right_wheels.append(wheel)

	if _server_authority:
		physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_ON
	else:
		physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
		freeze = true
	reset_physics_interpolation()


func get_display_name() -> String:
	return "Tank"


func possess() -> void:
	_possessed = true
	_predict_turret = not _server_authority
	if _camera != null:
		_camera.current = true


func unpossess() -> void:
	_possessed = false
	_predict_turret = false
	if _camera != null:
		_camera.current = false
	_last_command = InputCommand.new()


func is_possessed() -> bool:
	return _possessed


func is_occupied() -> bool:
	return owner_peer != 0


func can_exit() -> bool:
	return true


func common() -> VehicleCommon:
	return _common


func push_command(cmd: InputCommand) -> void:
	_pending.append(cmd)


func speed_kmh() -> float:
	return linear_velocity.length() * 3.6


func turret_angles() -> Vector2:
	return Vector2(_turret_yaw_angle, _cannon_pitch_angle)


func muzzle_transform() -> Transform3D:
	return _muzzle.global_transform if _muzzle != null else global_transform


func get_net_state() -> Dictionary:
	return {
		"p": global_position,
		"q": global_transform.basis.get_rotation_quaternion(),
		"ty": _turret_yaw_angle,
		"cp": _cannon_pitch_angle,
		"v": linear_velocity,
		"o": owner_peer,
	}


func apply_replicated_state(net_state: Dictionary) -> void:
	if _server_authority:
		return
	var quat: Quaternion = net_state.get("q", Quaternion())
	global_transform = Transform3D(Basis(quat), net_state.get("p", global_position))
	if not _predict_turret:
		_turret_yaw_angle = net_state.get("ty", _turret_yaw_angle)
		_cannon_pitch_angle = net_state.get("cp", _cannon_pitch_angle)
	owner_peer = net_state.get("o", owner_peer)
	_apply_turret()


func get_history() -> PositionHistory:
	return _history


func hit_half_extents() -> Vector3:
	return Vector3(1.7, 0.775, 3.1)


func hit_centre_y() -> float:
	return 0.775


func resolve_sector(world_point: Vector3) -> Dictionary:
	var local := global_transform.affine_inverse() * world_point
	if local.y > deck_height:
		return {"sector": "top", "multiplier": armour_top}

	var flat := Vector2(local.x, local.z)
	if flat.length() < 0.001:
		return {"sector": "top", "multiplier": armour_top}

	var forward_angle := rad_to_deg(Vector2(0.0, -1.0).angle_to(flat.normalized()))
	var magnitude := absf(forward_angle)
	if magnitude <= 45.0:
		return {"sector": "front", "multiplier": armour_front}
	if magnitude >= 135.0:
		return {"sector": "rear", "multiplier": armour_rear}
	return {"sector": "side", "multiplier": armour_side}


func apply_damage(amount: float) -> void:
	if not _server_authority:
		return
	health = maxf(0.0, health - amount)


func _next_command() -> InputCommand:
	if not _pending.is_empty():
		_last_command = _pending.pop_front()
	return _last_command


func _physics_process(delta: float) -> void:
	if not _server_authority:
		return

	var cmd := _next_command()
	var driving := owner_peer != 0
	var throttle := cmd.move.y if driving else 0.0
	var steer_input := cmd.move.x if driving else 0.0
	if driving:
		_aim = cmd.aim

	_drive(throttle, steer_input, driving and cmd.held(InputCommand.BRAKE), delta)
	_step_turret(delta, driving)
	_apply_turret()
	_history.push(float(Time.get_ticks_msec()) * 0.001, global_position, -global_transform.basis.z)
	_cooldown = maxf(0.0, _cooldown - delta)
	if driving and cmd.held(InputCommand.FIRE):
		_try_fire()


func _try_fire() -> void:
	if _cooldown > 0.0 or _muzzle == null:
		return
	_cooldown = fire_cooldown_time
	_shots_fired += 1
	var origin := _muzzle.global_position
	var direction := -_muzzle.global_transform.basis.z
	fired.emit(origin, direction, shell_params_id)
	apply_impulse(-direction * recoil_impulse, Vector3.UP * 1.2)


func reload_fraction() -> float:
	if fire_cooldown_time <= 0.0:
		return 1.0
	return clampf(1.0 - _cooldown / fire_cooldown_time, 0.0, 1.0)


func _process(delta: float) -> void:
	if _predict_turret:
		_step_turret(delta, true)
		_apply_turret()
	_update_camera()


func set_local_aim(aim: Vector3) -> void:
	if _predict_turret:
		_aim = aim


func _update_camera() -> void:
	if _spring == null:
		return
	var flat := Vector3(_aim.x, 0.0, _aim.z)
	if flat.length_squared() < 0.000001:
		flat = Vector3.FORWARD
	var yaw := atan2(-flat.x, -flat.z)
	var pitch := clampf(asin(clampf(_aim.normalized().y, -1.0, 1.0)),
		deg_to_rad(camera_pitch_min_deg), deg_to_rad(camera_pitch_max_deg))
	var arm_pitch := minf(pitch, 0.0)
	_spring.global_position = global_position + Vector3.UP * camera_pivot_height
	_spring.global_rotation = Vector3(arm_pitch, yaw, 0.0)
	if _camera != null:
		_camera.rotation = Vector3(pitch - arm_pitch, 0.0, 0.0)


func _drive(throttle: float, steer_input: float, braking: bool, delta: float) -> void:
	var speed := linear_velocity.length()
	var authority := lerpf(steer_authority_low, steer_authority_high,
		clampf(speed / maxf(max_speed, 0.001), 0.0, 1.0))
	var governor := clampf(1.0 - speed / maxf(max_speed, 0.001), 0.0, 1.0)

	var pivoting := absf(throttle) < 0.05 and absf(steer_input) > 0.05
	var travel := _travel_direction(throttle)
	var left := 0.0
	var right := 0.0
	if pivoting:
		left = steer_input * pivot_force
		right = -steer_input * pivot_force
	else:
		var inside := steer_input * authority * travel
		left = -(throttle + inside) * max_engine_force * governor
		right = -(throttle - inside) * max_engine_force * governor

	_apply_side(_left_wheels, left)
	_apply_side(_right_wheels, right)
	_apply_yaw(steer_input, authority, pivoting, travel, delta)

	var braking_force := brake_force if braking else 0.0
	if not braking and absf(throttle) < 0.05 and absf(steer_input) < 0.05:
		braking_force = idle_brake
	for wheel in _left_wheels + _right_wheels:
		wheel.brake = braking_force


func _travel_direction(throttle: float) -> float:
	var along := linear_velocity.dot(-global_transform.basis.z)
	if absf(along) > 0.5:
		return signf(along)
	if absf(throttle) > 0.05:
		return signf(throttle)
	return 1.0


func _apply_yaw(steer_input: float, authority: float, pivoting: bool, travel: float,
		delta: float) -> void:
	if absf(steer_input) < 0.05 or _grounded_wheels() == 0:
		return
	var rate := max_yaw_rate if pivoting else max_yaw_rate * authority
	var target := -steer_input * rate
	if not pivoting:
		target *= travel
	var up := global_transform.basis.y
	var spin := angular_velocity.dot(up)
	var accel := clampf((target - spin) / maxf(delta, 0.0001), -yaw_accel, yaw_accel)
	apply_torque(up * accel * yaw_inertia)


func _grounded_wheels() -> int:
	var count := 0
	for wheel in _left_wheels + _right_wheels:
		if wheel.is_in_contact():
			count += 1
	return count


func _apply_side(wheels: Array[VehicleWheel3D], total_force: float) -> void:
	if wheels.is_empty():
		return
	var each := total_force / float(wheels.size())
	for wheel in wheels:
		wheel.engine_force = each


func _step_turret(delta: float, driving: bool) -> void:
	if not driving:
		return
	var flat := Vector3(_aim.x, 0.0, _aim.z)
	if flat.length_squared() < 0.000001:
		return

	var hull_yaw := global_transform.basis.get_euler().y
	var want_yaw := wrapf(atan2(-flat.x, -flat.z) - hull_yaw, -PI, PI)
	var yaw_step := deg_to_rad(turret_yaw_speed_deg) * delta
	_turret_yaw_angle = wrapf(_turret_yaw_angle
		+ clampf(wrapf(want_yaw - _turret_yaw_angle, -PI, PI), -yaw_step, yaw_step), -PI, PI)

	var want_pitch := clampf(asin(clampf(_aim.normalized().y, -1.0, 1.0)),
		deg_to_rad(cannon_pitch_min_deg), deg_to_rad(cannon_pitch_max_deg))
	var pitch_step := deg_to_rad(cannon_pitch_speed_deg) * delta
	_cannon_pitch_angle += clampf(want_pitch - _cannon_pitch_angle, -pitch_step, pitch_step)


func _apply_turret() -> void:
	if _turret_yaw != null:
		_turret_yaw.rotation.y = _turret_yaw_angle
	if _cannon_pitch != null:
		_cannon_pitch.rotation.x = _cannon_pitch_angle
