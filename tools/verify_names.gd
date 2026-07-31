extends SceneTree

var _level: Node
var _t := 0
var _fail := 0
var _gs
var _gc


func _ok(label: String, cond: bool, detail: String = "") -> void:
	if not cond:
		_fail += 1
	print("%s %s%s" % ["PASS" if cond else "FAIL", label, "  " + detail if detail != "" else ""])


func _initialize() -> void:
	_level = load("res://levels/sandbox/sandbox.tscn").instantiate()
	root.add_child(_level)


func _physics_process(_d: float) -> bool:
	_t += 1
	if _t < 20:
		return false
	_gs = root.get_node_or_null("/root/GameServer")
	_gc = root.get_node_or_null("/root/GameClient")
	_gs.is_active = true

	_check_chosen_names()
	_check_sanitising()
	_check_replication()
	_check_relationships()
	_check_plate()
	_check_owner_reaches_clients()
	_check_renaming()

	print("names: %d failing" % _fail)
	quit(1 if _fail > 0 else 0)
	return true


func _check_chosen_names() -> void:
	_gs.roster.clear()
	_gs.handle_slot_request(11, 0, "Rook")
	_ok("a chosen name sticks to the slot", _gs.roster.name_of(11) == "Rook",
		_gs.roster.name_of(11))

	_gs.handle_slot_request(22, 1, "")
	_ok("an empty name falls back to the callsign",
		_gs.roster.name_of(22) == Roster.callsign(1), _gs.roster.name_of(22))

	_gs.roster.release(11)
	_ok("leaving a slot clears its name", _gs.roster.name_of_slot(0) == Roster.callsign(0),
		"otherwise the next occupant inherits a stranger's name")


func _check_sanitising() -> void:
	_ok("names are trimmed", Roster.sanitise_name("  Vex  ") == "Vex")
	_ok("names are length-capped",
		Roster.sanitise_name("ABCDEFGHIJKLMNOPQRSTUVWXYZ").length()
		== Roster.NAME_MAX_LENGTH,
		"%d chars" % Roster.sanitise_name("ABCDEFGHIJKLMNOPQRSTUVWXYZ").length())
	var nasty := Roster.sanitise_name("bad\nname\there")
	_ok("control characters are stripped",
		not nasty.contains("\n") and not nasty.contains("\t"), nasty)
	_ok("a name of only whitespace becomes empty", Roster.sanitise_name("   ") == "")


func _check_replication() -> void:
	_gs.roster.clear()
	_gs.handle_slot_request(11, 0, "Rook")
	_gs.handle_slot_request(22, 8, "Vulture")
	_gc.roster.clear()
	_gc.apply_roster(_gs.roster.to_array(), int(_gs.phase), _gs.tickets, 0,
		_gs.roster.names_to_array())
	_ok("names reach the client", _gc.roster.name_of(11) == "Rook"
		and _gc.roster.name_of(22) == "Vulture",
		"%s, %s" % [_gc.roster.name_of(11), _gc.roster.name_of(22)])
	_ok("a client with no names still reads callsigns",
		Roster.new().name_of_slot(3) == Roster.callsign(3))


func _check_relationships() -> void:
	_gs.roster.clear()
	_gs.handle_slot_request(1, 0, "Me")
	_gs.handle_slot_request(2, 1, "Mate")
	_gs.handle_slot_request(3, 4, "OtherSquad")
	_gs.handle_slot_request(4, 8, "Foe")
	_gc.roster.from_array(_gs.roster.to_array())
	_gc.roster.names_from_array(_gs.roster.names_to_array())
	_gc._peer_id = 1
	_gc.my_team = 1

	var roster: Roster = _gc.roster
	_ok("a squadmate is green",
		Relations.colour_for(roster, 1, 1, 2) == Relations.SQUAD)
	_ok("another squad on your team is blue",
		Relations.colour_for(roster, 1, 1, 3) == Relations.TEAM,
		"team %d vs %d" % [roster.team_of(3), 1])
	_ok("the other team is red",
		Relations.colour_for(roster, 1, 1, 4) == Relations.ENEMY)
	_ok("the rule is a pure function, so it can be tested at all",
		Relations.colour_for(roster, 4, 2, 1) == Relations.ENEMY,
		"viewed from the other side, the same pair reads enemy")


func _check_plate() -> void:
	var body: Node3D = load("res://entities/player/player.tscn").instantiate()
	_level.get_node("Players").add_child(body)
	var plate: Label3D = body.get_node_or_null("Nameplate")
	_ok("a player carries a nameplate", plate != null)
	_ok("it hangs above the head", plate.position.y > 1.8, "%.2f m" % plate.position.y)
	_ok("it starts hidden", not plate.visible,
		"nothing is shown until the client decides the relationship")
	_ok("it billboards", plate.billboard != BaseMaterial3D.BILLBOARD_DISABLED)
	_ok("it sits outside Visual",
		body.get_node_or_null("Visual/Nameplate") == null,
		"else possession would move it to the own-body layer and hide it from everyone")
	body.queue_free()


func _check_owner_reaches_clients() -> void:
	var body: Node3D = load("res://entities/player/player.tscn").instantiate()
	_level.get_node("Players").add_child(body)
	body.owner_peer = 77
	body.team = 2
	var wire: Dictionary = body.get_net_state()
	_ok("a player replicates who owns it", wire.has("o"),
		"without this every remote body reads owner_peer 0 and no client sees a plate")
	_ok("and which team it is on", wire.has("t"))

	var mirror: Node3D = load("res://entities/player/player.tscn").instantiate()
	_level.get_node("Players").add_child(mirror)
	mirror.role = mirror.Role.REMOTE
	mirror.apply_replicated_state(wire)
	_ok("a client learns the owner from the snapshot", mirror.owner_peer == 77,
		"peer %d" % mirror.owner_peer)
	_ok("and the team", mirror.team == 2)
	body.queue_free()
	mirror.queue_free()


func _check_renaming() -> void:
	_gs.roster.clear()
	_gs.handle_slot_request(11, 0, "First")
	_ok("the slot starts with the name given at pick time",
		_gs.roster.name_of(11) == "First")

	_gs.handle_name_request(11, "Second")
	_ok("typing a name afterwards updates the slot",
		_gs.roster.name_of(11) == "Second", _gs.roster.name_of(11))

	_gs.handle_name_request(99, "Ghost")
	var taken := false
	for slot in Roster.SLOT_COUNT:
		if _gs.roster.name_of_slot(slot) == "Ghost":
			taken = true
	_ok("a peer holding no slot cannot set a name", not taken)

	_gs.handle_name_request(11, "  Third  ")
	_ok("a renamed slot is sanitised too", _gs.roster.name_of(11) == "Third",
		_gs.roster.name_of(11))
