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
	print("[13 - lobby, phases, and the CLI bypass]")

func _physics_process(_d: float) -> bool:
	_t += 1
	if _t < 30:
		return false
	_gs = root.get_node_or_null("/root/GameServer")
	_gc = root.get_node_or_null("/root/GameClient")

	var lobby = _level.get_node_or_null("UI/Lobby")
	var menu = _level.get_node_or_null("UI/MainMenu")
	_ok(lobby != null, "lobby node is in the level")
	_ok(menu != null, "main menu node is in the level")
	_ok(lobby != null and lobby.get_script() != null,
		"lobby has its script attached, not just a bare Control")
	_ok(menu != null and menu.get_script() != null,
		"main menu has its script attached, not just a bare Control")
	_ok(lobby != null and lobby.has_method("_refresh"), "lobby script is the right one")
	_ok(menu != null and menu.has_method("_on_host"), "menu script is the right one")
	_ok(menu != null and menu.get_child_count() > 0,
		"menu actually built its buttons when no launch flag was given",
		"%d children" % (menu.get_child_count() if menu != null else -1))

	_ok(_gs.phase == _gs.Phase.LOBBY,
		"a server that never began hosting sits in LOBBY, not PLAYING")

	_gs.is_active = true
	_gs.phase = _gs.Phase.LOBBY
	_gs.roster.clear()

	_gs.handle_slot_request(11, 0)
	_ok(_gs.roster.occupant(0) == 11, "a slot request is granted by the server")
	_gs.handle_slot_request(22, 0)
	_ok(_gs.roster.occupant(0) == 11, "a taken slot is refused and does not move")
	_gs.handle_slot_request(22, 5)
	_ok(_gs.roster.occupant(5) == 22, "a second player takes a different slot")
	_ok(_gs.roster.team_of(11) == 1 and _gs.roster.team_of(22) == 1,
		"slots 0 and 5 are both team 1 (Red and Yellow)")
	_gs.handle_slot_request(33, 99)
	_ok(_gs.roster.slot_of(33) < 0, "an out-of-range slot is refused")

	_ok(_gs.phase == _gs.Phase.LOBBY, "still in LOBBY before anyone starts")
	_gs.handle_start_request(44)
	_ok(_gs.phase == _gs.Phase.LOBBY, "a peer holding no slot cannot start the match")
	_gs.handle_start_request(11)
	_ok(_gs.phase == _gs.Phase.LOBBY,
		"nor can a client that holds one — starting is the host's call")
	_gs.roster.assign(_gs.HOST_PEER, _gs.roster.first_free_slot())
	_gs.handle_start_request(_gs.HOST_PEER)
	_ok(_gs.phase == _gs.Phase.PLAYING, "the host can start it")
	_ok(_gs.roster.occupied_count() == Roster.SLOT_COUNT,
		"with bots on, start fills the empty slots",
		"%d of %d filled" % [_gs.roster.occupied_count(), Roster.SLOT_COUNT])

	_gs.phase = _gs.Phase.LOBBY
	_gs._clear_bots()
	_gs.fill_bots = false
	var humans: int = _gs.roster.occupied_count()
	_gs.handle_start_request(_gs.HOST_PEER)
	_ok(_gs.roster.occupied_count() == humans,
		"with bots off, empty slots simply stay empty — 13's original rule holds",
		"%d of %d filled" % [_gs.roster.occupied_count(), Roster.SLOT_COUNT])
	_gs.fill_bots = true

	_gs.handle_slot_request(11, 9)
	_ok(_gs.roster.slot_of(11) == 0, "slots cannot be switched mid-match")

	_gs.roster.clear()
	_gs.client_ready_local(77)
	_ok(_gs.roster.has_peer(77),
		"a peer becoming ready during PLAYING is auto-assigned a slot",
		"slot %d" % _gs.roster.slot_of(77))

	_ok(_gc.phase == _gs.Phase.PLAYING,
		"the host's own client mirrors the phase without an RPC to itself")
	_ok(_gc.roster.has_peer(77), "and mirrors the roster")

	_gs.roster.clear()
	_gs.phase = _gs.Phase.PLAYING
	_gs.client_ready_local(88, false)
	_ok(not _gs.roster.has_peer(88),
		"a menu joiner is NOT auto-slotted mid-match; they get the picker")
	_gs.handle_slot_request(88, 12)
	_ok(_gs.roster.slot_of(88) == 12,
		"and may then choose a slot even though the match is running",
		"%s squad, team %d" % [Roster.squad_name(Roster.squad_of_slot(12)),
			_gs.roster.team_of(88)])

	_gs.roster.clear()
	_gs.client_ready_local(99, true)
	_ok(_gs.roster.has_peer(99),
		"a flagged CLI launch is still auto-slotted, so the suite is unaffected")

	var hud = _level.get_node_or_null("UI/HUD")
	_ok(hud != null and hud.has_method("_refresh_squad"),
		"HUD has the team and squad readout")
	_ok(hud != null and hud.get_node_or_null("Self/SquadList") != null,
		"the squad list sits in the self corner (14)")
	_ok(hud != null and hud.get_node_or_null("Situation") != null
		and hud._mine_bar != null and hud._their_bar != null,
		"tickets read out in the situation corner, as a count and a bar each")

	var bm = _gs.ballistics
	_ok(bm != null and not bm.authoritative,
		"a level registered before hosting starts leaves ballistics non-authoritative")
	_gs.is_active = false
	_gs.begin_hosting(27099, NetCli.Mode.HOST)
	_ok(_gs.is_active, "hosting can be started later, from the menu")
	_ok(bm != null and bm.authoritative,
		"and starting it flips ballistics authoritative, or nothing can be damaged")

	print("\n%s  (%d failures)" % ["PASS" if failures == 0 else "FAIL", failures])
	quit(1 if failures > 0 else 0)
	return true
