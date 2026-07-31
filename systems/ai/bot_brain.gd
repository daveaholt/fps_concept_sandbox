class_name BotBrain
extends RefCounted

const ARRIVE_RADIUS := 1.6
const ENGAGE_RANGE := 55.0
const STANDOFF := 12.0
const AIM_TOLERANCE := deg_to_rad(6.0)
const TURN_RATE := deg_to_rad(260.0)


static func yaw_towards(from: Vector3, to: Vector3) -> float:
	var flat := Vector3(to.x - from.x, 0.0, to.z - from.z)
	if flat.length_squared() < 0.000001:
		return 0.0
	return atan2(-flat.x, -flat.z)


static func step_yaw(current: float, wanted: float, delta: float) -> float:
	var difference := wrapf(wanted - current, -PI, PI)
	var step := TURN_RATE * delta
	return wrapf(current + clampf(difference, -step, step), -PI, PI)


static func aim_from(yaw: float, pitch: float) -> Vector3:
	var cp := cos(pitch)
	return Vector3(-sin(yaw) * cp, sin(pitch), -cos(yaw) * cp)


static func lead_point(target: Vector3, target_velocity: Vector3, origin: Vector3,
		muzzle_speed: float) -> Vector3:
	if muzzle_speed <= 0.0:
		return target
	var flight := origin.distance_to(target) / muzzle_speed
	return target + target_velocity * flight


static func pitch_towards(from: Vector3, to: Vector3) -> float:
	var flat := Vector2(to.x - from.x, to.z - from.z).length()
	if flat < 0.001:
		return 0.0
	return atan2(to.y - from.y, flat)


static func move_towards(own_position: Vector3, own_yaw: float,
		destination: Vector3) -> Vector2:
	var flat := Vector3(destination.x - own_position.x, 0.0,
		destination.z - own_position.z)
	if flat.length() < ARRIVE_RADIUS:
		return Vector2.ZERO
	var direction := flat.normalized()
	var forward := Vector3(-sin(own_yaw), 0.0, -cos(own_yaw))
	var right := forward.cross(Vector3.UP).normalized()
	return Vector2(direction.dot(right), direction.dot(forward)).limit_length(1.0)


static func should_fire(own_aim: Vector3, own_position: Vector3, target: Vector3,
		has_sight: bool) -> bool:
	if not has_sight:
		return false
	var to_target := target - own_position
	if to_target.length() > ENGAGE_RANGE:
		return false
	if to_target.length_squared() < 0.0001:
		return false
	return own_aim.normalized().dot(to_target.normalized()) >= cos(AIM_TOLERANCE)


static func wants_to_close(distance: float) -> bool:
	return distance > STANDOFF
