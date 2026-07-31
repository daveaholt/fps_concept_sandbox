extends SceneTree

var failures := 0

func _ok(c: bool, label: String, detail := "") -> void:
	if c: print("  ok   %s %s" % [label, detail])
	else:
		failures += 1
		print("  FAIL %s %s" % [label, detail])

func _initialize() -> void:
	print("[13 - roster: slots are the single source of team and squad]")
	var r := Roster.new()

	_ok(Roster.SLOT_COUNT == 16, "sixteen slots", "%d" % Roster.SLOT_COUNT)
	_ok(Roster.SQUAD_SIZE == 4 and Roster.SQUAD_COUNT == 4,
		"four squads of four, no remainder at 8 a side")

	_ok(Roster.squad_of_slot(0) == 0 and Roster.squad_of_slot(3) == 0,
		"slots 0-3 are squad 0 (Red)")
	_ok(Roster.squad_of_slot(4) == 1 and Roster.squad_of_slot(15) == 3,
		"slots 4 and 15 land in squads 1 and 3")
	_ok(Roster.team_of_slot(0) == 1 and Roster.team_of_slot(7) == 1,
		"Red and Yellow are team 1")
	_ok(Roster.team_of_slot(8) == 2 and Roster.team_of_slot(15) == 2,
		"Blue and Green are team 2")
	_ok(Roster.squad_name(0) == "Red" and Roster.squad_name(2) == "Blue",
		"squad names match the spec")

	_ok(r.occupied_count() == 0, "starts empty")
	_ok(r.team_of(42) == Roster.UNALIGNED,
		"an unassigned peer is unaligned, not team 1", "team %d" % r.team_of(42))

	_ok(r.assign(11, 0), "a peer can take a free slot")
	_ok(r.team_of(11) == 1 and r.squad_of(11) == 0, "and derives team 1, squad Red")
	_ok(not r.assign(22, 0), "a second peer cannot take the same slot")
	_ok(r.occupant(0) == 11, "and the slot still holds the first peer")

	_ok(r.assign(22, 1), "peer 22 takes the next Red slot")
	_ok(r.assign(33, 8), "peer 33 takes a Blue slot")
	_ok(r.team_of(33) == 2, "and is on team 2")

	var mates := r.squadmates(11)
	_ok(mates.size() == 1 and mates[0] == 22, "squadmates lists 22 and not 33",
		str(mates))
	_ok(r.squadmates(33).is_empty(), "a lone squad member has no squadmates")

	_ok(r.assign(11, 4), "moving to a free slot is allowed")
	_ok(r.slot_of(11) == 4 and r.is_free(0),
		"and the old slot is released, not duplicated")
	_ok(r.squad_of(11) == 1, "team and squad follow the slot, they are not stored")
	_ok(r.squadmates(22).is_empty(),
		"22 is alone in Red now that 11 moved to Yellow")

	r.release(22)
	_ok(r.is_free(1) and not r.has_peer(22), "release frees the slot")

	var full := Roster.new()
	for i in Roster.SLOT_COUNT:
		full.assign(100 + i, i)
	_ok(full.occupied_count() == 16, "sixteen peers fill the board")
	_ok(full.first_free_slot() == -1, "a full board reports no free slot")
	_ok(not full.assign(999, 3), "and refuses a seventeenth")
	_ok(full.peers_on_team(1).size() == 8 and full.peers_on_team(2).size() == 8,
		"eight a side")

	var wire := Roster.new()
	wire.from_array(full.to_array())
	_ok(wire.to_array() == full.to_array(), "roster survives a round trip over the wire")
	_ok(wire.team_of(115) == full.team_of(115), "and resolves the same teams")

	_ok(not r.assign(0, 5), "peer 0 is not a real peer and cannot hold a slot")
	_ok(not r.assign(7, 16) and not r.assign(7, -1), "out-of-range slots are refused")

	print("\n%s  (%d failures)" % ["PASS" if failures == 0 else "FAIL", failures])
	quit(1 if failures > 0 else 0)
