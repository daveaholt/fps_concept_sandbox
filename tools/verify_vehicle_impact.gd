extends SceneTree

var _level: Node
var _t := 0
var _fail := 0
var _gs
var _tank
var _heli
var _phase := 0
var _drop_health := 0.0
var _soft_health := 0.0


func _ok(label: String, cond: bool, detail: String = "") -> void:
	if not cond:
		_fail += 1
	print("%s %s%s" % ["PASS" if cond else "FAIL", label, "  " + detail if detail != "" else ""])


func _initialize() -> void:
	_level = load("res://levels/sandbox/sandbox.tscn").instantiate()
	root.add_child(_level)


func _physics_process(_d: float) -> bool:
	_t += 1
	if _t == 20:
		_gs = root.get_node_or_null("/root/GameServer")
		_gs.is_active = true
		_tank = _level.get_node("Vehicles/Tank")
		_heli = _level.get_node("Vehicles/Helicopter")
		_check_thresholds()
		_check_rule()
		_begin_soft_landing()
		return false
	if _phase == 1 and _t > 20 and _t < 160:
		return false
	if _phase == 1 and _t == 160:
		_finish_soft_landing()
		_begin_hard_drop()
		return false
	if _phase == 2 and _t < 500:
		return false
	if _phase == 2:
		_finish_hard_drop()
		print("vehicle impact: %d failing" % _fail)
		quit(1 if _fail > 0 else 0)
		return true
	return false


func _check_thresholds() -> void:
	_ok("the helicopter tolerates a worse arrival than 06's clean-landing number",
		_heli.impact_tolerance > 4.0 and _heli.impact_tolerance < 9.0,
		"%.1f m/s vs 06's 4 m/s — a bad landing should not break the airframe"
		% _heli.impact_tolerance)
	var settle: float = sqrt(2.0 * 9.8 * 1.5)
	_ok("dropping the skids 1.5 m is survivable", settle < _heli.impact_tolerance,
		"%.1f m/s on arrival" % settle)
	_ok("a tracked vehicle tolerates more than an airframe",
		_tank.impact_tolerance > _heli.impact_tolerance,
		"tank %.1f vs heli %.1f" % [_tank.impact_tolerance, _heli.impact_tolerance])


func _check_rule() -> void:
	for pair in [[_tank, "tank"], [_heli, "heli"]]:
		var vehicle = pair[0]
		var name: String = pair[1]
		vehicle.revive()

		vehicle._last_velocity = Vector3.ZERO
		vehicle.linear_velocity = Vector3(0.0, -vehicle.impact_tolerance + 0.5, 0.0)
		vehicle._track_impact()
		_ok("%s shrugs off a touchdown under tolerance" % name,
			is_equal_approx(vehicle.health, vehicle.max_health),
			"hull %.0f" % vehicle.health)

		vehicle._last_velocity = Vector3.ZERO
		vehicle.linear_velocity = Vector3(0.0, -(vehicle.impact_tolerance + 6.0), 0.0)
		vehicle._track_impact()
		var taken: float = vehicle.max_health - vehicle.health
		_ok("%s is hurt by a hard arrival" % name, taken > 0.0,
			"%.0f damage from 6 m/s over tolerance" % taken)
		_ok("%s damage grows with the square of the excess" % name,
			is_equal_approx(taken, 36.0 * vehicle.impact_damage_scale),
			"%.0f vs expected %.0f — energy, not speed"
			% [taken, 36.0 * vehicle.impact_damage_scale])

		vehicle.revive()
		vehicle._last_velocity = Vector3.ZERO
		vehicle.linear_velocity = Vector3(0.0, -(vehicle.impact_tolerance + 2.0), 0.0)
		vehicle._track_impact()
		var gentle: float = vehicle.max_health - vehicle.health
		_ok("%s barely notices a small overshoot" % name,
			gentle < vehicle.max_health * 0.1,
			"%.0f damage from 2 m/s over — forgiving near the threshold" % gentle)

		vehicle.revive()
		vehicle._last_velocity = Vector3.ZERO
		vehicle.linear_velocity = Vector3(0.0, -60.0, 0.0)
		vehicle._track_impact()
		_ok("%s does not survive a terminal impact" % name, not vehicle.is_alive(),
			"hull %.0f" % vehicle.health)
		vehicle.revive()


func _begin_soft_landing() -> void:
	_phase = 1
	_heli.revive()
	_heli.global_position = _heli.global_position + Vector3(0.0, 1.2, 0.0)
	_heli.linear_velocity = Vector3.ZERO
	_soft_health = _heli.health


func _finish_soft_landing() -> void:
	_ok("a 1.2 m settle costs the helicopter nothing",
		is_equal_approx(_heli.health, _soft_health),
		"hull %.0f of %.0f" % [_heli.health, _heli.max_health])


func _begin_hard_drop() -> void:
	_phase = 2
	_heli.revive()
	_heli.global_position = _heli.global_position + Vector3(0.0, 40.0, 0.0)
	_heli.linear_velocity = Vector3.ZERO
	_drop_health = _heli.health


func _finish_hard_drop() -> void:
	_ok("a 40 m fall wrecks the helicopter through real physics",
		not _heli.is_alive(),
		"hull %.0f of %.0f — impact damage runs off the solver, not a special case"
		% [_heli.health, _heli.max_health])
	_heli.revive()
