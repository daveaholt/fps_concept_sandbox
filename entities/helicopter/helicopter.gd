extends RigidBody3D

signal fired(origin: Vector3, direction: Vector3, params_id: int)
signal gun_fired(origin: Vector3, direction: Vector3, params_id: int)
signal destroyed(vehicle: Node)

const SEAT_COUNT := 2
const GUNNER_SEAT := 1

@export var max_lift: float = 34000.0
@export var collective_rate: float = 1.9
@export var spool_rate: float = 0.25
@export var cyclic_torque: float = 9500.0
@export var pedal_torque: float = 13000.0
@export var attitude_damping: float = 3.0
@export var auto_level: float = 0.35
@export var tilt_limit_deg: float = 45.0
@export var tilt_limit_strength: float = 4.0

@export var rocket_params_id: int = 4
@export var rocket_interval: float = 0.35
@export var rocket_salvo: int = 4
@export var rocket_reload: float = 3.2
@export var gun_params_id: int = 3
@export var gun_rate_per_second: float = 18.0
@export var gun_slew_deg: float = 300.0
@export var gun_yaw_limit_deg: float = 120.0
@export var gun_pitch_min_deg: float = -75.0
@export var gun_pitch_max_deg: float = 15.0
@export var gun_heat_per_shot: float = 0.018
@export var gun_cool_rate: float = 0.45
@export var exit_max_speed: float = 2.0
@export var exit_max_altitude: float = 3.0
@export var ground_probe_distance: float = 250.0
@export var ground_probe_lift: float = 1.5

@export var rotor_visual_speed: float = 38.0
@export var tail_rotor_visual_speed: float = 64.0

@export var chase_spring_length: float = 10.0
@export var chase_pivot_height: float = 2.2
@export var chase_lag: float = 6.0
@export var chase_pitch_deg: float = -8.0

var owner_peer: int = 0
var team: int = Roster.UNALIGNED
@export var impact_tolerance: float = 6.0
@export var impact_damage_scale: float = 4.5
@export var wreck_blast_damage: float = 200.0
@export var explosive_vulnerability: float = 1.6
@export var max_health: float = 350.0
var health: float = 350.0
var wrecked: bool = false
var wreck_shown: bool = false
var _damage_state: int = VehicleDamage.State.HEALTHY
var _spawn_transform := Transform3D()
var _last_velocity := Vector3.ZERO
var _live_collision_layer: int = 4
var _entry_shape: CollisionShape3D
var engine_on: bool = false
var rotor_rpm_norm: float = 0.0
var collective: float = 0.0

var _common: VehicleCommon
var _rotor: Node3D
var _tail_rotor: Node3D
var _cockpit_camera: Camera3D
var _chase_rig: Node3D
var _chase_spring: SpringArm3D
var _chase_camera: Camera3D
var _chase_yaw: float = 0.0
var _gunner_rig: Node3D
var _gunner_camera: Camera3D
var _gunner_eye: Marker3D
var _gunner_view_aim: Vector3 = Vector3.FORWARD
var _local_seat: int = -1

var seats := Seats.new(SEAT_COUNT)
var _pending: Array = []
var _last_command: Array = []
var _aim: Vector3 = Vector3.FORWARD
var _possessed: bool = false
var _server_authority: bool = true
var _chase_active: bool = false
var _history := PositionHistory.new()
var _gun_yaw: Node3D
var _gun_pitch: Node3D
var _gun_muzzle: Marker3D
var _gun_yaw_angle: float = 0.0
var _gun_pitch_angle: float = 0.0
var _gun_aim: Vector3 = Vector3.FORWARD
var _gun_cooldown: float = 0.0
var _gun_heat: float = 0.0
var _rocket_cooldown: float = 0.0
var _rockets_left: int = 0
var _pods: Array[Marker3D] = []
var _pod_index: int = 0


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
	add_to_group("helicopter")

	_common = get_node_or_null("VehicleCommon")
	_entry_shape = get_node_or_null("VehicleCommon/EntryZone/Shape")
	_rotor = get_node_or_null("Rotor")
	_tail_rotor = get_node_or_null("TailRotor")
	_cockpit_camera = get_node_or_null("CockpitCam")
	_chase_rig = get_node_or_null("ChaseRig")
	_chase_spring = get_node_or_null("ChaseRig/SpringArm3D")
	_chase_camera = get_node_or_null("ChaseRig/SpringArm3D/Camera3D")
	_gunner_eye = get_node_or_null("GunnerEye")
	_gunner_rig = get_node_or_null("GunnerRig")
	_gunner_camera = get_node_or_null("GunnerRig/Camera3D")
	if _gunner_rig != null:
		_gunner_rig.top_level = true
	if _gunner_camera != null:
		_gunner_camera.current = false

	angular_damp = attitude_damping
	can_sleep = false
	if _chase_spring != null:
		_chase_spring.spring_length = chase_spring_length
	if _chase_rig != null:
		_chase_rig.top_level = true
	if _cockpit_camera != null:
		_cockpit_camera.current = false
	if _chase_camera != null:
		_chase_camera.current = false

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


func rockets_left() -> int:
	return _rockets_left


func reloading() -> bool:
	return _rockets_left <= 0


func _step_rockets(cmd: InputCommand, driving: bool, delta: float) -> void:
	_rocket_cooldown = maxf(0.0, _rocket_cooldown - delta)
	if _rockets_left <= 0:
		if _rocket_cooldown <= 0.0:
			_rockets_left = rocket_salvo
		return
	if not driving or not cmd.held(InputCommand.FIRE) or _rocket_cooldown > 0.0:
		return
	if _pods.is_empty():
		return
	var pod := _pods[_pod_index % _pods.size()]
	_pod_index += 1
	_rockets_left -= 1
	_rocket_cooldown = rocket_interval if _rockets_left > 0 else rocket_reload
	fired.emit(pod.global_position, -global_transform.basis.z, rocket_params_id)


func _init_gunner() -> void:
	_gun_yaw = get_node_or_null("GunYaw")
	_gun_pitch = get_node_or_null("GunYaw/GunPitch")
	_gun_muzzle = get_node_or_null("GunYaw/GunPitch/Muzzle")
	_pods = []
	for name in ["RocketPodL", "RocketPodR"]:
		var pod := get_node_or_null(name) as Marker3D
		if pod != null:
			_pods.append(pod)
	_rockets_left = rocket_salvo


func gunner_peer() -> int:
	return seats.occupant(GUNNER_SEAT)


func weapon_ray(seat: int) -> Array:
	if seat == GUNNER_SEAT:
		if _gun_muzzle == null:
			return []
		return [_gun_muzzle.global_position, -_gun_muzzle.global_transform.basis.z,
			gun_params_id]
	if _pods.is_empty():
		return []
	var origin := (_pods[0].global_position + _pods[_pods.size() - 1].global_position) * 0.5
	return [origin, -global_transform.basis.z, rocket_params_id]


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
	return "Helicopter"


func possess() -> void:
	_possessed = true
	_chase_active = false
	_chase_yaw = global_transform.basis.get_euler().y
	_activate_camera()


func unpossess() -> void:
	_possessed = false
	_local_seat = -1
	_activate_camera()
	for i in _last_command.size():
		_last_command[i] = InputCommand.new()


func is_possessed() -> bool:
	return _possessed


func is_occupied() -> bool:
	return not seats.is_empty()


func can_exit() -> bool:
	return linear_velocity.length() < exit_max_speed and altitude_agl() < exit_max_altitude


func exit_refusal() -> String:
	if can_exit():
		return ""
	return "Land first"


func toggle_camera() -> void:
	_chase_active = not _chase_active
	_activate_camera()


func using_chase_camera() -> bool:
	return _chase_active


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


func climb_rate() -> float:
	return linear_velocity.y


func rotor_fraction() -> float:
	return rotor_rpm_norm


func collective_fraction() -> float:
	return collective


func hover_rpm_floor() -> float:
	return sqrt(clampf(mass * 9.8 / maxf(max_lift, 0.001), 0.0, 1.0))


func can_hover() -> bool:
	return rotor_rpm_norm >= hover_rpm_floor()


func altitude_agl() -> float:
	var space := get_world_3d().direct_space_state
	if space == null:
		return ground_probe_distance
	var from := global_position
	var query := PhysicsRayQueryParameters3D.create(from + Vector3.UP * ground_probe_lift,
		from + Vector3.DOWN * ground_probe_distance)
	query.collision_mask = 1
	query.exclude = [get_rid()]
	var hit := space.intersect_ray(query)
	if hit.is_empty():
		return ground_probe_distance
	return maxf(from.y - float(hit["position"].y), 0.0)


func get_net_state() -> Dictionary:
	return {
		"p": global_position,
		"q": global_transform.basis.get_rotation_quaternion(),
		"rr": rotor_rpm_norm,
		"co": collective,
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
	rotor_rpm_norm = net_state.get("rr", rotor_rpm_norm)
	collective = net_state.get("co", collective)
	if not _predict_gun():
		_gun_yaw_angle = net_state.get("gy", _gun_yaw_angle)
		_gun_pitch_angle = net_state.get("gp", _gun_pitch_angle)
		_apply_gun()
	_gun_heat = net_state.get("gh", _gun_heat)
	linear_velocity = net_state.get("v", linear_velocity)
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


func get_history() -> PositionHistory:
	return _history


func hit_half_extents() -> Vector3:
	return Vector3(1.1, 1.0, 3.4)


func hit_centre_y() -> float:
	return 1.3


func resolve_sector(_world_point: Vector3,
		params: ProjectileParams = null) -> Dictionary:
	if params != null and params.explosive:
		return {"sector": "airframe", "multiplier": explosive_vulnerability}
	return {"sector": "hull", "multiplier": 1.0}


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
	rotor_rpm_norm = 0.0
	collective = 0.0
	_chase_active = false
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
	if driving:
		_aim = cmd.aim

	engine_on = driving
	_step_engine(delta)
	_step_collective(cmd, driving, delta)
	_step_rockets(cmd, driving, delta)
	_step_gunner(delta)
	_apply_rotor_forces(cmd, driving)
	_history.push(float(Time.get_ticks_msec()) * 0.001, global_position,
		-global_transform.basis.z)


func _step_engine(delta: float) -> void:
	var target := 1.0 if engine_on else 0.0
	rotor_rpm_norm = move_toward(rotor_rpm_norm, target, spool_rate * delta)


func _step_collective(cmd: InputCommand, driving: bool, delta: float) -> void:
	if not driving:
		return
	collective = clampf(collective + cmd.axes.y * collective_rate * delta, 0.0, 1.0)


func _apply_rotor_forces(cmd: InputCommand, driving: bool) -> void:
	var authority := rotor_rpm_norm * rotor_rpm_norm
	if authority <= 0.0001:
		return

	var frame := global_transform.basis
	apply_central_force(frame.y * collective * max_lift * authority * mobility())

	var cyclic := cmd.move if driving else Vector2.ZERO
	if absf(cyclic.y) > 0.001:
		apply_torque(frame.x * -cyclic.y * cyclic_torque * authority)
	if absf(cyclic.x) > 0.001:
		apply_torque(frame.z * -cyclic.x * cyclic_torque * authority)

	var pedals := cmd.axes.x if driving else 0.0
	if absf(pedals) > 0.001:
		apply_torque(frame.y * -pedals * pedal_torque * authority * mobility())

	if cyclic.length() < 0.05 and auto_level > 0.0:
		_apply_auto_level(frame, authority)
	_apply_tilt_limit(frame, authority)


func tilt_from_level() -> float:
	return global_transform.basis.y.angle_to(Vector3.UP)


func _apply_tilt_limit(frame: Basis, authority: float) -> void:
	var limit := deg_to_rad(tilt_limit_deg)
	var tilt := frame.y.angle_to(Vector3.UP)
	if tilt <= limit:
		return
	var axis := frame.y.cross(Vector3.UP)
	if axis.length_squared() < 0.000001:
		axis = frame.x
	var excess := tilt - limit
	apply_torque(axis.normalized() * excess * tilt_limit_strength * cyclic_torque * authority)


func _apply_auto_level(frame: Basis, authority: float) -> void:
	var up := frame.y
	var axis := up.cross(Vector3.UP)
	if axis.length_squared() < 0.000001:
		return
	var angle := up.angle_to(Vector3.UP)
	apply_torque(axis.normalized() * angle * auto_level * cyclic_torque * authority)


func _process(delta: float) -> void:
	_spin_rotors(delta)
	if not _possessed:
		return
	if _predict_gun():
		slew_gun(_gunner_view_aim, delta)
	_update_cameras(delta)
	_refresh_shell()


func _predict_gun() -> bool:
	return not _server_authority and _possessed and _local_seat == GUNNER_SEAT


func _spin_rotors(delta: float) -> void:
	if _rotor != null:
		_rotor.rotate_y(rotor_visual_speed * rotor_rpm_norm * delta)
	if _tail_rotor != null:
		_tail_rotor.rotate_x(tail_rotor_visual_speed * rotor_rpm_norm * delta)


func _activate_camera() -> void:
	var gunning := _possessed and _local_seat == GUNNER_SEAT
	if _cockpit_camera != null:
		_cockpit_camera.current = _possessed and not gunning and not _chase_active
	if _chase_camera != null:
		_chase_camera.current = _possessed and not gunning and _chase_active
	if _gunner_camera != null:
		_gunner_camera.current = gunning
	_refresh_shell()


func set_local_aim(aim: Vector3, seat: int = Seats.DRIVER) -> void:
	if seat != _local_seat:
		_local_seat = seat
		_activate_camera()
	if seat == GUNNER_SEAT:
		_gunner_view_aim = aim


func _refresh_shell() -> void:
	if _common == null:
		return
	var camera: Camera3D = _cockpit_camera
	if _local_seat == GUNNER_SEAT:
		camera = _gunner_camera
	elif _chase_active:
		camera = _chase_camera
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


func _update_cameras(delta: float) -> void:
	if _local_seat == GUNNER_SEAT:
		_update_gunner_camera()
		return

	if _cockpit_camera != null and not _chase_active:
		_cockpit_camera.rotation = Vector3.ZERO

	if _chase_rig != null and _chase_active:
		var hull_yaw := global_transform.basis.get_euler().y
		_chase_yaw = lerp_angle(_chase_yaw, hull_yaw, clampf(chase_lag * delta, 0.0, 1.0))
		_chase_rig.global_position = global_position + Vector3.UP * chase_pivot_height
		_chase_rig.global_rotation = Vector3(0.0, _chase_yaw, 0.0)
		if _chase_spring != null:
			_chase_spring.rotation = Vector3(deg_to_rad(chase_pitch_deg), 0.0, 0.0)
		if _chase_camera != null:
			_chase_camera.rotation = Vector3.ZERO
