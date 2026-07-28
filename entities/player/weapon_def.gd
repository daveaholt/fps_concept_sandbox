class_name WeaponDef
extends Resource

enum FireMode { FULL_AUTO, SEMI_AUTO }

@export var display_name: String = "Weapon"
@export var fire_mode: FireMode = FireMode.FULL_AUTO
@export var rpm: float = 600.0
@export var draw_time: float = 0.5
@export var ballistics_params: String = ""


func seconds_per_shot() -> float:
	return 60.0 / maxf(rpm, 1.0)
