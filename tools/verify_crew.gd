extends SceneTree

var failures := 0
var _level: Node
var _t := 0
var _gs

func _ok(c: bool, label: String, detail := "") -> void:
	if c: print("  ok   %s %s" % [label, detail])
	else:
		failures += 1
		print("  FAIL %s %s" % [label, detail])

func _initialize() -> void:
	_level = load("res://levels/sandbox/sandbox.tscn").instantiate()
	root.add_child(_level)
	print("[04/13 - two crew in one vehicle, and spawning into a free seat]")

func _near(vehicle: Node3D, peer: int) -> Node:
	var body = _gs._spawn_infantry(peer, vehicle.global_position + Vector3(2, 0, 0),
		Vector3(0, 0, -1))
	_gs._bind(peer, body)
	return body

func _physics_process(_d: float) -> bool:
	_t += 1
	if _t < 30:
		return false
	_gs = root.get_node_or_null("/root/GameServer")
	_gs.is_active = true
	_gs.roster.clear()
	_gs.handle_slot_request(11, 0)
	_gs.handle_slot_request(22, 1)
	_gs.handle_slot_request(33, 8)
	_gs.phase = _gs.Phase.PLAYING

	var heli = _level.get_node("Vehicles/Helicopter")
	_ok(heli.seats.count() == 2, "the helicopter has two seats", "%d" % heli.seats.count())

	_near(heli, 11)
	_gs.handle_enter_request(11, heli)
	_ok(heli.seats.driver() == 11, "first player in becomes the pilot")
	_ok(heli.owner_peer == 11, "owner_peer still means the driver seat")
	_ok(heli.has_free_seat(), "and a seat is still free")

	_near(heli, 22)
	_gs.handle_enter_request(22, heli)
	_ok(heli.seat_of(22) == 1, "the second player takes the gunner seat")
	_ok(heli.seats.occupied_count() == 2 and not heli.has_free_seat(),
		"the helicopter is now full")

	_near(heli, 33)
	_gs.handle_enter_request(33, heli)
	_ok(heli.seat_of(33) < 0, "a third player is refused")

	_ok(heli.team_id() == 1, "the vehicle takes the pilot's team", "team %d" % heli.team_id())

	heli.push_command(InputCommand.make(0, Vector2(0.5, 0), 0, Vector3(0, 0, -1)), 0)
	heli.push_command(InputCommand.make(0, Vector2(-0.5, 0), 0, Vector3(1, 0, 0)), 1)
	_ok(heli._pending[0].size() == 1 and heli._pending[1].size() == 1,
		"pilot and gunner commands queue separately, not into one stream")

	_gs.handle_exit_request(11)
	_ok(heli.seats.driver() == 0, "the pilot can get out")
	_ok(heli.seat_of(22) == 1, "and the gunner stays aboard")
	_ok(heli.is_occupied(), "so the helicopter is still occupied")
	_ok(heli.team_id() == 1, "and keeps a team from its remaining crew")

	_gs.handle_exit_request(22)
	_ok(not heli.is_occupied() and heli.team_id() == Roster.UNALIGNED,
		"emptying it returns the helicopter to unaligned")

	_near(heli, 11)
	_gs.handle_enter_request(11, heli)
	_ok(_gs.can_spawn_on(22, 11),
		"a squadmate flying with a free seat is a valid spawn target")
	_gs._release_peer(22)
	_gs.handle_squad_spawn_request(22, 11)
	_ok(heli.seat_of(22) == 1,
		"and spawning on them puts you in the seat, not beside the aircraft")

	_gs._release_peer(33)
	_ok(not _gs.can_spawn_on(33, 11),
		"a full vehicle is not offered, and an enemy never is")

	var gc = root.get_node_or_null("/root/GameClient")
	gc.roster.from_array(_gs.roster.to_array())
	gc.phase = _gs.Phase.PLAYING
	var tank = _level.get_node("Vehicles/Tank")
	_gs._release_peer(33)
	tank.take_seat(33)
	_gs._bind(33, tank)
	_ok(tank.seats.has_peer(33), "peer 33 is crewing the tank")
	_ok(gc.squadmate_entity(33) == tank,
		"the client locates a squadmate who is inside a vehicle, not only on foot")
	var stale = _level.get_node_or_null("Players/Player_33")
	_ok(stale == null or stale.is_queued_for_deletion(),
		"which matters because their infantry body is despawned on entry")
	var wire = tank.get_net_state()
	_ok(wire.has("st") and int(wire["st"][0]) == 33,
		"seat occupancy rides the snapshot so remote clients can see it too")

	print("\n%s  (%d failures)" % ["PASS" if failures == 0 else "FAIL", failures])
	quit(1 if failures > 0 else 0)
	return true
