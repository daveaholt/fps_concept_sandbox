class_name InfantryState
extends RefCounted

var position: Vector3 = Vector3.ZERO
var velocity: Vector3 = Vector3.ZERO
var on_floor: bool = false
var floor_normal: Vector3 = Vector3.UP

var health: float = 100.0

var weapon_index: int = 0
var switch_progress: float = 1.0
var fire_cooldown: float = 0.0

var prev_buttons: int = 0
var shots_fired: int = 0


func clone() -> InfantryState:
	var s := InfantryState.new()
	s.position = position
	s.velocity = velocity
	s.on_floor = on_floor
	s.floor_normal = floor_normal
	s.health = health
	s.weapon_index = weapon_index
	s.switch_progress = switch_progress
	s.fire_cooldown = fire_cooldown
	s.prev_buttons = prev_buttons
	s.shots_fired = shots_fired
	return s


func equals_within(other: InfantryState, epsilon: float) -> bool:
	return position.distance_to(other.position) <= epsilon \
		and velocity.distance_to(other.velocity) <= epsilon \
		and weapon_index == other.weapon_index \
		and absf(switch_progress - other.switch_progress) <= epsilon


func to_dict() -> Dictionary:
	return {
		"position": position, "velocity": velocity,
		"on_floor": on_floor, "floor_normal": floor_normal,
		"health": health, "weapon_index": weapon_index,
		"switch_progress": switch_progress, "fire_cooldown": fire_cooldown,
		"prev_buttons": prev_buttons, "shots_fired": shots_fired,
	}


static func from_dict(d: Dictionary) -> InfantryState:
	var s := InfantryState.new()
	s.position = d.get("position", Vector3.ZERO)
	s.velocity = d.get("velocity", Vector3.ZERO)
	s.on_floor = d.get("on_floor", false)
	s.floor_normal = d.get("floor_normal", Vector3.UP)
	s.health = d.get("health", 100.0)
	s.weapon_index = d.get("weapon_index", 0)
	s.switch_progress = d.get("switch_progress", 1.0)
	s.fire_cooldown = d.get("fire_cooldown", 0.0)
	s.prev_buttons = d.get("prev_buttons", 0)
	s.shots_fired = d.get("shots_fired", 0)
	return s
