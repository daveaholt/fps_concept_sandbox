extends SceneTree

var failures := 0
var _level: Node
var _t := 0

func _ok(c: bool, label: String, detail := "") -> void:
	if c: print("  ok   %s %s" % [label, detail])
	else:
		failures += 1
		print("  FAIL %s %s" % [label, detail])

func _initialize() -> void:
	_level = load("res://levels/sandbox/sandbox.tscn").instantiate()
	root.add_child(_level)
	print("[13 - the deploy map must offer a squadmate who is crewing a vehicle]")

func _physics_process(_d: float) -> bool:
	_t += 1
	if _t < 30:
		return false
	var gs = root.get_node_or_null("/root/GameServer")
	var gc = root.get_node_or_null("/root/GameClient")
	var tank = _level.get_node("Vehicles/Tank")
	var map = _level.get_node("UI/DeployMap")

	gs.is_active = true
	gs.roster.clear()
	gs.handle_slot_request(1, 0)
	gs.handle_slot_request(22, 1)
	gs.phase = gs.Phase.PLAYING
	gc.roster.from_array(gs.roster.to_array())
	gc.phase = gs.Phase.PLAYING

	_ok(gc.squadmate_spawn_targets().is_empty(),
		"nothing offered while the squadmate has not deployed")

	var body = gs._spawn_infantry(22, tank.global_position + Vector3(3, 0, 0),
		Vector3(0, 0, -1))
	gs._bind(22, body)
	_ok(gc.squadmate_spawn_targets() == [22], "a squadmate on foot is offered")

	map._build_markers()
	_ok(map._mate_markers.has(22), "and gets a marker on the map")

	gs.handle_enter_request(22, tank)
	_ok(tank.seats.has_peer(22), "the squadmate boards the tank")
	_ok(gc.squadmate_entity(22) == tank,
		"the client resolves them to the tank once their body is gone")
	_ok(gc.squadmate_spawn_targets() == [22],
		"and they are STILL offered as a spawn target while crewing")

	var wire: Dictionary = tank.get_net_state()
	var mirror = load("res://entities/tank/tank.tscn").instantiate()
	_level.add_child(mirror)
	mirror.name = "MirrorTank"
	mirror._server_authority = false
	mirror.apply_replicated_state(wire)
	_ok(mirror.seats.has_peer(22),
		"a replicated copy rebuilds seat occupancy from the snapshot",
		"seat %d" % mirror.seats.seat_of(22))
	mirror.queue_free()

	map.visible = true
	map._process(0.016)
	_ok(map._mate_markers.has(22),
		"the map rebuilds its markers when the squadmate changes vehicle state")

	print("\n%s  (%d failures)" % ["PASS" if failures == 0 else "FAIL", failures])
	quit(1 if failures > 0 else 0)
	return true
