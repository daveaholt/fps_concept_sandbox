extends Node3D

const HOST_PEER := 1


func _ready() -> void:
	var spawn_points := get_node_or_null("SpawnPoints")
	var main_base: SpawnPoint = spawn_points.get_node_or_null("MainBase") if spawn_points != null else null
	GameServer.register_level(get_node("Players"), main_base)

	if GameServer.is_active and GameClient.is_active:
		call_deferred("_deploy_host")


func _deploy_host() -> void:
	GameServer.spawn_infantry(HOST_PEER, null)
