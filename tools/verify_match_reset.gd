extends SceneTree

var _level: Node
var _t := 0
var _fail := 0
var _gs
var _tank
var _heli
var _home := {}


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
	_tank = _level.get_node("Vehicles/Tank")
	_heli = _level.get_node("Vehicles/Helicopter")
	_home["Tank"] = _tank.global_position
	_home["Helicopter"] = _heli.global_position

	_make_a_mess()
	_gs.phase = _gs.Phase.RESULT
	_gs._return_to_lobby()
	_check_reset()

	print("match reset: %d failing" % _fail)
	quit(1 if _fail > 0 else 0)
	return true


func _make_a_mess() -> void:
	_gs.is_active = true
	_gs.roster.clear()
	_gs.handle_slot_request(11, 0)
	_gs.phase = _gs.Phase.PLAYING

	_tank.take_seat(11)
	_gs._bind(11, _tank)
	_tank.global_position += Vector3(30.0, 0.0, 12.0)
	_tank.apply_damage(_tank.max_health * 0.7)
	_tank._turret_yaw_angle = 1.2
	_tank._gun_heat = 0.8

	_heli.global_position += Vector3(0.0, 40.0, 25.0)
	_heli.linear_velocity = Vector3(12.0, -3.0, 0.0)
	_heli.rotor_rpm_norm = 1.0
	_heli.collective = 0.9
	_heli.apply_damage(_heli.max_health)

	_ok("the tank is damaged and away from home before the reset",
		_tank.health < _tank.max_health
		and _tank.global_position.distance_to(_home["Tank"]) > 10.0)
	_ok("the helicopter is wrecked before the reset", not _heli.is_alive())
	_ok("a wreck is queued to respawn", _gs._wrecks.size() > 0)


func _check_reset() -> void:
	_ok("the match returned to the lobby", _gs.phase == _gs.Phase.LOBBY)

	for pair in [[_tank, "Tank"], [_heli, "Helicopter"]]:
		var vehicle = pair[0]
		var name: String = pair[1]
		_ok("%s is back at full hull" % name,
			is_equal_approx(vehicle.health, vehicle.max_health),
			"%.0f of %.0f" % [vehicle.health, vehicle.max_health])
		_ok("%s is back where it started" % name,
			vehicle.global_position.distance_to(_home[name]) < 1.0,
			"%.1f m from home" % vehicle.global_position.distance_to(_home[name]))
		_ok("%s is not wrecked" % name, not vehicle.wrecked and vehicle.is_alive())
		_ok("%s is visible again" % name, vehicle.visible)
		_ok("%s has stopped smoking" % name, not vehicle.common().smoking())
		_ok("%s is empty" % name, vehicle.seats.is_empty() and vehicle.owner_peer == 0)
		_ok("%s is unaligned again" % name, vehicle.team == Roster.UNALIGNED,
			"or it would still belong to last match's team")
		_ok("%s is at rest" % name, vehicle.linear_velocity.length() < 0.5,
			"%.1f m/s" % vehicle.linear_velocity.length())
		_ok("%s gun is cool" % name, is_zero_approx(vehicle.gun_heat()))
		_ok("%s reads as healthy" % name,
			vehicle.damage_state() == VehicleDamage.State.HEALTHY)

	_ok("the tank's turret is centred", is_zero_approx(_tank.turret_angles().x),
		"%.2f rad" % _tank.turret_angles().x)
	_ok("the helicopter's rotor has stopped",
		is_zero_approx(_heli.rotor_rpm_norm) and is_zero_approx(_heli.collective),
		"rotor %.2f, collective %.2f" % [_heli.rotor_rpm_norm, _heli.collective])
	_ok("the helicopter has its rockets back",
		_heli.rockets_left() == _heli.rocket_salvo)
	_ok("no wreck timers survive into the lobby", _gs._wrecks.is_empty(),
		"or a hull would respawn mid-lobby")
	_ok("no corpses survive into the lobby", _gs._corpses.is_empty())
