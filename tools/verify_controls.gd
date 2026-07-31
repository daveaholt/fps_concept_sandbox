extends SceneTree

var _level: Node
var _t := 0
var _fail := 0
var _gs
var _tank
var _heli
var _shots := 0
var _rockets := 0


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
		_setup()
		return false
	if _t > 20 and _t < 100:
		var cmd := InputCommand.make(_t, Vector2.ZERO, InputCommand.FIRE, Vector3(1, 0, 0))
		_gs.submit_local_commands(22, [cmd.to_dict()])
		_gs.submit_local_commands(33, [cmd.to_dict()])
		return false
	if _t == 100:
		_check_fire()
		_check_hints()
		_check_rays()
		_check_guard()
		print("controls: %d failing" % _fail)
		quit(1 if _fail > 0 else 0)
		return true
	return false


func _setup() -> void:
	_gs = root.get_node_or_null("/root/GameServer")
	_tank = _level.get_node("Vehicles/Tank")
	_heli = _level.get_node("Vehicles/Helicopter")
	_gs.is_active = true
	_gs.roster.clear()
	_gs.handle_slot_request(11, 0)
	_gs.handle_slot_request(22, 1)
	_gs.handle_slot_request(33, 2)
	_gs.phase = _gs.Phase.PLAYING
	_tank.take_seat(11)
	_tank.take_seat(22)
	_heli.take_seat(33)
	_heli.take_seat(33, 1)
	_gs._bind(11, _tank)
	_gs._bind(22, _tank)
	_gs._bind(33, _heli)
	_tank.gun_fired.connect(func(_o, _dir, _p): _shots += 1)
	_heli.gun_fired.connect(func(_o, _dir, _p): _rockets += 1)


func _check_fire() -> void:
	_ok("tank gunner fires through the server input path", _shots > 0, "%d rounds" % _shots)
	_ok("heli gunner fires through the server input path", _rockets > 0,
		"%d rounds" % _rockets)


func _check_hints() -> void:
	InputHints.pad = true
	_ok("pad label for switch_seat is A", InputHints.label("switch_seat") == "A",
		InputHints.label("switch_seat"))
	_ok("pad label for exit_vehicle is B", InputHints.label("exit_vehicle") == "B",
		InputHints.label("exit_vehicle"))
	_ok("pad label for vehicle_fire is RB", InputHints.label("vehicle_fire") == "RB",
		InputHints.label("vehicle_fire"))
	_ok("pad label for fire is RT", InputHints.label("fire") == "RT", InputHints.label("fire"))
	_ok("pad label for zoom is LT", InputHints.label("zoom") == "LT", InputHints.label("zoom"))
	InputHints.pad = false
	_ok("key label for switch_seat is C", InputHints.label("switch_seat") == "C",
		InputHints.label("switch_seat"))
	_ok("key label for exit_vehicle is F", InputHints.label("exit_vehicle") == "F",
		InputHints.label("exit_vehicle"))
	_ok("key label for fire is LMB", InputHints.label("fire") == "LMB", InputHints.label("fire"))
	_ok("key label for zoom is RMB", InputHints.label("zoom") == "RMB", InputHints.label("zoom"))

	var pad_event := InputEventJoypadButton.new()
	pad_event.button_index = JOY_BUTTON_A
	pad_event.pressed = true
	InputHints.note(pad_event)
	_ok("a pad press flips the hints to pad", InputHints.pad)
	var key_event := InputEventKey.new()
	key_event.keycode = KEY_W
	InputHints.note(key_event)
	_ok("a key press flips the hints back to keyboard", not InputHints.pad)
	var drift := InputEventJoypadMotion.new()
	drift.axis = JOY_AXIS_LEFT_X
	drift.axis_value = 0.2
	InputHints.note(drift)
	_ok("stick drift below the deadzone does not flip the hints", not InputHints.pad)


func _check_rays() -> void:
	for pair in [[_tank, "tank"], [_heli, "heli"]]:
		var vehicle = pair[0]
		for seat in [0, 1]:
			var ray: Array = vehicle.weapon_ray(seat)
			_ok("%s seat %d has a weapon ray" % [pair[1], seat], ray.size() == 3)
			if ray.size() != 3:
				continue
			var dir: Vector3 = ray[1]
			_ok("%s seat %d ray is normalised" % [pair[1], seat],
				absf(dir.length() - 1.0) < 0.01, "len %.3f" % dir.length())
			var origin: Vector3 = ray[0]
			_ok("%s seat %d muzzle sits on the vehicle" % [pair[1], seat],
				origin.distance_to(vehicle.global_position) < 8.0,
				"%.1f m" % origin.distance_to(vehicle.global_position))
			_ok("%s seat %d ray carries its params id" % [pair[1], seat],
				ray.size() == 3 and (ray[2] as int) > 0, "id %d" % (ray[2] as int))
	_check_drop()


func _check_drop() -> void:
	var manager = _gs.ballistics
	if manager == null:
		_ok("ballistics manager reachable for reticle drop", false)
		return
	var rocket: ProjectileParams = manager.params_for(_heli.rocket_params_id)
	var mg: ProjectileParams = manager.params_for(_heli.gun_params_id)
	var range := 150.0
	var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity", 9.8)
	var rocket_drop := 0.5 * gravity * rocket.gravity_scale \
		* pow(range / rocket.muzzle_velocity, 2.0)
	var mg_drop := 0.5 * gravity * mg.gravity_scale * pow(range / mg.muzzle_velocity, 2.0)
	_ok("rocket drop at %.0f m is worth compensating" % range, rocket_drop > 1.0,
		"%.2f m" % rocket_drop)
	_ok("minigun drop at %.0f m stays small" % range, mg_drop < 0.5, "%.2f m" % mg_drop)


func _check_guard() -> void:
	_ok("a seated gunner may command the vehicle", _gs._may_command(_tank, 22))
	_ok("the driver may command the vehicle", _gs._may_command(_tank, 11))
	_ok("an outsider may not command the vehicle", not _gs._may_command(_tank, 99))
	var body := _level.get_node_or_null("Players")
	if body != null and body.get_child_count() > 0:
		var player = body.get_child(0)
		_ok("an infantry body still checks owner_peer",
			_gs._may_command(player, player.owner_peer)
			and not _gs._may_command(player, player.owner_peer + 7))
