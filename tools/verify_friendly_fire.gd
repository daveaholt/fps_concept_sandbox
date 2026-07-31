extends SceneTree

var failures := 0
var _level: Node
var _t := 0
var _gs
var _bm

func _ok(c: bool, label: String, detail := "") -> void:
	if c: print("  ok   %s %s" % [label, detail])
	else:
		failures += 1
		print("  FAIL %s %s" % [label, detail])

func _initialize() -> void:
	_level = load("res://levels/sandbox/sandbox.tscn").instantiate()
	root.add_child(_level)
	print("[13 - friendly fire is off; unaligned targets stay damageable]")

func _physics_process(_d: float) -> bool:
	_t += 1
	if _t < 30:
		return false
	_gs = root.get_node_or_null("/root/GameServer")
	_bm = _gs.ballistics

	_ok(not _gs.blocks_damage(1, 2), "team 1 may damage team 2")
	_ok(_gs.blocks_damage(1, 1), "team 1 may not damage team 1")
	_ok(_gs.blocks_damage(2, 2), "team 2 may not damage team 2")
	_ok(not _gs.blocks_damage(Roster.UNALIGNED, 1),
		"an unaligned shooter may damage anyone")
	_ok(not _gs.blocks_damage(1, Roster.UNALIGNED),
		"anyone may damage an unaligned target, so the firing range still works")
	_ok(not _gs.blocks_damage(Roster.UNALIGNED, Roster.UNALIGNED),
		"two unaligned entities are not treated as teammates")

	_gs.roster.clear()
	_gs.roster.assign(11, 0)
	_gs.roster.assign(22, 1)
	_gs.roster.assign(33, 8)

	var mate = _gs._spawn_infantry(22, Vector3(20, 2, 20), Vector3(0, 0, -1))
	var enemy = _gs._spawn_infantry(33, Vector3(24, 2, 20), Vector3(0, 0, -1))
	mate.team = _gs.roster.team_of(22)
	enemy.team = _gs.roster.team_of(33)
	_ok(mate.team_id() == 1 and enemy.team_id() == 2,
		"squadmate is team 1, enemy is team 2",
		"%d vs %d" % [mate.team_id(), enemy.team_id()])

	var dummy = _level.get_node_or_null("FiringRange/TargetDummy")
	_ok(dummy != null, "found the range dummy")
	_ok(dummy != null and dummy.team_id() == Roster.UNALIGNED,
		"range dummy is unaligned so the firing range keeps working")
	_ok(dummy != null and _bm._may_damage({"team": 1}, dummy),
		"and a team-1 shooter can still hit it")

	var mate_hp: float = mate.state.health
	var enemy_hp: float = enemy.state.health

	var shooter_team: int = _gs.roster.team_of(11)
	var friendly := {"team": shooter_team}
	var hostile := {"team": shooter_team}
	_ok(not _bm._may_damage(friendly, mate), "a shot from peer 11 cannot hurt its squadmate")
	_ok(_bm._may_damage(hostile, enemy), "the same shot can hurt the enemy")

	var tank = _level.get_node("Vehicles/Tank")
	_ok(tank.team_id() == Roster.UNALIGNED, "an empty tank is unaligned")
	_ok(_bm._may_damage(friendly, tank), "and can be shot by anyone")

	_gs.is_active = true
	var driver = _gs._spawn_infantry(22, tank.global_position + Vector3(2, 0, 0),
		Vector3(0, 0, -1))
	_gs._bind(22, driver)
	_gs.handle_enter_request(22, tank)
	_ok(tank.owner_peer == 22, "squadmate entered the tank through the real enter path")
	_ok(tank.team_id() == 1, "the server stamped the driver's team onto the vehicle",
		"team %d" % tank.team_id())
	_ok(not _bm._may_damage(friendly, tank), "so it is protected from friendly fire")
	_ok(_bm._may_damage({"team": 2}, tank), "and is still a target for the enemy")

	_gs.handle_exit_request(22)
	_ok(tank.owner_peer == 0 and tank.team_id() == Roster.UNALIGNED,
		"leaving the tank returns it to unaligned")
	_ok(_bm._may_damage(friendly, tank), "an abandoned tank is a target for both sides")

	var exited = _gs._spawn_infantry(22, Vector3(30, 2, 30), Vector3(0, 0, -1))
	_ok(exited.team_id() == 1,
		"infantry spawned by any path carries its team, including on vehicle exit",
		"team %d" % exited.team_id())
	_ok(not _bm._may_damage(friendly, exited),
		"so a soldier who just left a tank is still protected from squadmates")

	_ok(is_equal_approx(mate.state.health, mate_hp)
		and is_equal_approx(enemy.state.health, enemy_hp),
		"no damage was actually applied by the checks themselves")

	print("\n%s  (%d failures)" % ["PASS" if failures == 0 else "FAIL", failures])
	quit(1 if failures > 0 else 0)
	return true
