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
	print("[07 - deploy markers: what you are spawning on, and whether you can]")

func _physics_process(_d: float) -> bool:
	_t += 1
	if _t < 30:
		return false
	var gs = root.get_node_or_null("/root/GameServer")
	var gc = root.get_node_or_null("/root/GameClient")
	var map = _level.get_node("UI/DeployMap")
	var tank = _level.get_node("Vehicles/Tank")
	var heli = _level.get_node("Vehicles/Helicopter")

	gs.is_active = true
	gs.roster.clear()
	gs.handle_slot_request(1, 0)
	gs.handle_slot_request(22, 1)
	gs.phase = gs.Phase.PLAYING
	gc.roster.from_array(gs.roster.to_array())
	gc.phase = gs.Phase.PLAYING

	var body = gs._spawn_infantry(22, tank.global_position + Vector3(4, 0, 0),
		Vector3(0, 0, -1))
	gs._bind(22, body)
	var info: Dictionary = gc.squadmate_marker_info(22)
	_ok(info.get("kind") == "infantry", "a squadmate on foot reads as infantry",
		str(info.get("kind")))
	_ok(bool(info.get("available")), "and is available")

	map._build_markers()
	map._refresh()
	var button: Button = map._mate_markers[22]
	_ok(button.text.begins_with("\u25b2"), "infantry marker uses the soldier icon",
		button.text)
	_ok(not button.disabled, "and is selectable")

	gs.handle_enter_request(22, tank)
	map._refresh()
	info = gc.squadmate_marker_info(22)
	_ok(info.get("kind") == "tank", "a squadmate in the tank reads as a tank")
	_ok("TANK" in button.text and button.text.begins_with("\u25a0"),
		"and the marker says so, with its own icon", button.text)
	_ok(bool(info.get("available")), "one free seat means still available")
	_ok(button.modulate != map.UNAVAILABLE, "so it is drawn in the squad colour")

	tank.take_seat(77)
	map._refresh()
	_ok(not bool(gc.squadmate_marker_info(22).get("available")),
		"filling the last seat makes it unavailable")
	_ok(button.disabled, "the marker is not selectable")
	_ok(button.modulate == map.UNAVAILABLE, "and is greyed out rather than squad-coloured")
	_ok("(full)" in button.text, "with the reason shown", button.text)

	var before: int = map._selected_mate
	map._on_mate_pressed(22)
	_ok(map._selected_mate == before, "clicking an unavailable marker selects nothing")
	tank.leave_seat(77)

	gs.handle_exit_request(22)
	gs._bind(22, gs._spawn_infantry(22, heli.global_position + Vector3(4, 0, 0),
		Vector3(0, 0, -1)))
	gs.handle_enter_request(22, heli)
	map._refresh()
	_ok(gc.squadmate_marker_info(22).get("kind") == "heli",
		"a squadmate in the helicopter reads as a heli")
	_ok("HELI" in button.text, "and the marker distinguishes it from the tank",
		button.text)

	var disabled_point: SpawnPoint = null
	for node in root.get_tree().get_nodes_in_group("spawn_points"):
		disabled_point = node
		break
	if disabled_point != null:
		disabled_point.enabled = false
		map._refresh()
		_ok(map._markers[disabled_point].modulate == map.UNAVAILABLE,
			"a disabled spawn point is greyed too, not just squadmates")
		disabled_point.enabled = true

	print("\n%s  (%d failures)" % ["PASS" if failures == 0 else "FAIL", failures])
	quit(1 if failures > 0 else 0)
	return true
