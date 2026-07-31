extends SceneTree

var failures := 0

func _ok(c: bool, label: String, detail := "") -> void:
	if c: print("  ok   %s %s" % [label, detail])
	else:
		failures += 1
		print("  FAIL %s %s" % [label, detail])

func _initialize() -> void:
	print("[04 - seats: multi-occupant vehicles]")
	var s := Seats.new(2)

	_ok(s.count() == 2, "a two-seat vehicle has two seats")
	_ok(s.is_empty() and s.driver() == 0, "starts empty with no driver")
	_ok(Seats.DRIVER == 0, "seat 0 is the driver, so owner_peer keeps its meaning")

	_ok(s.take(11, Seats.DRIVER), "a peer can take the driver seat")
	_ok(s.driver() == 11, "and becomes the driver")
	_ok(not s.take(22, Seats.DRIVER), "a second peer cannot take a held seat")
	_ok(s.take(22, 1), "but can take the free one")
	_ok(s.seat_of(22) == 1 and s.seat_of(11) == 0, "seats resolve per peer")
	_ok(s.occupied_count() == 2 and s.first_free() == -1, "the vehicle is now full")
	_ok(s.take_first_free(33) == -1, "a third peer is refused")

	_ok(s.occupants().size() == 2, "occupants lists both")

	s.release(11)
	_ok(s.driver() == 0, "the driver can leave")
	_ok(s.occupant(1) == 22, "leaving the driver seat does not evict the gunner")
	_ok(not s.is_empty(), "and the vehicle is still occupied")
	_ok(s.take_first_free(33) == 0, "the empty driver seat is the next one offered")

	var moved := Seats.new(4)
	moved.take(7, 2)
	_ok(moved.seat_of(7) == 2, "peer sits in seat 2")
	moved.take(7, 3)
	_ok(moved.seat_of(7) == 3 and moved.is_free(2),
		"moving seats releases the old one rather than duplicating the peer")
	_ok(moved.occupied_count() == 1, "so they occupy exactly one seat")

	_ok(not moved.take(0, 1), "peer 0 is not a real peer")
	_ok(not moved.take(9, 99) and not moved.take(9, -1), "out-of-range seats are refused")

	print("\n%s  (%d failures)" % ["PASS" if failures == 0 else "FAIL", failures])
	quit(1 if failures > 0 else 0)
