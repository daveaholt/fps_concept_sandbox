extends SceneTree

const PAD := Vector3(45, 0.65, -40)
const HILLTOP := Vector3(38, 6.9, 12)

var failures := 0
var _level: Node
var _heli: RigidBody3D
var _t := 0
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
	_heli = _level.get_node_or_null("Vehicles/Helicopter")
	print("[06 - helicopter]")

func _place(origin: Vector3) -> void:
	_heli.freeze = true
	_heli.global_transform = Transform3D(Basis(), origin)
	_heli.linear_velocity = Vector3.ZERO
	_heli.angular_velocity = Vector3.ZERO
	_heli.freeze = false

func _hover_trim() -> float:
	return _heli.mass * 9.8 / _heli.max_lift

func _hover_at(height: float) -> void:
	_place(PAD + Vector3.UP * height)
	_heli.owner_peer = 1
	_heli.engine_on = true
	_heli.rotor_rpm_norm = 1.0
	_heli.collective = _hover_trim()

func _shutdown() -> void:
	_heli.owner_peer = 0
	_heli.engine_on = false
	_heli.rotor_rpm_norm = 0.0
	_heli.collective = 0.0

func _fly(move: Vector2, axes: Vector2, buttons := 0) -> void:
	_heli.push_command(InputCommand.make(0, move, buttons, Vector3(0, 0, -1), axes))


func _board() -> void:
	_heli.owner_peer = 1


func _leave() -> void:
	_heli.owner_peer = 0

func _pitch_deg() -> float:
	return rad_to_deg(_heli.global_transform.basis.get_euler().x)

func _advance() -> void:
	_phase += 1
	_ticks = 0

func _physics_process(_d: float) -> bool:
	_t += 1
	_ticks += 1
	match _phase:
		0:
			if _t < 10: return false
			_ok(_heli != null, "helicopter is in the level")
			if _heli == null:
				quit(1)
				return true
			_ok(_heli.is_in_group("controllable") and _heli.is_in_group("vehicle")
				and _heli.is_in_group("helicopter"),
				"in the controllable, vehicle and helicopter groups")
			_ok(_heli.common() != null, "reuses the 04 VehicleCommon helper untouched")
			_ok(_heli.common().entry_zone() != null
				and _heli.common().entry_zone().is_in_group(VehicleCommon.ENTRY_GROUP),
				"EntryZone registered in the vehicle_entry group")
			_ok(_heli.get_node_or_null("CockpitCam") != null
				and _heli.get_node_or_null("ChaseRig/SpringArm3D/Camera3D") != null,
				"has both 04 camera rigs")
			var ratio: float = _heli.max_lift / (_heli.mass * 9.8)
			_ok(ratio > 1.15 and ratio < 1.9,
				"lift-to-weight gives climb and translation authority without being violent",
				"%.2f x m*g, hover trim %.0f%% collective" % [ratio, 100.0 / ratio])
			_ok(_heli.tilt_limit_deg > 20.0 and _heli.tilt_limit_deg < 80.0,
				"a tilt limit exists, so sustained full stick cannot invert it",
				"%.0f deg" % _heli.tilt_limit_deg)
			print("\n[06 - spool is a real event]")
			_place(PAD)
			_advance()
		1:
			if _ticks < 90:
				_fly(Vector2.ZERO, Vector2.ZERO)
				return false
			_record["rest_y"] = _heli.global_position.y
			_ok(_heli.rotor_fraction() < 0.01, "rotor is stopped before anyone gets in",
				"%.2f" % _heli.rotor_fraction())
			_ok(not _heli.can_hover(), "and cannot hover below the rpm floor")
			_advance()
		2:
			if _ticks == 1:
				_board()
				return false
			if _ticks < 40:
				_fly(Vector2.ZERO, Vector2(0, 1.0))
				return false
			_ok(_heli.engine_on, "entering the heli starts the engine, no toggle needed")
			_ok(_heli.rotor_fraction() > 0.05 and _heli.rotor_fraction() < 0.7,
				"rotor spools gradually, not instantly",
				"%.2f after 0.65 s" % _heli.rotor_fraction())
			_ok(_heli.global_position.y - float(_record["rest_y"]) < 0.5,
				"full collective below the rpm floor cannot lift it",
				"rose %.2f m" % (_heli.global_position.y - float(_record["rest_y"])))
			_advance()
		3:
			if _ticks < 300:
				_fly(Vector2.ZERO, Vector2(0, 1.0))
				return false
			_ok(_heli.rotor_fraction() > 0.95, "rotor reaches full rpm in about 4 s",
				"%.2f" % _heli.rotor_fraction())
			_ok(_heli.global_position.y - float(_record["rest_y"]) > 3.0,
				"and then it climbs",
				"+%.1f m" % (_heli.global_position.y - float(_record["rest_y"])))
			print("\n[06 - hover trim]")
			_hover_at(40.0)
			_advance()
		4:
			if _ticks < 30:
				_fly(Vector2.ZERO, Vector2.ZERO)
				return false
			_record["vy0"] = _heli.linear_velocity.y
			_advance()
		5:
			if _ticks < 60:
				_fly(Vector2.ZERO, Vector2.ZERO)
				return false
			var accel: float = _heli.linear_velocity.y - float(_record["vy0"])
			_ok(absf(accel) < 1.0, "at trim collective the heli very nearly hovers",
				"%.2f m/s^2 net" % accel)
			_ok(_heli.collective_fraction() > 0.05 and _heli.collective_fraction() < 0.95,
				"hover trim sits between the collective stops",
				"%.2f" % _heli.collective_fraction())
			_advance()
		6:
			if _ticks < 40:
				_fly(Vector2.ZERO, Vector2(0, 1.0))
				return false
			_ok(_heli.collective_fraction() > _hover_trim() + 0.15,
				"collective is rate-moved by the axes channel",
				"%.2f after 0.65 s of up" % _heli.collective_fraction())
			print("\n[06 - attitude is the only way to translate]")
			_hover_at(60.0)
			_advance()
		7:
			if _ticks < 60:
				_fly(Vector2(0, 1.0), Vector2.ZERO)
				return false
			_ok(_pitch_deg() < -5.0, "cyclic forward pitches the nose down",
				"%.1f deg" % _pitch_deg())
			_advance()
		8:
			if _ticks < 30:
				_fly(Vector2(0, 1.0), Vector2.ZERO)
				return false
			var along := _heli.linear_velocity.z
			_ok(along < -1.0, "and a nose-down disc translates the heli forward",
				"%.1f m/s along -Z" % along)
			_advance()
		9:
			if _ticks < 60:
				_fly(Vector2.ZERO, Vector2.ZERO)
				return false
			_record["settled"] = _pitch_deg()
			_advance()
		10:
			if _ticks < 300:
				_fly(Vector2.ZERO, Vector2.ZERO)
				return false
			var start: float = float(_record["settled"])
			_ok(absf(_pitch_deg()) < absf(start) * 0.7,
				"auto-level slowly rights the disc when cyclic is centered",
				"%.1f deg -> %.1f deg over 5 s" % [start, _pitch_deg()])
			print("\n[06 - pedals]")
			_hover_at(60.0)
			_advance()
		11:
			if _ticks < 60:
				_fly(Vector2.ZERO, Vector2(1.0, 0.0))
				return false
			var spin: float = _heli.angular_velocity.dot(_heli.global_transform.basis.y)
			_ok(spin < -0.05, "right pedal yaws the nose right", "%.2f rad/s" % spin)
			_hover_at(60.0)
			_advance()
		12:
			if _ticks < 60:
				_fly(Vector2.ZERO, Vector2(-1.0, 0.0))
				return false
			var spin: float = _heli.angular_velocity.dot(_heli.global_transform.basis.y)
			_ok(spin > 0.05, "left pedal yaws the nose left", "%.2f rad/s" % spin)
			print("\n[06 - exit rules]")
			_hover_at(30.0)
			_advance()
		13:
			if _ticks < 10:
				_fly(Vector2.ZERO, Vector2.ZERO)
				return false
			_ok(_heli.altitude_agl() > 3.0, "airborne well above the exit ceiling",
				"%.1f m AGL" % _heli.altitude_agl())
			_ok(not _heli.can_exit(), "mid-air exit is refused")
			_ok(_heli.exit_refusal() == "Land first", "and the refusal reads 'Land first'",
				_heli.exit_refusal())
			print("\n[06 - landing on skids]")
			_shutdown()
			_place(PAD + Vector3.UP * 0.75)
			_advance()
		14:
			if _ticks == 20:
				_record["impact"] = absf(_heli.linear_velocity.y)
			if _ticks < 180:
				_fly(Vector2.ZERO, Vector2.ZERO)
				return false
			_ok(float(_record["impact"]) < 4.5, "touches down at a survivable descent rate",
				"%.1f m/s" % float(_record["impact"]))
			_ok(_heli.altitude_agl() < 3.0 and _heli.linear_velocity.length() < 2.0,
				"settles on the pad", "%.2f m AGL, %.2f m/s" % [
					_heli.altitude_agl(), _heli.linear_velocity.length()])
			_ok(_heli.can_exit(), "landed exit is allowed")
			_ok(_heli.exit_refusal() == "", "and shows no refusal")
			var roll := rad_to_deg(_heli.global_transform.basis.get_euler().z)
			_ok(absf(roll) < 10.0 and absf(_pitch_deg()) < 10.0,
				"rests upright on its skids, no bounce-flip",
				"roll %.1f deg, pitch %.1f deg" % [roll, _pitch_deg()])
			print("\n[06 - land on the Hilltop and exit, the full-loop criterion]")
			_shutdown()
			_place(HILLTOP + Vector3.UP * 0.75)
			_advance()
		15:
			if _ticks < 180:
				_fly(Vector2.ZERO, Vector2.ZERO)
				return false
			_ok(_heli.altitude_agl() < 1.0,
				"AGL reads height above the surface it stands on, not the valley floor",
				"%.2f m AGL on a %.1f m plateau" % [_heli.altitude_agl(), HILLTOP.y - 0.65])
			_ok(_heli.can_exit(), "exit is allowed after landing on raised terrain")
			_ok(_heli.exit_refusal() == "", "and shows no refusal on the Hilltop")
			_advance()
		16:
			if _ticks == 1:
				_hover_at(80.0)
				return false
			if _ticks < 600:
				_fly(Vector2(0.0, 1.0), Vector2(0.0, 1.0))
				_record["held"] = maxf(float(_record.get("held", 0.0)),
					rad_to_deg(_heli.tilt_from_level()))
				return false
			_ok(float(_record["held"]) < 90.0,
				"holding full cyclic for 10 s never puts it past vertical",
				"peak tilt %.0f deg" % float(_record["held"]))
			print("\n%s  (%d failures)" % ["PASS" if failures == 0 else "FAIL", failures])
			quit(1 if failures > 0 else 0)
			return true
	return false
