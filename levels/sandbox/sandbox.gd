extends Node3D


func _ready() -> void:
	var spawn_points := get_node_or_null("SpawnPoints")
	var main_base: SpawnPoint = spawn_points.get_node_or_null("MainBase") if spawn_points != null else null
	var players := get_node("Players")

	GameServer.register_level(players, main_base)
	GameClient.register_level(players)
