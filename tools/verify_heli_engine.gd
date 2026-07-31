extends SceneTree

const PAD := Vector3(45, 0.65, -40)

var failures := 0
var _level: Node
var _heli: RigidBody3D
var _t := 0
var _phase := 0
var _ticks := 0
var _rest_y := 0.0

func _ok(c: bool, label: String, detail := "") -> void:
	if c: print("  ok   %s %s" % [label, detail])
	else:
		failures += 1
		print("  FAIL %s %s" % [label, detail])

func _initialize() -> void:
	_level = load("res://levels/sandbox/sandbox.tscn").instantiate()
	root.add_child(_level)
	_heli = _level.get_node("Vehicles/Helicopter")
	print("[06 - the engine runs on server-side occupancy, never on possess()]")
	print("   possess() is client presentation; a remote pilot never calls it on this instance")

func _fly(axes: Vector2) -> void:
	_heli.push_command(InputCommand.make(0, Vector2.ZERO, 0, Vector3(0, 0, -1), axes))

func _advance() -> void:
	_phase += 1
	_ticks = 0

func _physics_process(_d: float) -> bool:
	_t += 1
	_ticks += 1
	match _phase:
		0:
			if _t < 10: return false
			_heli.freeze = true
			_heli.global_transform = Transform3D(Basis(), PAD)
			_heli.linear_velocity = Vector3.ZERO
			_heli.freeze = false
			_heli.owner_peer = 0
			_advance()
		1:
			if _ticks < 60:
				_fly(Vector2.ZERO)
				return false
			_rest_y = _heli.global_position.y
			_ok(not _heli.engine_on and _heli.rotor_fraction() < 0.01,
				"empty heli keeps its engine off", "rotor %.2f" % _heli.rotor_fraction())
			var expected: float = sqrt(_heli.mass * 9.8 / _heli.max_lift)
			_ok(absf(_heli.hover_rpm_floor() - expected) < 0.005,
				"hover floor tracks lift-to-weight instead of being a stored guess",
				"%.0f%% == sqrt(m*g / max_lift)" % (_heli.hover_rpm_floor() * 100.0))
			_heli.owner_peer = 2
			_advance()
		2:
			if _ticks < 30:
				_fly(Vector2(0, 1.0))
				return false
			_ok(_heli.engine_on,
				"binding a peer starts the engine with no possess() call",
				"rotor %.2f and climbing" % _heli.rotor_fraction())
			_ok(not _heli.is_possessed(),
				"and the server instance was never possessed", "is_possessed=%s"
				% str(_heli.is_possessed()))
			_advance()
		3:
			if _ticks < 330:
				_fly(Vector2(0, 1.0))
				return false
			_ok(_heli.rotor_fraction() > 0.95, "rotor reaches full rpm",
				"%.2f" % _heli.rotor_fraction())
			_ok(_heli.global_position.y - _rest_y > 3.0,
				"a remote pilot holding collective actually lifts off",
				"+%.1f m" % (_heli.global_position.y - _rest_y))
			_heli.owner_peer = 0
			_advance()
		4:
			if _ticks < 60:
				_fly(Vector2.ZERO)
				return false
			_ok(not _heli.engine_on, "leaving stops the engine")
			_ok(_heli.rotor_fraction() < 1.0, "and the rotor spools down",
				"%.2f" % _heli.rotor_fraction())
			print("\n%s  (%d failures)" % ["PASS" if failures == 0 else "FAIL", failures])
			quit(1 if failures > 0 else 0)
			return true
	return false
