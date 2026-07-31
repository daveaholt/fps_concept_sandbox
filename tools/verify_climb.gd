extends SceneTree

var failures := 0
var _level: Node
var _tank: VehicleBody3D
var _t := 0
var _phase := 0
var _rest_y := 0.0

func _ok(c: bool, label: String, detail := "") -> void:
	if c: print("  ok   %s %s" % [label, detail])
	else:
		failures += 1
		print("  FAIL %s %s" % [label, detail])

func _initialize() -> void:
	_level = load("res://levels/sandbox/sandbox.tscn").instantiate()
	root.add_child(_level)
	_tank = _level.get_node("Vehicles/Tank")
	print("[05 - a tread should ride over a low obstacle]")
	print("   airfield slab at z=-40: ground ends x=26, slab top y=0.60, flat beyond")

func _drive(throttle: float) -> void:
	_tank.owner_peer = 1
	_tank.push_command(InputCommand.make(0, Vector2(0, throttle), 0, Vector3(1, 0, 0)))

func _physics_process(_d: float) -> bool:
	_t += 1
	match _phase:
		0:
			if _t < 20: return false
			_tank.freeze = true
			_tank.global_transform = Transform3D(
				Basis(Vector3.UP, deg_to_rad(-90)), Vector3(16, 1.2, -40))
			_tank.linear_velocity = Vector3.ZERO
			_tank.angular_velocity = Vector3.ZERO
			_tank.freeze = false
			_phase = 1
			_t = 0
		1:
			if _t < 150:
				_drive(0.0)
				return false
			_rest_y = _tank.global_position.y
			print("   resting on flat ground: hull y = %+.2f" % _rest_y)
			_ok(_rest_y > 0.30, "rests on its wheels, not its belly",
				"y=%+.2f (belly-down would be -0.21)" % _rest_y)
			_phase = 2
			_t = 0
		2:
			if _t < 260:
				_drive(1.0)
				if _t % 40 == 0:
					var q := _tank.global_position
					print("    t=%3d  x=%6.1f  y=%+6.2f  pitch=%+5.1f" % [_t, q.x, q.y,
						rad_to_deg(_tank.global_transform.basis.get_euler().x)])
				return false
			_phase = 3
			_t = 0
		3:
			if _t < 120:
				_drive(0.0)
				return false
			var p := _tank.global_position
			var pitch := rad_to_deg(_tank.global_transform.basis.get_euler().x)
			print("   settled at x=%.1f y=%+.2f pitch=%+.1f" % [p.x, p.y, pitch])
			_ok(p.x > 32.0, "climbed the 0.6 m step and kept going",
				"x=%.1f (stopping at the face would be x<23)" % p.x)
			_ok(absf(p.y - (0.6 + _rest_y)) < 0.25, "riding level on the slab deck",
				"y=%+.2f, expected ~%+.2f" % [p.y, 0.6 + _rest_y])
			_ok(absf(pitch) < 8.0, "sitting flat, not nosed up or launched",
				"pitch=%+.1f deg" % pitch)
			print("\n%s  (%d failures)" % ["PASS" if failures == 0 else "FAIL", failures])
			quit(1 if failures > 0 else 0)
			return true
	return false
