class_name SpawnPoint
extends Marker3D

@export var display_name: String = "Spawn"
@export var enabled: bool = true


func _ready() -> void:
	add_to_group("spawn_points")
