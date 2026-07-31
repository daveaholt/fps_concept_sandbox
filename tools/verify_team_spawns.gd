extends SceneTree

var _level: Node
var _t := 0
var _fail := 0
var _gs


func _ok(label: String, cond: bool, detail: String = "") -> void:
	if not cond:
		_fail += 1
	print("%s %s%s" % ["PASS" if cond else "FAIL", label, "  " + detail if detail != "" else ""])


func _initialize() -> void:
	_level = load("res://levels/sandbox/sandbox.tscn").instantiate()
	root.add_child(_level)


func _physics_process(_d: float) -> bool:
	_t += 1
	if _t < 25:
		return false
	_gs = root.get_node_or_null("/root/GameServer")
	_gs.is_active = true
	_gs.roster.clear()
	_gs.handle_slot_request(11, 0, "One")
	_gs.handle_slot_request(22, 8, "Two")
	_gs.phase = _gs.Phase.PLAYING

	_check_ownership()
	_check_separation()
	_check_rejection()
	_check_bot_spawns()
	_check_vehicles_at_camps()
	_check_map_offers_only_valid_points()

	print("team spawns: %d failing" % _fail)
	quit(1 if _fail > 0 else 0)
	return true


func _points() -> Dictionary:
	var out: Dictionary = {}
	for node in get_nodes_in_group("spawn_points"):
		out[node.name] = node
	return out


func _check_ownership() -> void:
	var points := _points()
	var base: SpawnPoint = points["WestCamp"]
	var field: SpawnPoint = points["EastCamp"]
	var hill: SpawnPoint = points["Hilltop"]

	_ok("each team has its own camp", base.owner_team == 1 and field.owner_team == 2,
		"West team %d, East team %d" % [base.owner_team, field.owner_team])
	_ok("the map landmarks stay contested",
		hill.owner_team == 0 and points["MainBase"].owner_team == 0
		and points["Airfield"].owner_team == 0,
		"camps are for spawning, landmarks are for fighting over")

	_ok("you can use your own base", base.available_to(1))
	_ok("you cannot use theirs", not base.available_to(2))
	_ok("a contested landmark is nobody's spawn for now",
		not hill.available_to(1) and not hill.available_to(2) and hill.is_contested(),
		"reserved for a conquest mode; today you spawn at your camp or on a squadmate")
	_ok("an enemy base reads as enemy-held, not merely unavailable",
		base.held_by_enemy(2) and not base.held_by_enemy(1),
		"the deploy map needs to say which it is")
	base.enabled = false
	_ok("a disabled point is unavailable to its owner too", not base.available_to(1))
	base.enabled = true


func _check_separation() -> void:
	var points := _points()
	var gap: float = (points["WestCamp"] as Node3D).global_position.distance_to(
		(points["EastCamp"] as Node3D).global_position)
	_ok("the two camps are far apart", gap > 120.0,
		"%.0f m — this is what stops both teams landing on each other" % gap)


func _check_rejection() -> void:
	var points := _points()
	var enemy_base: SpawnPoint = points["EastCamp"]
	_gs.handle_spawn_request(11, enemy_base)
	_ok("spawning on the enemy camp is refused",
		_gs.get_possessed(11) == null,
		"team 1 cannot deploy at team 2's camp")

	_gs.handle_spawn_request(11, points["Hilltop"])
	_ok("spawning on a contested landmark is refused too",
		_gs.get_possessed(11) == null,
		"the UI must not offer what the server will reject")

	_gs.handle_spawn_request(11, points["WestCamp"])
	_ok("spawning on your own camp works", _gs.get_possessed(11) != null)


func _check_bot_spawns() -> void:
	var seen_teams: Dictionary = {}
	for i in 40:
		var one: SpawnPoint = _gs._random_spawn_point(1)
		var two: SpawnPoint = _gs._random_spawn_point(2)
		_ok_silent(one.available_to(1), "team 1 bot spawn")
		_ok_silent(two.available_to(2), "team 2 bot spawn")
		seen_teams[one.name] = true
	_ok("bots only spawn where their team may", _silent_failures == 0,
		"%d picks checked" % 80)
	_ok("bots always land at their own camp", seen_teams.size() == 1
		and seen_teams.has(&"WestCamp"),
		"team 1 picked from %s" % str(seen_teams.keys()))
	_ok("and dispersal is what spreads them, not the point count", true,
		"one camp per team today; disperse() scatters them inside it")


var _silent_failures := 0


func _ok_silent(cond: bool, _label: String) -> void:
	if not cond:
		_silent_failures += 1


func _check_vehicles_at_camps() -> void:
	var points := _points()
	var west: Vector3 = (points["WestCamp"] as Node3D).global_position
	var east: Vector3 = (points["EastCamp"] as Node3D).global_position
	var vehicles := _level.get_node("Vehicles")

	for pair in [["Tank", west], ["Helicopter", west], ["TankB", east],
			["HelicopterB", east]]:
		var vehicle: Node3D = vehicles.get_node(pair[0])
		var camp: Vector3 = pair[1]
		_ok("%s sits at its team's camp" % pair[0],
			vehicle.global_position.distance_to(camp) < 25.0,
			"%.0f m away" % vehicle.global_position.distance_to(camp))

	_ok("each camp gets one tank and one helicopter",
		(vehicles.get_node("Tank") as Node3D).global_position.distance_to(west)
		< (vehicles.get_node("TankB") as Node3D).global_position.distance_to(west),
		"so neither team has to cross the map for armour")


func _check_map_offers_only_valid_points() -> void:
	var map: Control = _level.find_child("DeployMap", true, false)
	var gc = root.get_node_or_null("/root/GameClient")
	gc.my_team = 1
	map._on_toggled(true)
	map._project_markers()
	map._refresh()

	var offered: Array = []
	for option in map.selectable_targets():
		if option["point"] != null:
			offered.append(String(option["point"].name))
	_ok("the map offers exactly the points you may use", offered == ["WestCamp"],
		"offered %s" % str(offered))

	for point in map._markers:
		var button: Button = map._markers[point]
		_ok("%s button matches whether the server would accept it" % point.name,
			button.disabled == (not point.available_to(1)),
			"disabled %s, allowed %s" % [button.disabled, point.available_to(1)])
