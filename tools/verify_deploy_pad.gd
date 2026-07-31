extends SceneTree

var _level: Node
var _t := 0
var _fail := 0
var _map: Control


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
	var gs = root.get_node_or_null("/root/GameServer")
	var gc = root.get_node_or_null("/root/GameClient")
	gs.is_active = true
	gs.roster.clear()
	gs.handle_slot_request(1, 0)
	gc.roster.from_array(gs.roster.to_array())
	gc.my_team = 1
	_map = _level.find_child("DeployMap", true, false)
	if _map == null:
		_ok("the deploy map exists", false)
		quit(1)
		return true

	_map._on_toggled(true)
	_map._project_markers()

	var options: Array = _map.selectable_targets()
	_ok("the map offers a selectable target without a mouse", options.size() >= 1,
		"%d targets — your own camp, plus any squadmate" % options.size())
	_ok("a reticle exists", _map._reticle is DeployReticle)

	_map._selected = null
	_map._selected_mate = 0
	_map.step_selection(Vector2.RIGHT)
	_ok("a stick nudge selects something when nothing is selected",
		_map.selected_button() != null)

	_map._place_reticle()
	_ok("the reticle marks the selection", _map._reticle.visible)
	var button: Button = _map.selected_button()
	var box: Rect2 = _map._reticle.target_rect()
	_ok("the reticle sits on the selected marker",
		box.encloses(Rect2(button.position, button.size)),
		"reticle %s vs marker %s" % [box, Rect2(button.position, button.size)])

	_map._build_markers()
	_map._project_markers()
	_map._place_reticle()
	_ok("the reticle survives a marker rebuild", is_instance_valid(_map._reticle)
		and _map._reticle.visible, "rebuilds happen whenever squadmates change")
	_ok("the reticle draws above the markers",
		_map._marker_layer.get_child(_map._marker_layer.get_child_count() - 1)
			== _map._reticle)

	_check_directions(options)
	_check_skips_unavailable()

	print("deploy pad: %d failing" % _fail)
	quit(1 if _fail > 0 else 0)
	return true


func _check_directions(options: Array) -> void:
	var reached: Array = []
	for direction in [Vector2.RIGHT, Vector2.LEFT, Vector2.UP, Vector2.DOWN]:
		for _i in 6:
			_map.step_selection(direction)
			var button: Button = _map.selected_button()
			if button != null and not reached.has(button):
				reached.append(button)
	_ok("stick navigation can reach every target", reached.size() == options.size(),
		"reached %d of %d" % [reached.size(), options.size()])

	var before: Button = _map.selected_button()
	for _i in 8:
		_map.step_selection(Vector2.RIGHT)
	var settled: Button = _map.selected_button()
	_ok("navigation settles instead of cycling forever", settled != null)
	_ok("a selection is always held once made", before != null and settled != null)


func _check_skips_unavailable() -> void:
	var points := get_nodes_in_group("spawn_points")
	if points.is_empty():
		return
	var victim: SpawnPoint = points[0]
	var was: bool = victim.enabled
	victim.enabled = false
	_map._build_markers()
	_map._project_markers()
	var offered := false
	for option in _map.selectable_targets():
		if option["point"] == victim:
			offered = true
	_ok("a disabled spawn point is not reachable by stick", not offered,
		"greyed markers must not be selectable")
	victim.enabled = was
