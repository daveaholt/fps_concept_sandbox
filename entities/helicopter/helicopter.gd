extends RigidBody3D

@export var max_lift: float = 29100.0
@export var collective_rate: float = 0.8
@export var spool_rate: float = 0.25
@export var cyclic_torque: float = 14000.0
@export var pedal_torque: float = 9000.0
@export var attitude_damping: float = 3.0
@export var auto_level: float = 0.35

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
var health: float = 350.0
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

var _pending: Array[InputCommand] = []
var _last_command: InputCommand = InputCommand.new()
var _aim: Vector3 = Vector3.FORWARD
var _possessed: bool = false
var _server_authority: bool = true
var _chase_active: bool = false
var _history := PositionHistory.new()


func _ready() -> void:
	_server_authority = multiplayer.multiplayer_peer == null or multiplayer.is_server()
	add_to_group("controllable")
	add_to_group("vehicle")
	add_to_group("helicopter")

	_common = get_node_or_null("VehicleCommon")
	_rotor = get_node_or_null("Rotor")
	_tail_rotor = get_node_or_null("TailRotor")
	_cockpit_camera = get_node_or_null("CockpitCam")
	_chase_rig = get_node_or_null("ChaseRig")
	_chase_spring = get_node_or_null("ChaseRig/SpringArm3D")
	_chase_camera = get_node_or_null("ChaseRig/SpringArm3D/Camera3D")

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


func get_display_name() -> String:
	return "Helicopter"


func possess() -> void:
	_possessed = true
	_chase_active = false
	_chase_yaw = global_transform.basis.get_euler().y
	_activate_camera()


func unpossess() -> void:
	_possessed = false
	if _cockpit_camera != null:
		_cockpit_camera.current = false
	if _chase_camera != null:
		_chase_camera.current = false
	_last_command = InputCommand.new()


func is_possessed() -> bool:
	return _possessed


func is_occupied() -> bool:
	return owner_peer != 0


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


func push_command(cmd: InputCommand) -> void:
	_pending.append(cmd)


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
		"v": linear_velocity,
		"o": owner_peer,
	}


func apply_replicated_state(net_state: Dictionary) -> void:
	if _server_authority:
		return
	var quat: Quaternion = net_state.get("q", Quaternion())
	global_transform = Transform3D(Basis(quat), net_state.get("p", global_position))
	rotor_rpm_norm = net_state.get("rr", rotor_rpm_norm)
	collective = net_state.get("co", collective)
	linear_velocity = net_state.get("v", linear_velocity)
	owner_peer = net_state.get("o", owner_peer)


func get_history() -> PositionHistory:
	return _history


func hit_half_extents() -> Vector3:
	return Vector3(1.1, 1.0, 3.4)


func hit_centre_y() -> float:
	return 1.3


func resolve_sector(_world_point: Vector3) -> Dictionary:
	return {"sector": "hull", "multiplier": 1.0}


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
	if driving:
		_aim = cmd.aim

	engine_on = driving
	_step_engine(delta)
	_step_collective(cmd, driving, delta)
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
	apply_central_force(frame.y * collective * max_lift * authority)

	var cyclic := cmd.move if driving else Vector2.ZERO
	if absf(cyclic.y) > 0.001:
		apply_torque(frame.x * -cyclic.y * cyclic_torque * authority)
	if absf(cyclic.x) > 0.001:
		apply_torque(frame.z * -cyclic.x * cyclic_torque * authority)

	var pedals := cmd.axes.x if driving else 0.0
	if absf(pedals) > 0.001:
		apply_torque(frame.y * -pedals * pedal_torque * authority)

	if cyclic.length() < 0.05 and auto_level > 0.0:
		_apply_auto_level(frame, authority)


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
	_update_cameras(delta)


func _spin_rotors(delta: float) -> void:
	if _rotor != null:
		_rotor.rotate_y(rotor_visual_speed * rotor_rpm_norm * delta)
	if _tail_rotor != null:
		_tail_rotor.rotate_x(tail_rotor_visual_speed * rotor_rpm_norm * delta)


func _activate_camera() -> void:
	if _cockpit_camera != null:
		_cockpit_camera.current = _possessed and not _chase_active
	if _chase_camera != null:
		_chase_camera.current = _possessed and _chase_active


func _update_cameras(delta: float) -> void:
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
