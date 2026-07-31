extends SceneTree

var failures := 0
var _level: Node
var _t := 0
var _gs
var _heli
var _tank
var _shots := 0

func _ok(c: bool, label: String, detail := "") -> void:
	if c: print("  ok   %s %s" % [label, detail])
	else:
		failures += 1
		print("  FAIL %s %s" % [label, detail])

func _initialize() -> void:
	_level = load("res://levels/sandbox/sandbox.tscn").instantiate()
	root.add_child(_level)
	print("[04/05/06 - pilot rockets, gunner minigun]")

func _fire(vehicle, seat: int, aim: Vector3) -> void:
	vehicle.push_command(InputCommand.make(0, Vector2.ZERO, InputCommand.FIRE, aim), seat)

func _physics_process(delta: float) -> bool:
	_t += 1
	if _t < 30:
		return false
	if _t == 30:
		_gs = root.get_node_or_null("/root/GameServer")
		_heli = _level.get_node("Vehicles/Helicopter")
		_tank = _level.get_node("Vehicles/Tank")
		_gs.is_active = true
		_gs.roster.clear()
		_gs.handle_slot_request(11, 0)
		_gs.handle_slot_request(22, 1)
		_gs.phase = _gs.Phase.PLAYING

		var bm = _gs.ballistics
		_ok(bm.params_for(3).display_name == "Minigun round", "minigun round registered",
			bm.params_for(3).display_name)
		_ok(bm.params_for(4).display_name == "Rocket", "rocket registered",
			bm.params_for(4).display_name)
		_ok(bm.params_for(4).splash_radius > 0.0, "rockets carry splash",
			"%.1f m" % bm.params_for(4).splash_radius)
		_ok(bm.params_for(3).splash_radius == 0.0, "minigun rounds do not")

		_ok(_heli.get_node_or_null("GunYaw/GunPitch/Muzzle") != null,
			"helicopter has a chin gun muzzle")
		_ok(_heli.get_node_or_null("RocketPodL") != null
			and _heli.get_node_or_null("RocketPodR") != null,
			"and two rocket pods")
		_ok(_tank.get_node_or_null("GunYaw/GunPitch/Muzzle") != null,
			"tank has a machine gun muzzle")

		_heli.take_seat(11)
		_heli.take_seat(22)
		_heli.fired.connect(func(_o, _d, _p): _shots += 1)
		_heli.gun_fired.connect(func(_o, _d, _p): _shots += 1000)
		return false

	if _t < 60:
		_fire(_heli, 0, Vector3(0, 0, -1))
		return false
	if _t == 60:
		_ok(_shots % 1000 > 0, "the pilot firing launches rockets",
			"%d away" % (_shots % 1000))
		_ok(_shots % 1000 <= _heli.rocket_salvo,
			"no more than a salvo before reloading",
			"%d of %d" % [_shots % 1000, _heli.rocket_salvo])
		_ok(_shots < 1000, "and the pilot does not fire the gunner's minigun")
		_shots = 0
		return false

	if _t < 100:
		_heli.push_command(InputCommand.make(0, Vector2.ZERO, 0, Vector3(0, 0, -1)), 0)
		_fire(_heli, 1, Vector3(1, 0, 0))
		return false
	if _t == 100:
		_ok(_shots >= 1000, "the gunner firing runs the minigun", "%d rounds" % (_shots / 1000))
		_ok(_shots % 1000 == 0,
			"and does not launch the pilot's rockets while the pilot holds nothing")
		_ok(_heli.gun_angles().x != 0.0,
			"the turret slews toward the gunner's own aim, not the pilot's",
			"%.0f deg" % rad_to_deg(_heli.gun_angles().x))
		_ok(_heli.gun_heat() > 0.0, "sustained fire builds heat",
			"%.2f" % _heli.gun_heat())
		return false

	if _t == 101:
		_heli.leave_seat(22)
		_shots = 0
		return false
	if _t < 130:
		_heli.push_command(InputCommand.make(0, Vector2.ZERO, 0, Vector3(0, 0, -1)), 0)
		_fire(_heli, 1, Vector3(1, 0, 0))
		return false

	_ok(_shots == 0, "an empty gunner seat cannot fire")
	_ok(_heli.gunner_peer() == 0, "and reports no gunner")

	print("\n%s  (%d failures)" % ["PASS" if failures == 0 else "FAIL", failures])
	quit(1 if failures > 0 else 0)
	return true
