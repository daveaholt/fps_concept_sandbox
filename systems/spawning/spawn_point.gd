class_name SpawnPoint
extends Marker3D

@export var display_name: String = "Spawn"
@export var enabled: bool = true
@export var owner_team: int = 0


func available_to(team: int) -> bool:
	if not enabled:
		return false
	return owner_team == 0 or owner_team == team


func held_by_enemy(team: int) -> bool:
	return owner_team != 0 and owner_team != team


func _ready() -> void:
	add_to_group("spawn_points")
