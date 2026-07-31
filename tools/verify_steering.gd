extends SceneTree

var failures := 0
var _level: Node
var _tank: VehicleBody3D
var _t := 0
var _i := 0
var _results := {}

var _cases := [
	{"n": "forward + A", "throttle": 1.0, "steer": -1.0, "want": "left"},
	{"n": "forward + D", "throttle": 1.0, "steer": 1.0, "want": "right"},
	{"n": "reverse + A", "throttle": -1.0, "steer": -1.0, "want": "right"},
	{"n": "reverse + D", "throttle": -1.0, "steer": 1.0, "want": "left"},
	{"n": "pivot + A", "throttle": 0.0, "steer": -1.0, "want": "left"},
	{"n": "pivot + D", "throttle": 0.0, "steer": 1.0, "want": "right"},
]


func _ok(c: bool, label: String, detail := "") -> void:
	if c: print("  ok   %s %s" % [label, detail])
	else:
		failures += 1
		print("  FAIL %s %s" % [label, detail])


func _initialize() -> void:
	_level = load("res://levels/sandbox/sandbox.tscn").instantiate()
	root.add_child(_level)
	_tank = _level.get_node("Vehicles/Tank")
	print("[05 — steering follows track direction, as a tracked vehicle does]")


func _physics_process(_d: float) -> bool:
	_t += 1
	var span := 260
	var local := _t % span

	if local == 1:
		if _i >= _cases.size():
			print("\n%s  (%d failures)" % ["PASS" if failures == 0 else "FAIL", failures])
			quit(1 if failures > 0 else 0)
			return true
		_tank.freeze = true
		_tank.global_transform = Transform3D(Basis(), Vector3(0, 1.2, -350))
		_tank.linear_velocity = Vector3.ZERO
		_tank.angular_velocity = Vector3.ZERO
		_tank.freeze = false
	elif local > 60 and local < span:
		var c = _cases[_i]
		_tank.owner_peer = 1
		_tank.push_command(InputCommand.make(0, Vector2(c["steer"], c["throttle"]), 0, Vector3(0, 0, -1)))
	elif local == 0:
		var c = _cases[_i]
		var yaw: float = _tank.angular_velocity.y
		var nose := "left" if yaw > 0.05 else ("right" if yaw < -0.05 else "straight")
		var fwd := -_tank.global_transform.basis.z
		var along: float = _tank.linear_velocity.dot(fwd)
		var authority: float = lerpf(_tank.steer_authority_low, _tank.steer_authority_high,
			clampf(_tank.linear_velocity.length() / _tank.max_speed, 0.0, 1.0))
		_ok(nose == c["want"], "%s swings the nose %s" % [c["n"], c["want"]],
			"got %s (yaw %+.2f, along %+.1f m/s, authority %.2f, target %+.2f)"
			% [nose, yaw, along, authority, -c["steer"] * _tank.max_yaw_rate * authority * signf(along if absf(along) > 0.5 else 1.0)])
		_i += 1
	return false
