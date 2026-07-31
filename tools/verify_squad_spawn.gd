extends SceneTree

var failures := 0
var _level: Node
var _t := 0
var _gs

func _ok(c: bool, label: String, detail := "") -> void:
	if c: print("  ok   %s %s" % [label, detail])
	else:
		failures += 1
		print("  FAIL %s %s" % [label, detail])

func _initialize() -> void:
	_level = load("res://levels/sandbox/sandbox.tscn").instantiate()
	root.add_child(_level)
	print("[13 - squad spawn and randomised dispersal]")

func _physics_process(_d: float) -> bool:
	_t += 1
	if _t < 30:
		return false
	_gs = root.get_node_or_null("/root/GameServer")
	_gs.is_active = true
	_gs.roster.clear()
	_gs.handle_slot_request(11, 0)
	_gs.handle_slot_request(22, 1)
	_gs.handle_slot_request(33, 4)
	_gs.handle_slot_request(44, 8)
	_gs.phase = _gs.Phase.PLAYING

	var mate = _gs.deploy(22)
	_ok(mate != null, "a squadmate is in the world")

	_ok(_gs.can_spawn_on(11, 22), "you may spawn on a living squadmate on foot")
	_ok(not _gs.can_spawn_on(11, 33),
		"but not on someone in another squad on your own team")
	_ok(not _gs.can_spawn_on(11, 44), "and not on an enemy")
	_ok(not _gs.can_spawn_on(11, 99), "nor on a peer who does not exist")
	_ok(not _gs.can_spawn_on(11, 11), "nor on yourself")

	var targets: Array = _gs.squadmate_spawn_targets(11)
	_ok(targets.size() == 1 and targets[0] == 22,
		"the offered list is exactly the eligible squadmates", str(targets))

	_gs.handle_squad_spawn_request(11, 22)
	var me = _gs._possession.get(11)
	_ok(me != null, "spawning on a squadmate puts you in the world")
	if me != null:
		var gap: float = (me as Node3D).global_position.distance_to(
			(mate as Node3D).global_position)
		_ok(gap > 0.05 and gap <= _gs.SPAWN_DISPERSAL_RADIUS + 1.0,
			"and near them, but not inside them", "%.2f m away" % gap)

	_gs.handle_squad_spawn_request(11, 22)
	_ok(_gs._possession.get(11) == me, "a second request while alive is refused")

	var tank = _level.get_node("Vehicles/Tank")
	_gs._release_peer(22)
	tank.take_seat(22)
	_gs._bind(22, tank)
	_ok(_gs.can_spawn_on(11, 22),
		"a squadmate crewing a vehicle with a free seat IS a spawn target")
	tank.take_seat(77)
	_ok(not _gs.can_spawn_on(11, 22),
		"but a full vehicle is not offered", "%d seats taken"
		% tank.seats.occupied_count())
	tank.leave_seat(77)
	tank.leave_seat(22)
	_gs._release_peer(22)

	_gs.roster.clear()
	_gs.handle_slot_request(11, 0)
	_gs.handle_slot_request(22, 1)
	_gs.phase = _gs.Phase.LOBBY
	_ok(_gs.squadmate_spawn_targets(11).is_empty(),
		"no squad spawns are offered outside a running match")
	_gs.phase = _gs.Phase.PLAYING

	var base: Vector3 = Vector3(0, 0, 58)
	var seen := {}
	var inside := 0
	for i in 24:
		var p: Vector3 = _gs.disperse(base)
		seen[Vector2(snappedf(p.x, 0.01), snappedf(p.z, 0.01))] = true
		if p.distance_to(base) <= _gs.SPAWN_DISPERSAL_RADIUS + 0.01:
			inside += 1
	_ok(seen.size() >= 20, "24 deploys at one point give distinct positions",
		"%d unique" % seen.size())
	_ok(inside == 24, "and all of them land inside the dispersal radius",
		"%d of 24" % inside)

	print("\n%s  (%d failures)" % ["PASS" if failures == 0 else "FAIL", failures])
	quit(1 if failures > 0 else 0)
	return true
