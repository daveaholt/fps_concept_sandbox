class_name ProjectileParams
extends Resource

@export var display_name: String = "Round"
@export var muzzle_velocity: float = 400.0
@export var drag_k: float = 0.006
@export var gravity_scale: float = 1.0
@export var base_damage: float = 25.0
@export var max_lifetime: float = 4.0
@export var damage_floor: float = 0.3
@export var splash_radius: float = 0.0
@export var splash_damage: float = 0.0
@export var tracer_length: float = 6.0
@export var tracer_colour: Color = Color(1.0, 0.85, 0.4)


func energy_damage(speed: float) -> float:
	var ratio := (speed * speed) / maxf(muzzle_velocity * muzzle_velocity, 0.001)
	return base_damage * maxf(ratio, damage_floor)
