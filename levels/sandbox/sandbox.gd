extends Node3D


func _ready() -> void:
	var spawn_points := get_node_or_null("SpawnPoints")
	var main_base: SpawnPoint = spawn_points.get_node_or_null("MainBase") if spawn_points != null else null
	var players := get_node("Players")
	var ballistics: BallisticsManager = get_node_or_null("Ballistics")

	GameServer.register_level(players, main_base, ballistics)
	for vehicle in get_node("Vehicles").get_children():
		GameServer.register_vehicle(vehicle)
	GameClient.register_level(players, ballistics)
	_bake_navigation()


func _bake_navigation() -> void:
	var region: NavigationRegion3D = get_node_or_null("Navigation")
	if region == null:
		return
	region.bake_navigation_mesh(false)
	GameServer.register_navigation(region)
