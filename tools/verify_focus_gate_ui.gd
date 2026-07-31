extends SceneTree

class FakeSampler:
	extends InputSampler
	var focused: bool = true
	func window_focused() -> bool:
		return focused
	func release_mouse() -> void:
		pass
	func capture_mouse() -> void:
		pass

var _level: Node
var _t := 0
var _fail := 0
var _map: Control
var _fake: FakeSampler
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

	var gs = root.get_node_or_null("/root/GameServer")
	gs.is_active = true
	gs.roster.clear()
	gs.handle_slot_request(1, 0)
	_map = _level.find_child("DeployMap", true, false)
	_fake = FakeSampler.new()
	root.add_child(_fake)
	_gc = root.get_node_or_null("/root/GameClient")
	_gc.sampler = _fake
	_gc.roster.from_array(gs.roster.to_array())
	_gc.my_team = 1

	_map._on_toggled(true)
	_map._project_markers()

	_fake.focused = true
	_ok("a focused window may act", _map.may_act())
	_fake.focused = false
	_ok("an unfocused window may not act", not _map.may_act())

	_check_navigation_gate()
	_check_toggle_gate()
	_check_buttons_refuse_focus()

	print("focus gate: %d failing" % _fail)
	quit(1 if _fail > 0 else 0)
	return true


func _check_navigation_gate() -> void:
	_fake.focused = true
	_map._selected = null
	_map._selected_mate = 0
	_map.step_selection(Vector2.RIGHT)
	var chosen: Button = _map.selected_button()
	_ok("navigation works in the focused window", chosen != null)

	_fake.focused = false
	_map._nav_latched = false
	_map._selected = null
	_map._selected_mate = 0
	_map._poll_navigation()
	_ok("stick navigation is ignored while unfocused",
		_map.selected_button() == null,
		"the pad is polled process-wide, so both windows see it")


func _check_toggle_gate() -> void:
	var event := InputEventAction.new()
	event.action = "toggle_deploy_map"
	event.pressed = true
	_gc.phase = 1
	_gc.deploy_map_open = false

	_fake.focused = false
	var before: bool = _gc.deploy_map_open
	_map._unhandled_input(event)
	_ok("a pad button press is ignored while unfocused",
		_gc.deploy_map_open == before,
		"this is the bug that made one controller drive both windows")

	_fake.focused = true
	_map._unhandled_input(event)
	_ok("the same press works in the focused window",
		_gc.deploy_map_open != before)


func _check_buttons_refuse_focus() -> void:
	var checked := 0
	for button in _map._marker_layer.get_children():
		if not button is Button:
			continue
		checked += 1
		if button.focus_mode != Control.FOCUS_NONE:
			_ok("marker %s refuses keyboard focus" % button.name, false)
			return
	_ok("no marker takes UI focus", checked > 0,
		"%d markers — ui_accept is bound to pad A, so a focused button "
		% checked + "would fire in every window at once")
	_ok("the deploy button refuses UI focus",
		_map._deploy_button.focus_mode == Control.FOCUS_NONE)
