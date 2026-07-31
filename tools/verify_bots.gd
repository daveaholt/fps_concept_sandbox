extends SceneTree

var _level: Node
var _t := 0
var _fail := 0
var _gs
var _start_positions: Dictionary = {}


func _ok(label: String, cond: bool, detail: String = "") -> void:
	if not cond:
		_fail += 1
	print("%s %s%s" % ["PASS" if cond else "FAIL", label, "  " + detail if detail != "" else ""])


func _initialize() -> void:
	_level = load("res://levels/sandbox/sandbox.tscn").instantiate()
	root.add_child(_level)


func _physics_process(_d: float) -> bool:
	_t += 1
	if _t == 30:
		_setup()
		return false
	if _t == 40:
		_record_positions()
		return false
	if _t < 260:
		return false
	_check_movement()
	_check_pure_brain()
	print("bots: %d failing" % _fail)
	quit(1 if _fail > 0 else 0)
	return true


func _setup() -> void:
	_gs = root.get_node_or_null("/root/GameServer")
	_gs.is_active = true
	_gs.ballistics.authoritative = true
	_gs.roster.clear()
	_gs.handle_slot_request(1, 0, "Human")
	_gs.handle_start_request(1)

	_ok("starting a match fills the empty slots with bots", _gs.bot_count() > 0,
		"%d bots" % _gs.bot_count())
	_ok("the human keeps their slot", _gs.roster.occupant(0) == 1)
	_ok("bots take both teams", _bots_on(1) > 0 and _bots_on(2) > 0,
		"%d on team 1, %d on team 2" % [_bots_on(1), _bots_on(2)])
	_ok("a bot peer is never a real peer id", BotController.is_bot(-1000)
		and not BotController.is_bot(1) and not BotController.is_bot(0),
		"real peers are positive, so nothing can be mistaken for the other")
	_ok("every bot got a body", _bot_bodies().size() == _gs.bot_count(),
		"%d bodies for %d bots" % [_bot_bodies().size(), _gs.bot_count()])
	_ok("bots carry a callsign like anyone else",
		_gs.roster.name_of_slot(1) != "" and _gs.roster.name_of_slot(1) != "—",
		_gs.roster.name_of_slot(1))


func _bots_on(team: int) -> int:
	var total := 0
	for slot in Roster.SLOT_COUNT:
		var peer: int = _gs.roster.occupant(slot)
		if BotController.is_bot(peer) and _gs.roster.team_of(peer) == team:
			total += 1
	return total


func _bot_bodies() -> Array:
	var out: Array = []
	for node in _level.get_node("Players").get_children():
		if BotController.is_bot(node.owner_peer):
			out.append(node)
	return out


func _record_positions() -> void:
	for body in _bot_bodies():
		_start_positions[body.owner_peer] = body.global_position


func _check_movement() -> void:
	var moved := 0
	var furthest := 0.0
	for body in _bot_bodies():
		if not _start_positions.has(body.owner_peer):
			continue
		var travelled: float = _start_positions[body.owner_peer].distance_to(
			body.global_position)
		if travelled > 2.0:
			moved += 1
		furthest = maxf(furthest, travelled)
	_ok("bots actually move", moved > 0,
		"%d of %d moved, furthest %.1f m in ~3.5 s"
		% [moved, _bot_bodies().size(), furthest])
	_ok("bots are being fed commands", _gs.bots.tracked() > 0,
		"%d minds" % _gs.bots.tracked())

	var map: RID = _gs.navigation_map()
	_ok("the server knows about the navigation map", map.is_valid(),
		"without it bots walk into walls")


func _check_pure_brain() -> void:
	var origin := Vector3.ZERO
	var north := Vector3(0.0, 0.0, -10.0)
	_ok("facing is computed toward a point",
		absf(BotBrain.yaw_towards(origin, north)) < 0.01,
		"%.3f rad toward -Z" % BotBrain.yaw_towards(origin, north))

	var limit := BotBrain.TURN_RATE * 0.016
	var turned := BotBrain.step_yaw(0.0, 1.5, 0.016)
	_ok("turning is rate-limited, not instant",
		turned > 0.0 and turned <= limit + 0.0001,
		"%.3f rad in one tick, limit %.3f" % [turned, limit])
	_ok("and turns the short way round",
		BotBrain.step_yaw(0.0, -1.5, 0.016) < 0.0,
		"a target to the left is not reached by turning right")
	_ok("a half turn is still rate-limited",
		absf(BotBrain.step_yaw(0.0, PI, 0.016)) <= limit + 0.0001,
		"either direction is correct at exactly 180 degrees")

	var lead := BotBrain.lead_point(Vector3(0, 0, -50), Vector3(10, 0, 0),
		Vector3.ZERO, 400.0)
	_ok("bots lead a moving target", lead.x > 0.0,
		"aims %.2f m ahead of a crossing runner" % lead.x)

	_ok("no shot without line of sight",
		not BotBrain.should_fire(Vector3.FORWARD, origin, north, false))
	_ok("no shot when facing the wrong way",
		not BotBrain.should_fire(Vector3.BACK, origin, north, true))
	_ok("a shot when lined up and visible",
		BotBrain.should_fire(Vector3.FORWARD, origin, north, true))
	_ok("no shot beyond engagement range",
		not BotBrain.should_fire(Vector3.FORWARD, origin, Vector3(0, 0, -500), true))
	_ok("bots close the distance when far", BotBrain.wants_to_close(40.0))
	_ok("and hold at a standoff", not BotBrain.wants_to_close(3.0))
