class_name InfantryTuning
extends Resource

@export var walk_speed: float = 5.0
@export var sprint_speed: float = 8.5
@export var accel: float = 60.0
@export var air_accel: float = 10.0
@export var jump_velocity: float = 4.8
@export var gravity: float = 9.8
@export var gravity_scale: float = 1.0
@export var floor_max_angle_deg: float = 45.0
@export var sprint_forward_dot: float = 0.5

@export var capsule_radius: float = 0.4
@export var capsule_height: float = 1.8
@export var collision_mask: int = 1
@export var skin_width: float = 0.02
@export var max_slides: int = 4
@export var floor_snap_distance: float = 0.3
@export var floor_probe_lift: float = 0.1
@export var penetration_inset: float = 0.03
@export var depenetration_step: float = 0.12
@export var max_depenetration_steps: int = 8

@export var weapons: Array[WeaponDef] = []


func gravity_accel() -> float:
	return gravity * gravity_scale


func weapon_at(index: int) -> WeaponDef:
	if weapons.is_empty():
		return null
	return weapons[clampi(index, 0, weapons.size() - 1)]
