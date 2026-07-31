extends SceneTree

var failures := 0
var _level: Node
var _tank: VehicleBody3D
var _t := 0

func _ok(c: bool, label: String, detail := "") -> void:
	if c: print("  ok   %s %s" % [label, detail])
	else:
		failures += 1
		print("  FAIL %s %s" % [label, detail])

func _initialize() -> void:
	_level = load("res://levels/sandbox/sandbox.tscn").instantiate()
	root.add_child(_level)
	_tank = _level.get_node("Vehicles/Tank")
	print("[10 - the shooter must see their own tracer unless they predicted it]")

func _physics_process(_d: float) -> bool:
	_t += 1
	if _t < 30:
		return false
	var gc = root.get_node_or_null("/root/GameClient")
	var gs = root.get_node_or_null("/root/GameServer")
	gc.ballistics = gs.ballistics
	var bm = gc.ballistics

	gc.my_entity = _tank
	_ok(not gc.is_predicting(), "a possessed tank does not predict its own shots",
		"is_predicting()=%s" % str(gc.is_predicting()))

	var before: int = bm.live_count()
	gc.spawn_tracer(Vector3(0, 5, 0), Vector3(0, 0, -1), _tank.shell_params_id, gc.get_peer_id())
	var after: int = bm.live_count()
	_ok(after > before, "the tank gunner gets a tracer for their own shell",
		"live %d -> %d" % [before, after])

	var infantry = gs._spawn_infantry(gc.get_peer_id(), Vector3(0, 2, 0), Vector3(0, 0, -1))
	_ok(infantry != null, "spawned an infantry entity to check the skip path")
	if infantry != null:
		infantry.role = infantry.Role.PREDICTED
		gc.my_entity = infantry
		_ok(gc.is_predicting(), "possessed infantry does predict its own shots",
			"is_predicting()=%s" % str(gc.is_predicting()))
		var b2: int = bm.live_count()
		gc.spawn_tracer(Vector3(0, 5, 0), Vector3(0, 0, -1), 0, gc.get_peer_id())
		_ok(bm.live_count() == b2, "a predicting shooter is still skipped, so no double tracer",
			"live stayed at %d" % b2)

	print("\n%s  (%d failures)" % ["PASS" if failures == 0 else "FAIL", failures])
	quit(1 if failures > 0 else 0)
	return true
