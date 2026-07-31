extends SceneTree

var failures := 0
var _level: Node
var _tank: VehicleBody3D
var _t := 0
var _i := 0
var _cases := [
	{"n": "back-left  -> fwd-right", "a": Vector2(-1, -1), "b": Vector2(1, 1)},
	{"n": "back-right -> fwd-left ", "a": Vector2(1, -1), "b": Vector2(-1, 1)},
	{"n": "fwd-left   -> back-right", "a": Vector2(-1, 1), "b": Vector2(1, -1)},
	{"n": "fwd-right  -> back-left ", "a": Vector2(1, 1), "b": Vector2(-1, -1)},
]
var _pk := 0.0
var _rk := 0.0
var _y_hi := 0.0
var _y_lo := 999.0
var _samples := 0
var _skipped := 0

func _ok(c: bool, label: String, detail := "") -> void:
	if c: print("  ok   %s %s" % [label, detail])
	else:
		failures += 1
		print("  FAIL %s %s" % [label, detail])

func _initialize() -> void:
	_level = load("res://levels/sandbox/sandbox.tscn").instantiate()
	root.add_child(_level)
	_tank = _level.get_node("Vehicles/Tank")
	print("[05 - a hard input reversal must not throw the tank around]")
	print("   full lock, full throttle, both axes reversed at once")
	print("   attitude sampled only while the tank is over flat ground")

func _cmd(move: Vector2) -> void:
	_tank.owner_peer = 1
	_tank.push_command(InputCommand.make(0, move, 0, Vector3(1, 0, 0)))

func _over_flat_ground() -> bool:
	var p := _tank.global_position
	var space := _level.get_viewport().world_3d.direct_space_state
	for offset in [Vector3.ZERO, Vector3(0, 0, 4), Vector3(0, 0, -4),
			Vector3(4, 0, 0), Vector3(-4, 0, 0)]:
		var at: Vector3 = p + offset
		var ray := PhysicsRayQueryParameters3D.create(
			Vector3(at.x, 60.0, at.z), Vector3(at.x, -5.0, at.z))
		ray.collision_mask = 1
		var hit := space.intersect_ray(ray)
		if hit.is_empty() or absf(float(hit["position"].y)) > 0.05:
			return false
	return true

func _physics_process(_d: float) -> bool:
	_t += 1
	var span := 900
	var local := _t % span
	if local == 1:
		if _i >= _cases.size():
			print("\n%s  (%d failures)" % ["PASS" if failures == 0 else "FAIL", failures])
			quit(1 if failures > 0 else 0)
			return true
		_tank.freeze = true
		_tank.global_transform = Transform3D(
			Basis(Vector3.UP, deg_to_rad(-90)), Vector3(-30, 1.4, -40))
		_tank.linear_velocity = Vector3.ZERO
		_tank.angular_velocity = Vector3.ZERO
		_tank.freeze = false
		_pk = 0.0; _rk = 0.0; _y_hi = 0.0; _y_lo = 999.0
		_samples = 0; _skipped = 0
	elif local < 80:
		_cmd(Vector2.ZERO)
	elif local < 420:
		_cmd(_cases[_i]["a"])
	elif local < 880:
		_cmd(_cases[_i]["b"])
		if _over_flat_ground():
			var e := _tank.global_transform.basis.get_euler()
			_pk = maxf(_pk, absf(rad_to_deg(e.x)))
			_rk = maxf(_rk, absf(rad_to_deg(e.z)))
			_y_hi = maxf(_y_hi, _tank.global_position.y)
			_y_lo = minf(_y_lo, _tank.global_position.y)
			_samples += 1
		else:
			_skipped += 1
	elif local == 880:
		var case_name: String = _cases[_i]["n"]
		if _samples < 100:
			_ok(false, "%s had too few flat-ground samples" % case_name,
				"%d sampled, %d skipped" % [_samples, _skipped])
		else:
			_ok(_pk < 8.0, "%s stays level in pitch" % case_name, "peak %.1f deg" % _pk)
			_ok(_rk < 8.0, "%s stays level in roll" % case_name, "peak %.1f deg" % _rk)
			_ok(_y_hi - _y_lo < 0.20, "%s does not buck" % case_name,
				"heave %.2f m over %d samples" % [_y_hi - _y_lo, _samples])
		_i += 1
	return false
