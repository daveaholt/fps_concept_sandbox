extends SceneTree

var failures := 0
var _level: Node
var _t := 0
var _gs
var _gc

func _ok(c: bool, label: String, detail := "") -> void:
	if c: print("  ok   %s %s" % [label, detail])
	else:
		failures += 1
		print("  FAIL %s %s" % [label, detail])

func _initialize() -> void:
	_level = load("res://levels/sandbox/sandbox.tscn").instantiate()
	root.add_child(_level)
	print("[13 - tickets end the match, then everyone returns to the lobby]")

func _physics_process(_d: float) -> bool:
	_t += 1
	if _t < 30:
		return false
	_gs = root.get_node_or_null("/root/GameServer")
	_gc = root.get_node_or_null("/root/GameClient")
	_gs.is_active = true
	_gs.roster.clear()
	_gs.handle_slot_request(11, 0)
	_gs.handle_slot_request(22, 8)
	_gs.handle_slot_request(_gs.HOST_PEER, 1)
	_gs.handle_start_request(_gs.HOST_PEER)

	_ok(_gs.phase == _gs.Phase.PLAYING, "match running")
	_ok(int(_gs.tickets[1]) == _gs.START_TICKETS
		and int(_gs.tickets[2]) == _gs.START_TICKETS,
		"both teams start on full tickets", "%d each" % _gs.START_TICKETS)

	_gs._spend_ticket(1)
	_ok(int(_gs.tickets[1]) == _gs.START_TICKETS - 1,
		"a death costs the dying player's team one ticket")
	_ok(int(_gs.tickets[2]) == _gs.START_TICKETS,
		"and does not touch the other team")

	_gs._spend_ticket(Roster.UNALIGNED)
	_ok(int(_gs.tickets[1]) == _gs.START_TICKETS - 1
		and int(_gs.tickets[2]) == _gs.START_TICKETS,
		"an unaligned death spends nothing rather than guessing a side")

	_ok(_gc.tickets.has(1), "the client mirrors the ticket counts",
		"team 1: %d" % int(_gc.tickets.get(1, -1)))

	for i in _gs.START_TICKETS + 4:
		_gs._spend_ticket(2)
	_ok(int(_gs.tickets[2]) == 0, "tickets floor at zero, never negative",
		"%d" % int(_gs.tickets[2]))
	_ok(_gs.phase == _gs.Phase.RESULT, "running a team to zero ends the match")
	_ok(_gs.winning_team == 1, "and the other team wins", "team %d" % _gs.winning_team)
	_ok(_gc.phase == _gs.Phase.RESULT and _gc.winning_team == 1,
		"the client is told who won")

	_gs._spend_ticket(1)
	_ok(int(_gs.tickets[1]) == _gs.START_TICKETS - 1,
		"deaths after the match ends do not spend more tickets")

	_gc.set_deploy_map(true)
	_ok(not _gc.deploy_map_open, "nobody can deploy into a finished match")

	_ok(_gs.roster.occupant(0) == 11 and _gs.roster.occupant(8) == 22,
		"slots are still held during the result")

	_gs._return_to_lobby()
	_ok(_gs.phase == _gs.Phase.LOBBY, "the match returns to the lobby")
	_ok(_gs.roster.occupant(0) == 11 and _gs.roster.occupant(8) == 22,
		"and slots are kept, so a rematch is one press of Start")
	_ok(int(_gs.tickets[1]) == _gs.START_TICKETS
		and int(_gs.tickets[2]) == _gs.START_TICKETS, "tickets reset")
	_ok(_gs.winning_team == 0, "and the winner is cleared")

	_gs.handle_start_request(_gs.HOST_PEER)
	_ok(_gs.phase == _gs.Phase.PLAYING, "a rematch starts straight away")

	print("\n%s  (%d failures)" % ["PASS" if failures == 0 else "FAIL", failures])
	quit(1 if failures > 0 else 0)
	return true
