extends SceneTree

var failures := 0
var _warm := 0
var _level: Node

func _ok(c: bool, label: String, detail := "") -> void:
	if c: print("  ok   %s %s" % [label, detail])
	else:
		failures += 1
		print("  FAIL %s %s" % [label, detail])

func _initialize() -> void:
	_level = load("res://levels/sandbox/sandbox.tscn").instantiate()
	root.add_child(_level)

func _physics_process(_d: float) -> bool:
	_warm += 1
	if _warm < 5:
		return false

	print("[07 — deploy map scene]")
	var map: Node = _level.get_node_or_null("UI/DeployMap")
	_ok(map != null, "deploy map is on the UI layer")
	_ok(not map.visible, "starts hidden until toggled")
	var vp: SubViewport = map.get_node("ViewportBox/Viewport")
	_ok(not vp.own_world_3d, "SubViewport shares the main World3D")
	_ok(vp.render_target_update_mode == SubViewport.UPDATE_DISABLED,
		"viewport idles while the map is closed")
	var cam: Camera3D = vp.get_node("TopDownCamera")
	_ok(cam.projection == Camera3D.PROJECTION_ORTHOGONAL, "top-down camera is orthographic")
	_ok(absf(cam.rotation_degrees.x + 90.0) < 0.01, "camera looks straight down",
		"pitch %.1f" % cam.rotation_degrees.x)

	print("\n[07 — spawn points and marker projection]")
	var points := _level.get_tree().get_nodes_in_group("spawn_points")
	_ok(points.size() >= 3, "spawn points registered", "%d" % points.size())
	var neutral := 0
	var owned := {}
	for point in points:
		if point.owner_team == 0:
			neutral += 1
		else:
			owned[point.owner_team] = true
	_ok(neutral >= 3, "the map landmarks stay contested", "%d neutral" % neutral)
	_ok(owned.has(1) and owned.has(2), "and each team has a camp of its own",
		"teams with a camp: %s" % str(owned.keys()))
	for p in points:
		var projected := cam.unproject_position(p.global_position)
		var inside := projected.x >= 0.0 and projected.x <= float(vp.size.x) \
			and projected.y >= 0.0 and projected.y <= float(vp.size.y)
		_ok(inside, "%s projects inside the map view" % p.display_name,
			"at %.0f,%.0f of %dx%d" % [projected.x, projected.y, vp.size.x, vp.size.y])

	print("\n[gate — server rejects illegal spawn requests]")

	var server = load("res://autoload/game_server.gd").new()
	server.name = "GameServer"
	root.add_child(server)
	server.is_active = true
	server.register_level(_level.get_node("Players"), points[0], _level.get_node("Ballistics"))

	server.roster.clear()
	server.handle_slot_request(1, 0)
	server.handle_slot_request(2, 1)
	server.handle_slot_request(3, 2)
	var main_base: SpawnPoint = server.find_spawn_point("West Camp")
	_ok(main_base != null, "server can resolve a spawn point by name")

	server.handle_spawn_request(1, main_base)
	_ok(server.get_possessed(1) != null, "a legal spawn while undeployed is granted")

	var entity_before = server.get_possessed(1)
	server.handle_spawn_request(1, main_base)
	_ok(server.get_possessed(1) == entity_before,
		"a forged spawn-while-alive request is rejected, entity unchanged")

	server.handle_spawn_request(2, null)
	_ok(server.get_possessed(2) == null, "an unknown spawn point is rejected")

	var hilltop: SpawnPoint = server.find_spawn_point("West Camp")
	hilltop.enabled = false
	server.handle_spawn_request(3, hilltop)
	_ok(server.get_possessed(3) == null, "a disabled spawn point is rejected")
	hilltop.enabled = true

	print("\n[07 — spawn faces the marker yaw]")
	hilltop.rotation_degrees = Vector3(0, 90, 0)
	server._release_peer(1)
	server.handle_spawn_request(1, hilltop)
	var spawned = server.get_possessed(1)
	_ok(spawned != null, "deployed at the team camp")
	if spawned != null:
		var aim: Vector3 = spawned.get_aim()
		var want := -hilltop.global_transform.basis.z
		_ok(aim.normalized().dot(Vector3(want.x, 0, want.z).normalized()) > 0.99,
			"spawn aim matches the marker's yaw", "aim=%v want=%v" % [aim, want])

	print("\n%s  (%d failures)" % ["PASS" if failures == 0 else "FAIL", failures])
	quit(1 if failures > 0 else 0)
	return true
