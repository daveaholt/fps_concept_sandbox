extends SceneTree

var _level: Node
var _t := 0
var _fail := 0
var _gs
var _gc
var _hud: Control


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
	_hud = _level.find_child("HUD", true, false)

	_check_corners()
	_check_colours()
	_check_tickets()
	_check_callsigns()
	_check_ping_rules()
	_check_minimap()

	print("hud layout: %d failing" % _fail)
	quit(1 if _fail > 0 else 0)
	return true


func _check_corners() -> void:
	var situation: Control = _hud.get_node_or_null("Situation")
	var self_block: Control = _hud.get_node_or_null("Self")
	_ok("the situation corner exists", situation != null)
	_ok("the self corner exists", self_block != null)
	_ok("the old hand-positioned panel is gone",
		_hud.get_node_or_null("Bottom") == null
		or _hud.get_node_or_null("Bottom").is_queued_for_deletion())
	_ok("situation grows up from the bottom left",
		situation.grow_vertical == Control.GROW_DIRECTION_BEGIN
		and is_equal_approx(situation.anchor_left, 0.0))
	_ok("self grows up and left from the bottom right",
		self_block.grow_vertical == Control.GROW_DIRECTION_BEGIN
		and self_block.grow_horizontal == Control.GROW_DIRECTION_BEGIN
		and is_equal_approx(self_block.anchor_right, 1.0),
		"two independent corners, so neither shoves the other")
	_ok("control hints are gone", _hud.get_node_or_null("Self/ControlsLabel") == null)


func _check_colours() -> void:
	_ok("your team is blue", _hud.TEAM_BLUE.b > _hud.TEAM_BLUE.r)
	_ok("the enemy is red", _hud.ENEMY_RED.r > _hud.ENEMY_RED.g)
	_ok("your squad is green", _hud.SQUAD_GREEN.g > _hud.SQUAD_GREEN.r
		and _hud.SQUAD_GREEN.g > _hud.SQUAD_GREEN.b)
	_ok("the ticket counters use team and enemy colours",
		_hud._mine_count.get_theme_color("font_color") == _hud.TEAM_BLUE
		and _hud._their_count.get_theme_color("font_color") == _hud.ENEMY_RED)
	_ok("health is green", _hud._health_bar.colour == _hud.SQUAD_GREEN)


func _check_tickets() -> void:
	_gs.is_active = true
	_gs.roster.clear()
	_gs.handle_slot_request(1, 0)
	_gc.roster.from_array(_gs.roster.to_array())
	_gc.my_team = 1
	_gc.tickets = {1: 25, 2: 10}
	_hud._refresh_tickets()
	_ok("your ticket count is shown", _hud._mine_count.text == "25", _hud._mine_count.text)
	_ok("their ticket count is shown", _hud._their_count.text == "10", _hud._their_count.text)
	_ok("a full bar means full tickets", is_equal_approx(_hud._mine_bar.fraction, 1.0))
	_ok("the bar shrinks with the count",
		is_equal_approx(_hud._their_bar.fraction, 10.0 / 25.0),
		"%.2f" % _hud._their_bar.fraction)

	_gc.tickets = {1: 0, 2: 10}
	_hud._refresh_tickets()
	_ok("an empty bar means no tickets", is_zero_approx(_hud._mine_bar.fraction))


func _check_callsigns() -> void:
	_ok("slots carry placeholder callsigns", Roster.callsign(0) != Roster.callsign(1),
		"%s, %s" % [Roster.callsign(0), Roster.callsign(1)])
	_ok("there is a callsign for every slot",
		Roster.CALLSIGNS.size() == Roster.SLOT_COUNT,
		"%d names for %d slots" % [Roster.CALLSIGNS.size(), Roster.SLOT_COUNT])
	_ok("a squad row exists for each squadmate",
		_hud._squad_rows.size() == Roster.SQUAD_SIZE - 1,
		"%d rows" % _hud._squad_rows.size())


func _check_ping_rules() -> void:
	_gs.roster.clear()
	_gs.handle_slot_request(1, 0)
	_gs.handle_slot_request(2, 1)
	_gs.handle_slot_request(3, 8)
	_gc.roster.from_array(_gs.roster.to_array())
	_gc.my_team = 1
	_gc._peer_id = 1
	_gc.gunshots.clear()

	_gc.note_gunshot(Vector3(5, 0, 5), 1)
	_ok("your own shots do not ping", _gc.gunshots.is_empty())

	_gc.note_gunshot(Vector3(5, 0, 5), 2)
	_ok("a teammate firing does not ping", _gc.gunshots.is_empty(),
		"only enemies are revealed")

	_gc.note_gunshot(Vector3(9, 0, 9), 3)
	_ok("an enemy firing pings the map", _gc.gunshots.size() == 1)
	_ok("the ping records where the shot came from",
		(_gc.gunshots[0]["position"] as Vector3).is_equal_approx(Vector3(9, 0, 9)))

	_gc._age_gunshots(_gc.GUNSHOT_FADE_SECONDS * 0.5)
	_ok("a ping survives while it fades", _gc.gunshots.size() == 1)
	_gc._age_gunshots(_gc.GUNSHOT_FADE_SECONDS)
	_ok("a ping expires", _gc.gunshots.is_empty(),
		"a position at a moment, not a tracked enemy")


func _check_minimap() -> void:
	var map: Minimap = _hud.get_node_or_null("Situation/Minimap")
	_ok("the minimap is in the situation corner", map != null)
	_ok("it is drawn, not a second camera on the world",
		map.find_children("*", "SubViewport", true, false).is_empty()
		and map.find_children("*", "Camera3D", true, false).is_empty(),
		"a rendered view would hand out enemy positions by construction")

	var origin := Vector3(100.0, 0.0, 100.0)
	_ok("your own position sits at the centre",
		map.to_map(origin, origin).is_equal_approx(map.centre()))
	var north := map.to_map(origin + Vector3(0.0, 0.0, -50.0), origin)
	_ok("north is up", north.y < map.centre().y, "%.1f" % north.y)
	var east := map.to_map(origin + Vector3(50.0, 0.0, 0.0), origin)
	_ok("east is right", east.x > map.centre().x)
	_ok("distant things fall off the map",
		not map.on_map(map.to_map(origin + Vector3(0.0, 0.0, -400.0), origin)))
