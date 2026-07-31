class_name BotController
extends Node

const REPATH_SECONDS := 0.8
const TARGET_REFRESH_SECONDS := 0.5
const WORLD_MASK := 1
const MUZZLE_GUESS := 400.0
const PEER_BASE := -1000


static func is_bot(peer: int) -> bool:
	return peer <= PEER_BASE


static func next_peer(taken) -> int:
	var candidate := PEER_BASE
	while taken.has(candidate):
		candidate -= 1
	return candidate


var _state: Dictionary = {}


func forget(peer: int) -> void:
	_state.erase(peer)


func clear() -> void:
	_state.clear()


func tracked() -> int:
	return _state.size()


func command_for(peer: int, body: Node, tick: int, delta: float, targets: Array,
		space: PhysicsDirectSpaceState3D, map: RID) -> InputCommand:
	var mind: Dictionary = _state.get(peer, {})
	if mind.is_empty():
		mind = {"yaw": 0.0, "pitch": 0.0, "path": PackedVector3Array(),
			"step": 0, "repath": 0.0, "retarget": 0.0, "target": null}
		_state[peer] = mind

	var origin: Vector3 = (body as Node3D).global_position
	mind["retarget"] = float(mind["retarget"]) - delta
	if float(mind["retarget"]) <= 0.0:
		mind["retarget"] = TARGET_REFRESH_SECONDS
		mind["target"] = _pick_target(origin, targets)

	var target = mind["target"]
	var alive := target != null and is_instance_valid(target)
	var aim_point := origin + Vector3.FORWARD
	var sighted := false
	var destination := origin

	if alive:
		var seen: Vector3 = (target as Node3D).global_position + Vector3.UP * 1.2
		sighted = _has_sight(space, origin + Vector3.UP * 1.4, seen)
		aim_point = BotBrain.lead_point(seen, _velocity_of(target),
			origin + Vector3.UP * 1.4, MUZZLE_GUESS)
		destination = (target as Node3D).global_position

	mind["repath"] = float(mind["repath"]) - delta
	if float(mind["repath"]) <= 0.0 and map.is_valid():
		mind["repath"] = REPATH_SECONDS
		mind["path"] = NavigationServer3D.map_get_path(map, origin, destination, true)
		mind["step"] = 0

	var waypoint := _next_waypoint(mind, origin)
	var wanted_yaw: float = BotBrain.yaw_towards(origin + Vector3.UP * 1.4, aim_point) \
		if alive else BotBrain.yaw_towards(origin, waypoint)
	mind["yaw"] = BotBrain.step_yaw(float(mind["yaw"]), wanted_yaw, delta)
	mind["pitch"] = BotBrain.pitch_towards(origin + Vector3.UP * 1.4, aim_point) \
		if alive else 0.0

	var aim := BotBrain.aim_from(float(mind["yaw"]), float(mind["pitch"]))
	var move := Vector2.ZERO
	var distance: float = origin.distance_to(destination) if alive else 0.0
	if not alive or BotBrain.wants_to_close(distance):
		move = BotBrain.move_towards(origin, float(mind["yaw"]), waypoint)

	var buttons := 0
	if alive and BotBrain.should_fire(aim, origin + Vector3.UP * 1.4, aim_point, sighted):
		buttons |= InputCommand.FIRE
	if body.state.loaded(body.state.weapon_index) <= 0:
		buttons |= InputCommand.RELOAD

	return InputCommand.make(tick, move, buttons, aim)


func _next_waypoint(mind: Dictionary, origin: Vector3) -> Vector3:
	var path: PackedVector3Array = mind["path"]
	if path.is_empty():
		return origin
	var step: int = mind["step"]
	while step < path.size() - 1 and origin.distance_to(path[step]) < BotBrain.ARRIVE_RADIUS:
		step += 1
	mind["step"] = step
	return path[step]


func _pick_target(origin: Vector3, targets: Array):
	var best = null
	var best_distance := INF
	for candidate in targets:
		if candidate == null or not is_instance_valid(candidate):
			continue
		var distance: float = origin.distance_to((candidate as Node3D).global_position)
		if distance < best_distance:
			best_distance = distance
			best = candidate
	return best


func _velocity_of(target: Node) -> Vector3:
	if target.get("state") != null:
		return target.state.velocity
	if target.get("linear_velocity") != null:
		return target.linear_velocity
	return Vector3.ZERO


func _has_sight(space: PhysicsDirectSpaceState3D, from: Vector3, to: Vector3) -> bool:
	if space == null:
		return true
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.collision_mask = WORLD_MASK
	return space.intersect_ray(query).is_empty()
