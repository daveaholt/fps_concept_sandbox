extends SceneTree

var failures := 0
var _level: Node
var _t := 0
var _gs
var _bm
var _shooter
var _enemy
var _mate
var _enemy_hp := 0.0
var _mate_hp := 0.0

func _ok(c: bool, label: String, detail := "") -> void:
	if c: print("  ok   %s %s" % [label, detail])
	else:
		failures += 1
		print("  FAIL %s %s" % [label, detail])

func _initialize() -> void:
	_level = load("res://levels/sandbox/sandbox.tscn").instantiate()
	root.add_child(_level)
	print("[13 - a real shot: enemies take damage, squadmates do not]")

func _fire_at(target: Node) -> void:
	var origin: Vector3 = _shooter.muzzle_origin()
	var aim: Vector3 = ((target as Node3D).global_position + Vector3(0, 1.0, 0)
		- origin).normalized()
	_bm.spawn(origin, aim, 0, 11, 0.0, _gs.roster.team_of(11))

func _physics_process(_d: float) -> bool:
	_t += 1
	if _t == 20:
		_gs = root.get_node_or_null("/root/GameServer")
		_bm = _gs.ballistics
		_gs.is_active = true
		_bm.authoritative = true
		_gs.roster.clear()
		_gs.handle_slot_request(11, 0)
		_gs.handle_slot_request(22, 8)
		_gs.handle_slot_request(33, 1)
		_gs.phase = _gs.Phase.PLAYING
		_shooter = _gs._spawn_infantry(11, Vector3(0, 2, 0), Vector3(0, 0, -1))
		_enemy = _gs._spawn_infantry(22, Vector3(0, 2, -12), Vector3(0, 0, 1))
		_mate = _gs._spawn_infantry(33, Vector3(6, 2, -12), Vector3(0, 0, 1))
		_ok(_shooter.team_id() == 1 and _enemy.team_id() == 2 and _mate.team_id() == 1,
			"shooter and squadmate on team 1, enemy on team 2")
		return false
	if _t < 50:
		return false
	if _t == 50:
		_enemy_hp = _enemy.state.health
		_fire_at(_enemy)
		return false
	if _t == 110:
		_ok(_enemy.state.health < _enemy_hp,
			"a shot at an enemy takes health off them",
			"%.0f -> %.0f" % [_enemy_hp, _enemy.state.health])
		_mate_hp = _mate.state.health
		_fire_at(_mate)
		return false
	if _t == 170:
		_ok(is_equal_approx(_mate.state.health, _mate_hp),
			"the same shot at a squadmate does nothing",
			"%.0f -> %.0f" % [_mate_hp, _mate.state.health])
		_ok(_bm.authoritative,
			"ballistics is authoritative, which is what makes any of this run")
		print("\n%s  (%d failures)" % ["PASS" if failures == 0 else "FAIL", failures])
		quit(1 if failures > 0 else 0)
		return true
	return false
