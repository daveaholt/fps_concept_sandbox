extends CharacterBody3D

signal died(entity: Node)

@export var tuning: InfantryTuning
@export var eye_height: float = 1.6
@export var muzzle_flash_time: float = 0.045

const WORLD_VISIBLE_LAYER := 1
const OWN_BODY_LAYER := 2

var state: InfantryState = InfantryState.new()
var owner_peer: int = 0

var _head: Node3D
var _camera: Camera3D
var _interact_ray: RayCast3D
var _muzzle_flash: MeshInstance3D
var _visual_weapon: Node3D
var _visual_meshes: Array = []

var _pending: Array[InputCommand] = []
var _last_command: InputCommand = InputCommand.new()
var _aim: Vector3 = Vector3.FORWARD
var _shots_seen: int = 0
var _flash_timer: float = 0.0
var _possessed: bool = false
var _server_authority: bool = true


func _ready() -> void:
	_server_authority = multiplayer.multiplayer_peer == null or multiplayer.is_server()
	add_to_group("controllable")
	add_to_group("infantry")

	_head = get_node_or_null("Head")
	_camera = get_node_or_null("Head/Camera3D")
	_interact_ray = get_node_or_null("Head/InteractRay")
	_muzzle_flash = get_node_or_null("Head/Muzzle/Flash")
	_visual_weapon = get_node_or_null("Visual/WeaponProxy")

	var visual := get_node_or_null("Visual")
	if visual != null:
		_visual_meshes = visual.find_children("*", "VisualInstance3D", true, false)
	_set_visual_layer(WORLD_VISIBLE_LAYER)

	if _is_server():
		physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_ON
	else:
		physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF

	if tuning == null:
		tuning = InfantryTuning.new()
	tuning.gravity = ProjectSettings.get_setting("physics/3d/default_gravity", 9.8)

	state.position = global_position
	_shots_seen = state.shots_fired
	_set_flash_visible(false)
	if _camera != null:
		_camera.current = false
	reset_physics_interpolation()


func get_display_name() -> String:
	return "Infantry"


func possess() -> void:
	_possessed = true
	_set_visual_layer(OWN_BODY_LAYER)
	if _camera != null:
		_camera.current = true


func unpossess() -> void:
	_possessed = false
	_set_visual_layer(WORLD_VISIBLE_LAYER)
	if _camera != null:
		_camera.current = false


func _set_visual_layer(layer_bits: int) -> void:
	for node in _visual_meshes:
		node.layers = layer_bits


func is_possessed() -> bool:
	return _possessed


func push_command(cmd: InputCommand) -> void:
	_pending.append(cmd)


func get_interact_target() -> Node:
	if _interact_ray == null:
		return null
	_interact_ray.force_raycast_update()
	if not _interact_ray.is_colliding():
		return null
	return _interact_ray.get_collider()


func get_eye_transform() -> Transform3D:
	if _camera != null:
		return _camera.global_transform
	return global_transform


func get_active_weapon() -> WeaponDef:
	return tuning.weapon_at(state.weapon_index) if tuning != null else null


func get_net_state() -> Dictionary:
	return {
		"p": state.position,
		"a": _aim,
		"w": state.weapon_index,
		"h": state.health,
		"s": state.shots_fired,
	}


func apply_replicated_state(net_state: Dictionary) -> void:
	state.position = net_state.get("p", state.position)
	state.weapon_index = net_state.get("w", state.weapon_index)
	state.health = net_state.get("h", state.health)
	state.shots_fired = net_state.get("s", state.shots_fired)
	_aim = net_state.get("a", _aim)
	global_position = state.position


func apply_damage(amount: float) -> void:
	if not _is_server():
		return
	state.health = maxf(0.0, state.health - amount)
	print("[server] %s took %.0f damage, health %.0f" % [name, amount, state.health])
	if state.health <= 0.0:
		died.emit(self)


func _is_server() -> bool:
	return _server_authority


func _physics_process(delta: float) -> void:
	if not _is_server():
		return
	var cmd := _next_command()
	state = InfantrySim.simulate(state, cmd, tuning, get_world_3d().direct_space_state, delta)
	_aim = cmd.aim
	global_position = state.position
	velocity = state.velocity
	_apply_pose(delta)


func _process(delta: float) -> void:
	if not _is_server():
		_apply_pose(delta)


func _next_command() -> InputCommand:
	if not _pending.is_empty():
		_last_command = _pending.pop_front()
	return _last_command


func _apply_pose(delta: float) -> void:
	var forward := InfantrySim.flat_forward(_aim)
	var yaw := atan2(-forward.x, -forward.z)
	var pitch := asin(clampf(_aim.y, -1.0, 1.0))

	rotation.y = yaw
	if _head != null:
		_head.rotation.x = pitch
		_head.position.y = eye_height
	if _visual_weapon != null:
		_visual_weapon.rotation.x = pitch

	if state.shots_fired != _shots_seen:
		_shots_seen = state.shots_fired
		_flash_timer = muzzle_flash_time

	if _flash_timer > 0.0:
		_flash_timer -= delta
		_set_flash_visible(_flash_timer > 0.0)


func _set_flash_visible(visible_now: bool) -> void:
	if _muzzle_flash != null:
		_muzzle_flash.visible = visible_now
