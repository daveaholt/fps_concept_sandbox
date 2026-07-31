extends SceneTree

const TICK := 1.0 / 60.0

var failures := 0
var _level: Node
var _tank: VehicleBody3D
var _phase := 0
var _ticks := 0
var _record := {}


func _ok(c: bool, label: String, detail := "") -> void:
	if c: print("  ok   %s %s" % [label, detail])
	else:
		failures += 1
		print("  FAIL %s %s" % [label, detail])


func _initialize() -> void:
	_level = load("res://levels/sandbox/sandbox.tscn").instantiate()
	root.add_child(_level)
	_tank = _level.get_node("Vehicles/Tank")


func _place(origin: Vector3, yaw_deg: float = 0.0, pitch_deg: float = 0.0) -> void:
	_tank.freeze = true
	var basis := Basis(Vector3.UP, deg_to_rad(yaw_deg)) * Basis(Vector3.RIGHT, deg_to_rad(pitch_deg))
	_tank.global_transform = Transform3D(basis, origin)
	_tank.linear_velocity = Vector3.ZERO
	_tank.angular_velocity = Vector3.ZERO
	_tank.freeze = false
	_tank.reset_physics_interpolation()


func _drive(move: Vector2, aim := Vector3(0, 0, -1), buttons := 0) -> void:
	_tank.owner_peer = 1
	_tank.push_command(InputCommand.make(0, move, buttons, aim))


func _physics_process(_d: float) -> bool:
	_ticks += 1
	match _phase:
		0:
			if _ticks < 20:
				return false
			_static_checks()
			_place(Vector3(0, 1.5, 20))
			_advance()
		1:
			if _ticks < 90:
				_drive(Vector2.ZERO)
				return false
			_record["flat_rest_y"] = _tank.global_position.y
			_ok(absf(_tank.global_transform.basis.y.dot(Vector3.UP) - 1.0) < 0.05,
				"tank settles upright on flat ground",
				"up.y=%.3f" % _tank.global_transform.basis.y.dot(Vector3.UP))
			_advance()
		2:
			if _ticks < 240:
				_drive(Vector2(0, 1))
				return false
			var speed: float = _tank.linear_velocity.length()
			_ok(speed > 4.0, "accelerates under full throttle", "%.1f m/s" % speed)
			var forward := -_tank.global_transform.basis.z
			_ok(_tank.linear_velocity.normalized().dot(forward) > 0.9,
				"throttle drives the hull FORWARD, not in reverse",
				"vel.dot(forward)=%.2f" % _tank.linear_velocity.normalized().dot(forward))
			_ok(speed <= _tank.max_speed * 1.15, "governor holds it near max_speed",
				"%.1f vs max %.1f" % [speed, _tank.max_speed])
			print("\n[05 — neutral steer]")
			_place(Vector3(0, 1.5, 20))
			_advance()
		3:
			if _ticks < 180:
				_drive(Vector2(1, 0))
				return false
			var spin: float = absf(_tank.angular_velocity.y)
			var drift: float = Vector2(_tank.linear_velocity.x, _tank.linear_velocity.z).length()
			_ok(spin > 0.15, "neutral steer rotates the hull in place", "%.2f rad/s" % spin)
			_ok(drift < 3.0, "and barely translates while doing it", "%.2f m/s" % drift)
			print("\n[05 — 20 deg ramp]")
			_place(Vector3(38, 1.75, 33), 0.0, 20.0)
			_advance()
		4:
			if _ticks < 90:
				_drive(Vector2.ZERO)
				return false
			_record["ramp_start_y"] = _tank.global_position.y
			_advance()
		5:
			if _ticks < 300:
				_drive(Vector2(0, 1), Vector3(0, 0, -1))
				return false
			var climbed: float = _tank.global_position.y - float(_record["ramp_start_y"])
			_ok(climbed > 1.0, "climbs the 20 deg ramp from standstill", "+%.2f m" % climbed)
			print("\n[05 — idle brake on the ramp]")
			_place(Vector3(38, 2.85, 30), 0.0, 20.0)
			_advance()
		6:
			if _ticks < 120:
				_drive(Vector2.ZERO)
				return false
			_record["hold_start"] = _tank.global_position
			_advance()
		7:
			if _ticks < 240:
				_drive(Vector2.ZERO)
				return false
			var slid: float = _tank.global_position.distance_to(_record["hold_start"])
			_ok(slid < 1.5, "idle brake holds it on a 20 deg grade", "slid %.2f m in 2 s" % slid)
			print("\n[05 — 25 deg cross-slope]")
			_place(Vector3(38, 8.0, -22), 90.0)
			_advance()
		8:
			if _ticks < 300:
				_drive(Vector2.ZERO)
				return false
			var up: float = _tank.global_transform.basis.y.dot(Vector3.UP)
			_ok(up > 0.7, "does not flip on the 25 deg cross-slope", "up.y=%.3f" % up)
			print("
[05 — drives up the Hilltop access ramp]")
			_place(Vector3(-58, 1.5, 16), 0.0)
			_advance()
		9:
			if _ticks < 90:
				_drive(Vector2.ZERO)
				return false
			_record["hill_start"] = _tank.global_position
			_advance()
		10:
			if _ticks < 900:
				_drive(Vector2(0, 1), Vector3(0, 0, -1))
				return false
			_advance()
			_hilltop_result()
			_sector_checks()
			_cannon_checks()
			_possession_checks()
			print("\n%s  (%d failures)" % ["PASS" if failures == 0 else "FAIL", failures])
			quit(1 if failures > 0 else 0)
			return true
	return false


func _grounded() -> int:
	var n := 0
	for w in _tank.find_children("*", "VehicleWheel3D", true, false):
		if w.is_in_contact(): n += 1
	return n


func _hilltop_result() -> void:
	var start: Vector3 = _record["hill_start"]
	var climbed: float = _tank.global_position.y - start.y
	_ok(climbed > 10.0, "tank drives up the Hilltop ramp from the flat",
		"+%.1f m (started y=%.2f, now y=%.2f)" % [climbed, start.y, _tank.global_position.y])
	_ok(_tank.global_transform.basis.y.dot(Vector3.UP) > 0.7, "and stays upright doing it")


func _advance() -> void:
	_phase += 1
	_ticks = 0


func _static_checks() -> void:
	print("[04 — vehicle framework]")
	_ok(_tank != null, "tank is in the level")
	_ok(_tank.is_in_group("controllable") and _tank.is_in_group("vehicle") and _tank.is_in_group("tank"),
		"tank is in the controllable, vehicle and tank groups")
	var common: VehicleCommon = _tank.get_node("VehicleCommon")
	_ok(common != null, "VehicleCommon helper present")
	_ok(common.entry_zone() != null and common.entry_zone().is_in_group("vehicle_entry"),
		"EntryZone registered in the vehicle_entry group")
	_ok(common.get_node_or_null("ExitPoint") != null and common.get_node_or_null("ExitPointAlt") != null,
		"both exit points present")

	var wheels := _tank.find_children("*", "VehicleWheel3D", true, false)
	_ok(wheels.size() == 6, "six wheels", "%d" % wheels.size())
	var traction := 0
	var steering := 0
	for w in wheels:
		if w.use_as_traction: traction += 1
		if w.use_as_steering: steering += 1
	_ok(traction == 6, "all six are traction wheels", "%d" % traction)
	_ok(steering == 0, "none steer — turning is differential", "%d" % steering)
	_ok(_tank.get_node_or_null("TurretYaw/CannonPitch/Muzzle") != null, "turret hierarchy present")
	print("\n[05 — drive model]")


func _sector_checks() -> void:
	print("\n[05 / 11 — armour sectors]")
	_place(Vector3(0, 1.5, 20))
	var origin := _tank.global_position
	var cases := {
		"front": origin + Vector3(0, 1.0, -4.0),
		"rear": origin + Vector3(0, 1.0, 4.0),
		"side": origin + Vector3(4.0, _tank.deck_height - 0.2, 0),
		"top": origin + Vector3(0, _tank.deck_height + 1.5, 0),
	}
	var want := {"front": _tank.armour_front, "rear": _tank.armour_rear,
		"side": _tank.armour_side, "top": _tank.armour_top}
	_ok(_tank.resolve_sector(origin + Vector3(2.0, _tank.deck_height - 0.05, 0))["sector"] == "side",
		"a flank hit just under the deck line is side, not top")
	var hull_shape: CollisionShape3D = _tank.get_node("HullShape")
	var hull_top: float = hull_shape.position.y + (hull_shape.shape as BoxShape3D).size.y * 0.5
	_ok(_tank.deck_height <= hull_top and _tank.deck_height > hull_top - 0.35,
		"deck line sits just under the hull roof so the whole flank reads side",
		"deck %.2f vs roof %.2f" % [_tank.deck_height, hull_top])
	for sector in cases:
		var result: Dictionary = _tank.resolve_sector(cases[sector])
		_ok(result["sector"] == sector and absf(result["multiplier"] - want[sector]) < 0.001,
			"%s hit resolves correctly" % sector,
			"got %s x%.2f" % [result["sector"], result["multiplier"]])


func _possession_checks() -> void:
	print("\n[04 — enter / exit grants]")
	var server = load("res://autoload/game_server.gd").new()
	server.name = "GameServer"
	root.add_child(server)
	server.is_active = true
	var points := _level.get_tree().get_nodes_in_group("spawn_points")
	server.register_level(_level.get_node("Players"), points[0], _level.get_node("Ballistics"))
	server.register_vehicle(_tank)
	_place(Vector3(0, 1.5, 20))
	_tank.owner_peer = 0
	_tank.unpossess()

	server.roster.clear()
	server.handle_slot_request(1, 0)
	server.handle_spawn_request(1, server.find_spawn_point("West Camp"))
	var soldier = server.get_possessed(1)
	_ok(soldier != null, "peer deployed on foot")

	soldier.global_position = _tank.global_position + Vector3(40, 0, 0)
	soldier.state.position = soldier.global_position
	server.handle_enter_request(1, _tank)
	_ok(server.get_possessed(1) == soldier, "enter rejected from 40 m away")

	soldier.global_position = _tank.global_position + Vector3(2.5, 0, 0)
	soldier.state.position = soldier.global_position
	server.handle_enter_request(1, _tank)
	_ok(server.get_possessed(1) == _tank, "enter granted within range")
	_ok(_tank.owner_peer == 1, "tank records its occupant", "owner_peer=%d" % _tank.owner_peer)
	_ok(not is_instance_valid(soldier) or soldier.is_queued_for_deletion(),
		"infantry body despawned on entry")

	for i in range(5):
		server.handle_enter_request(1, _tank)
	_ok(_tank.owner_peer == 1 and server.get_possessed(1) == _tank,
		"enter spam cannot double-grant")

	server.handle_enter_request(2, _tank)
	_ok(_tank.owner_peer == 1, "a second peer cannot take an occupied tank")

	server.submit_local_commands(2, [InputCommand.make(1, Vector2(0, 1), 0, Vector3.FORWARD).to_dict()])
	_ok(_tank.owner_peer == 1, "forged input for an un-owned tank is dropped")

	server.handle_exit_request(1)
	var on_foot = server.get_possessed(1)
	_ok(on_foot != null and not on_foot.is_in_group("vehicle"), "exit returns the peer to a soldier")
	_ok(_tank.owner_peer == 0, "tank released on exit", "owner_peer=%d" % _tank.owner_peer)
	if on_foot != null:
		var gap: float = on_foot.global_position.distance_to(_tank.global_position)
		_ok(gap > 1.0 and gap < 6.0, "exits beside the hull", "%.1f m from centre" % gap)

	server.handle_exit_request(1)
	_ok(server.get_possessed(1) == on_foot, "exit spam while on foot is rejected")


func _cannon_checks() -> void:
	print("\n[05 — cannon]")
	var shell: ProjectileParams = load("res://assets/ballistics/tank_shell.tres")
	_ok(shell != null and shell.muzzle_velocity == 180.0, "shell muzzle velocity is 180 m/s")
	var heli = load("res://entities/helicopter/helicopter.tscn").instantiate()
	var tank = load("res://entities/tank/tank.tscn").instantiate()
	_ok(shell.energy_damage(0.0) * heli.explosive_vulnerability >= heli.max_health,
		"a shell one-shots a helicopter at any range")
	_ok(shell.energy_damage(shell.muzzle_velocity) * tank.armour_front < tank.max_health,
		"a shell does not one-shot a tank frontally")
	heli.free()
	tank.free()
	_ok(shell.splash_radius == 4.0 and shell.splash_damage > 0.0, "4 m splash radius",
		"%.0f dmg" % shell.splash_damage)
	_ok(_tank.reload_fraction() >= 0.0, "reload fraction exposed for the HUD")
	_ok(_tank.get_node_or_null("SeatCameraRig/SpringArm3D/Camera3D") != null, "chase camera rig present")
	var arm: SpringArm3D = _tank.get_node("SeatCameraRig/SpringArm3D")
	_ok(absf(arm.spring_length - 8.0) < 0.01, "spring length 8 m", "%.1f" % arm.spring_length)