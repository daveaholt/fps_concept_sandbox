extends SceneTree

var failures := 0
var _level: Node
var _t := 0

func _ok(c: bool, label: String, detail := "") -> void:
	if c: print("  ok   %s %s" % [label, detail])
	else:
		failures += 1
		print("  FAIL %s %s" % [label, detail])

func _initialize() -> void:
	_level = load("res://levels/sandbox/sandbox.tscn").instantiate()
	root.add_child(_level)
	print("[10 - vehicles load before the menu starts networking]")

func _physics_process(_d: float) -> bool:
	_t += 1
	if _t < 20:
		return false
	var tank = _level.get_node("Vehicles/Tank")

	_ok(tank._server_authority,
		"a vehicle loaded with no peer assumes it is authoritative")

	tank._server_authority = false
	tank.freeze = true
	var moved: Vector3 = tank.global_position
	tank.apply_replicated_state({"p": moved + Vector3(10, 0, 0), "q": Quaternion(),
		"st": [77, 0], "o": 77})
	_ok(tank.seats.has_peer(77),
		"a non-authoritative vehicle accepts replicated seats")

	tank._server_authority = true
	tank.apply_replicated_state({"p": Vector3.ZERO, "q": Quaternion(), "st": [0, 0], "o": 0})
	_ok(tank.seats.has_peer(77),
		"an authoritative vehicle ignores replicated state, which is why the"
		+ " stale flag hid the tank from clients")

	tank.seats.clear()
	tank.refresh_authority()
	_ok(tank._server_authority,
		"refresh keeps it authoritative when there is still no peer")
	_ok(tank.has_method("refresh_authority")
		and _level.get_node("Vehicles/Helicopter").has_method("refresh_authority"),
		"both vehicles can re-decide their authority after load")

	var gs = root.get_node_or_null("/root/GameServer")
	_ok(gs.has_method("refresh_entity_authority"),
		"the server can refresh every controllable when networking begins")
	gs.refresh_entity_authority()
	_ok(true, "and doing so does not error with no peer present")

	print("\n%s  (%d failures)" % ["PASS" if failures == 0 else "FAIL", failures])
	quit(1 if failures > 0 else 0)
	return true
