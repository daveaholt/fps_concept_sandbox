extends VehicleBody3D

const SEAT_COUNT := 2
const GUNNER_SEAT := 1

signal fired(origin: Vector3, direction: Vector3, params_id: int)
signal gun_fired(origin: Vector3, direction: Vector3, params_id: int)
signal destroyed(vehicle: Node)

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
@export var armour_side: float = 1.0
@export var armour_rear: float = 2.0
@export var armour_top: float = 1.5
@export var small_arms_scale: float = 0.1
@export var deck_height: float = 1.25

@export var gun_params_id: int = 3
@export var gun_rate_per_second: float = 18.0
@export var gun_slew_deg: float = 300.0
@export var gun_yaw_limit_deg: float = 120.0
@export var gun_pitch_min_deg: float = -35.0
@export var gun_pitch_max_deg: float = 20.0
@export var gun_heat_per_shot: float = 0.018
@export var gun_cool_rate: float = 0.45
@export var shell_params_id: int = 2
@export var fire_cooldown_time: float = 2.5
@export var recoil_impulse: float = 9000.0
@export var camera_pivot_height: float = 1.85
@export var camera_spring_length: float = 8.0
@export var camera_pitch_min_deg: float = -8.0
@export var camera_pitch_max_deg: float = 20.0

var owner_peer: int = 0
var team: int = Roster.UNALIGNED
@export var impact_tolerance: float = 7.0
@export var impact_damage_scale: float = 4.0
@export var wreck_blast_damage: float = 200.0
@export var max_health: float = 500.0
var health: float = 500.0
var wrecked: bool = false
var wreck_shown: bool = false
var _damage_state: int = VehicleDamage.State.HEALTHY
var _spawn_transform := Transform3D()
var _last_velocity := Vector3.ZERO
var _live_collision_layer: int = 4
var _entry_shape: CollisionShape3D

var _common: VehicleCommon
var _turret_yaw: Node3D
var _cannon_pitch: Node3D
var _muzzle: Marker3D
var _left_wheels: Array[VehicleWheel3D] = []
var _right_wheels: Array[VehicleWheel3D] = []

var seats := Seats.new(SEAT_COUNT)
var _pending: Array = []
var _last_command: Array = []
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
var _gun_yaw: Node3D
var _gun_pitch: Node3D
var _gun_muzzle: Marker3D
var _gun_yaw_angle: float = 0.0
var _gun_pitch_angle: float = 0.0
var _gun_aim: Vector3 = Vector3.FORWARD
var _gun_cooldown: float = 0.0
var _gun_heat: float = 0.0
var _gunner_rig: Node3D
var _gunner_camera: Camera3D
var _gunner_eye: Marker3D
var _cockpit_camera: Camera3D
var _first_person: bool = false
var _gunner_view_aim: Vector3 = Vector3.FORWARD
var _local_seat: int = -1


func _ready() -> void:
	_server_authority = multiplayer.multiplayer_peer == null or multiplayer.is_server()
	_pending = []
	_last_command = []
	for _i in seats.count():
		_pending.append([])
		_last_command.append(InputCommand.new())

	health = max_health
	_spawn_transform = global_transform
	_live_collision_layer = collision_layer
	_init_gunner()
	add_to_group("controllable")
	add_to_group("vehicle")
	add_to_group("tank")

	_common = get_node_or_null("VehicleCommon")
	_entry_shape = get_node_or_null("VehicleCommon/EntryZone/Shape")
	_turret_yaw = get_node_or_null("TurretYaw")
	_cannon_pitch = get_node_or_null("TurretYaw/CannonPitch")
	_muzzle = get_node_or_null("TurretYaw/CannonPitch/Muzzle")
	_spring = get_node_or_null("SeatCameraRig/SpringArm3D")
	_camera = get_node_or_null("SeatCameraRig/SpringArm3D/Camera3D")
	_cockpit_camera = get_node_or_null("TurretYaw/CannonPitch/DriverEye/Camera3D")
	_gunner_eye = get_node_or_null("GunnerEye")
	_gunner_rig = get_node_or_null("GunnerRig")
	_gunner_camera = get_node_or_null("GunnerRig/Camera3D")
	if _gunner_rig != null:
		_gunner_rig.top_level = true
	if _gunner_camera != null:
		_gunner_camera.current = false
	if _cockpit_camera != null:
		_cockpit_camera.current = false
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


func refresh_authority() -> void:
	var was := _server_authority
	_server_authority = multiplayer.multiplayer_peer == null or multiplayer.is_server()
	if was == _server_authority:
		return
	if _server_authority:
		physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_ON
		freeze = false
	else:
		physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
		freeze = true
	reset_physics_interpolation()


func _init_gunner() -> void:
	_gun_yaw = get_node_or_null("GunYaw")
	_gun_pitch = get_node_or_null("GunYaw/GunPitch")
	_gun_muzzle = get_node_or_null("GunYaw/GunPitch/Muzzle")


func gunner_peer() -> int:
	return seats.occupant(GUNNER_SEAT)


func weapon_ray(seat: int) -> Array:
	var node: Node3D = _gun_muzzle if seat == GUNNER_SEAT else _muzzle
	if node == null:
		return []
	var params: int = gun_params_id if seat == GUNNER_SEAT else shell_params_id
	return [node.global_position, -node.global_transform.basis.z, params]


func gun_angles() -> Vector2:
	return Vector2(_gun_yaw_angle, _gun_pitch_angle)


func gun_heat() -> float:
	return _gun_heat


func _step_gunner(delta: float) -> void:
	var manned := seats.occupant(GUNNER_SEAT) != 0
	var cmd := _next_command(GUNNER_SEAT)
	_gun_cooldown = maxf(0.0, _gun_cooldown - delta)
	if manned and cmd.aim.length_squared() > 0.000001:
		_gun_aim = cmd.aim
	slew_gun(_gun_aim, delta)

	if _gun_heat > 0.0:
		_gun_heat = maxf(0.0, _gun_heat - gun_cool_rate * delta)
	if not manned or not cmd.held(InputCommand.FIRE):
		return
	if _gun_cooldown > 0.0 or _gun_heat >= 1.0:
		return
	_gun_cooldown = 1.0 / maxf(gun_rate_per_second, 0.001)
	_gun_heat = minf(1.0, _gun_heat + gun_heat_per_shot)
	gun_fired.emit(_gun_muzzle.global_position,
		-_gun_muzzle.global_transform.basis.z, gun_params_id)


func slew_gun(aim: Vector3, delta: float) -> void:
	var flat := Vector3(aim.x, 0.0, aim.z)
	if flat.length_squared() > 0.000001:
		var hull_yaw := global_transform.basis.get_euler().y
		var want := wrapf(atan2(-flat.x, -flat.z) - hull_yaw, -PI, PI)
		want = clampf(want, deg_to_rad(-gun_yaw_limit_deg), deg_to_rad(gun_yaw_limit_deg))
		var step := deg_to_rad(gun_slew_deg) * delta
		_gun_yaw_angle = wrapf(_gun_yaw_angle
			+ clampf(wrapf(want - _gun_yaw_angle, -PI, PI), -step, step), -PI, PI)

	var want_pitch := clampf(asin(clampf(aim.normalized().y, -1.0, 1.0)),
		deg_to_rad(gun_pitch_min_deg), deg_to_rad(gun_pitch_max_deg))
	_gun_pitch_angle += clampf(want_pitch - _gun_pitch_angle,
		-deg_to_rad(gun_slew_deg) * delta, deg_to_rad(gun_slew_deg) * delta)
	_apply_gun()


func _apply_gun() -> void:
	if _gun_yaw != null:
		_gun_yaw.rotation.y = _gun_yaw_angle
	if _gun_pitch != null:
		_gun_pitch.rotation.x = _gun_pitch_angle


func get_display_name() -> String:
	return "Tank"


func possess() -> void:
	_possessed = true
	_predict_turret = not _server_authority
	_activate_cameras()


func unpossess() -> void:
	_possessed = false
	_predict_turret = false
	_local_seat = -1
	_activate_cameras()
	for i in _last_command.size():
		_last_command[i] = InputCommand.new()


func _activate_cameras() -> void:
	var gunning := _possessed and _local_seat == GUNNER_SEAT
	var cockpit := _possessed and not gunning and _first_person
	if _camera != null:
		_camera.current = _possessed and not gunning and not cockpit
	if _cockpit_camera != null:
		_cockpit_camera.current = cockpit
	if _gunner_camera != null:
		_gunner_camera.current = gunning
	_refresh_shell()


func toggle_camera() -> void:
	_first_person = not _first_person
	_activate_cameras()


func using_first_person() -> bool:
	return _first_person


func is_possessed() -> bool:
	return _possessed


func is_occupied() -> bool:
	return not seats.is_empty()


func can_exit() -> bool:
	return true


func common() -> VehicleCommon:
	return _common


func push_command(cmd: InputCommand, seat: int = Seats.DRIVER) -> void:
	if seat < 0 or seat >= _pending.size():
		return
	_pending[seat].append(cmd)


func seat_of(peer_id: int) -> int:
	return seats.seat_of(peer_id)


func has_free_seat() -> bool:
	return not wrecked and seats.first_free() >= 0


func take_seat(peer_id: int, seat: int = -1) -> int:
	var index := seat if seat >= 0 else seats.first_free()
	if index < 0 or not seats.take(peer_id, index):
		return -1
	owner_peer = seats.driver()
	return index


func leave_seat(peer_id: int) -> void:
	seats.release(peer_id)
	owner_peer = seats.driver()


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
		"gy": _gun_yaw_angle,
		"gp": _gun_pitch_angle,
		"gh": _gun_heat,
		"v": linear_velocity,
		"o": owner_peer,
		"hp": health,
		"wk": wrecked,
		"ws": wreck_shown,
		"st": seats.to_array(),
	}


func apply_replicated_state(net_state: Dictionary) -> void:
	if _server_authority:
		return
	var quat: Quaternion = net_state.get("q", Quaternion())
	global_transform = Transform3D(Basis(quat), net_state.get("p", global_position))
	if not _predict_turret:
		_turret_yaw_angle = net_state.get("ty", _turret_yaw_angle)
		_cannon_pitch_angle = net_state.get("cp", _cannon_pitch_angle)
	if not _predict_gun():
		_gun_yaw_angle = net_state.get("gy", _gun_yaw_angle)
		_gun_pitch_angle = net_state.get("gp", _gun_pitch_angle)
		_apply_gun()
	_gun_heat = net_state.get("gh", _gun_heat)
	owner_peer = net_state.get("o", owner_peer)
	health = net_state.get("hp", health)
	wrecked = net_state.get("wk", wrecked)
	wreck_shown = net_state.get("ws", wreck_shown)
	refresh_damage_state()
	var wire: Array = net_state.get("st", [])
	if not wire.is_empty():
		seats.clear()
		for i in mini(wire.size(), seats.count()):
			if int(wire[i]) != 0:
				seats.take(int(wire[i]), i)
	_apply_turret()


func get_history() -> PositionHistory:
	return _history


func hit_half_extents() -> Vector3:
	return Vector3(1.7, 0.775, 3.1)


func hit_centre_y() -> float:
	return 0.775


func resolve_sector(world_point: Vector3,
		params: ProjectileParams = null) -> Dictionary:
	var penetration := 1.0 if params == null or params.explosive else small_arms_scale
	var local := global_transform.affine_inverse() * world_point
	if local.y > deck_height:
		return {"sector": "top", "multiplier": armour_top * penetration}

	var flat := Vector2(local.x, local.z)
	if flat.length() < 0.001:
		return {"sector": "top", "multiplier": armour_top * penetration}

	var forward_angle := rad_to_deg(Vector2(0.0, -1.0).angle_to(flat.normalized()))
	var magnitude := absf(forward_angle)
	if magnitude <= 45.0:
		return {"sector": "front", "multiplier": armour_front * penetration}
	if magnitude >= 135.0:
		return {"sector": "rear", "multiplier": armour_rear * penetration}
	return {"sector": "side", "multiplier": armour_side * penetration}


func team_id() -> int:
	return Roster.UNALIGNED if seats.is_empty() else team


func apply_damage(amount: float) -> void:
	if not _server_authority or wrecked:
		return
	health = maxf(0.0, health - amount)
	refresh_damage_state()
	if health <= 0.0:
		destroyed.emit(self)


func blast_radius() -> float:
	return _common.entry_radius() if _common != null else 0.0


func blast_damage() -> float:
	return wreck_blast_damage


func impact_speed() -> float:
	return (linear_velocity - _last_velocity).length()


func _track_impact() -> void:
	var change := impact_speed()
	_last_velocity = linear_velocity
	if wrecked or change <= impact_tolerance:
		return
	var excess := change - impact_tolerance
	var damage := excess * excess * impact_damage_scale
	print("[impact] %s hit at %.1f m/s of change, %.0f damage" % [name, change, damage])
	apply_damage(damage)


func is_alive() -> bool:
	return not wrecked and health > 0.0


func health_fraction() -> float:
	return clampf(health / maxf(max_health, 0.001), 0.0, 1.0)


func damage_state() -> int:
	return _damage_state


func traverse_rate() -> float:
	return VehicleDamage.traverse(_damage_state)


func mobility() -> float:
	return VehicleDamage.mobility(_damage_state)


func refresh_damage_state() -> void:
	_damage_state = VehicleDamage.State.DESTROYED if wrecked 		else VehicleDamage.state_for(health_fraction())
	if _common != null:
		_common.set_damage_state(_damage_state)
	_sync_wreck_presence()


func hide_wreck() -> void:
	if not wreck_shown:
		return
	wreck_shown = false
	_sync_wreck_presence()


func _sync_wreck_presence() -> void:
	visible = not wrecked or wreck_shown
	var layer := 0 if wrecked else _live_collision_layer
	collision_layer = layer
	if _entry_shape != null:
		_entry_shape.disabled = wrecked


func kill_label() -> String:
	return "%s DESTROYED" % get_display_name().to_upper()


func enter_wreck() -> void:
	wrecked = true
	wreck_shown = true
	health = 0.0
	refresh_damage_state()
	for peer in seats.occupants():
		seats.release(peer)
	owner_peer = 0


func reset_for_lobby() -> void:
	for peer in seats.occupants():
		seats.release(peer)
	owner_peer = 0
	team = Roster.UNALIGNED
	_local_seat = -1
	unpossess()
	revive()
	_gun_yaw_angle = 0.0
	_gun_pitch_angle = 0.0
	_gun_heat = 0.0
	_gun_cooldown = 0.0
	_gun_aim = Vector3.FORWARD
	_gunner_view_aim = Vector3.FORWARD
	_apply_gun()
	_turret_yaw_angle = 0.0
	_cannon_pitch_angle = 0.0
	_apply_turret()
	_cooldown = 0.0
	_shots_fired = 0
	_aim = Vector3.FORWARD
	_first_person = false
	for i in _last_command.size():
		_last_command[i] = InputCommand.new()
		_pending[i] = []


func revive() -> void:
	wrecked = false
	wreck_shown = false
	health = max_health
	refresh_damage_state()
	global_transform = _spawn_transform
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	_last_velocity = Vector3.ZERO


func _next_command(seat: int = Seats.DRIVER) -> InputCommand:
	if seat < 0 or seat >= _pending.size():
		return InputCommand.new()
	var queue: Array = _pending[seat]
	if not queue.is_empty():
		_last_command[seat] = queue.pop_front()
	return _last_command[seat]


func _physics_process(delta: float) -> void:
	if not _server_authority:
		return

	_track_impact()
	var cmd := _next_command()
	var driving := owner_peer != 0
	var throttle := cmd.move.y if driving else 0.0
	var steer_input := cmd.move.x if driving else 0.0
	if driving:
		_aim = cmd.aim

	_drive(throttle, steer_input, driving and cmd.held(InputCommand.BRAKE), delta)
	_step_turret(delta, driving)
	_apply_turret()
	_step_gunner(delta)
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
	if _predict_gun():
		slew_gun(_gunner_view_aim, delta)
	_update_camera()
	_refresh_shell()


func _predict_gun() -> bool:
	return not _server_authority and _possessed and _local_seat == GUNNER_SEAT


func set_local_aim(aim: Vector3, seat: int = Seats.DRIVER) -> void:
	if seat != _local_seat:
		_local_seat = seat
		_activate_cameras()
	if seat == GUNNER_SEAT:
		_gunner_view_aim = aim
		return
	if _predict_turret:
		_aim = aim


func _refresh_shell() -> void:
	if _common == null:
		return
	var camera: Camera3D = _camera
	if _local_seat == GUNNER_SEAT:
		camera = _gunner_camera
	elif _first_person:
		camera = _cockpit_camera
	_common.set_shell_hidden(_possessed and camera != null
		and _common.encloses(camera.global_position))


func gunner_eye() -> Vector3:
	return _gunner_eye.global_position if _gunner_eye != null else global_position


func _update_gunner_camera() -> void:
	if _gunner_rig == null:
		return
	var flat := Vector3(_gunner_view_aim.x, 0.0, _gunner_view_aim.z)
	if flat.length_squared() < 0.000001:
		flat = Vector3.FORWARD
	var yaw := atan2(-flat.x, -flat.z)
	var pitch := asin(clampf(_gunner_view_aim.normalized().y, -1.0, 1.0))
	_gunner_rig.global_position = gunner_eye()
	_gunner_rig.global_rotation = Vector3(pitch, yaw, 0.0)


func _update_camera() -> void:
	if _local_seat == GUNNER_SEAT:
		_update_gunner_camera()
		return
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
		left = steer_input * pivot_force * mobility()
		right = -steer_input * pivot_force * mobility()
	else:
		var inside := steer_input * authority * travel
		left = -(throttle + inside) * max_engine_force * governor * mobility()
		right = -(throttle - inside) * max_engine_force * governor * mobility()

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
	var yaw_step := deg_to_rad(turret_yaw_speed_deg) * traverse_rate() * delta
	_turret_yaw_angle = wrapf(_turret_yaw_angle
		+ clampf(wrapf(want_yaw - _turret_yaw_angle, -PI, PI), -yaw_step, yaw_step), -PI, PI)

	var want_pitch := clampf(asin(clampf(_aim.normalized().y, -1.0, 1.0)),
		deg_to_rad(cannon_pitch_min_deg), deg_to_rad(cannon_pitch_max_deg))
	var pitch_step := deg_to_rad(cannon_pitch_speed_deg) * traverse_rate() * delta
	_cannon_pitch_angle += clampf(want_pitch - _cannon_pitch_angle, -pitch_step, pitch_step)


func _apply_turret() -> void:
	if _turret_yaw != null:
		_turret_yaw.rotation.y = _turret_yaw_angle
	if _cannon_pitch != null:
		_cannon_pitch.rotation.x = _cannon_pitch_angle
