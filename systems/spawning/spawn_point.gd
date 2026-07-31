class_name SpawnPoint
extends Marker3D

@export var display_name: String = "Spawn"
@export var enabled: bool = true
@export var owner_team: int = 0


func available_to(team: int) -> bool:
	return enabled and owner_team != 0 and owner_team == team


func is_contested() -> bool:
	return owner_team == 0


func held_by_enemy(team: int) -> bool:
	return owner_team != 0 and owner_team != team


func _ready() -> void:
	add_to_group("spawn_points")
