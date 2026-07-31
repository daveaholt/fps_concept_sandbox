extends SceneTree

var _level: Node
var _t := 0
var _fail := 0
var _menu: Control
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
	_gc = root.get_node_or_null("/root/GameClient")
	_menu = _level.find_child("MainMenu", true, false)
	if _menu == null:
		_ok("the main menu exists", false)
		quit(1)
		return true

	_ok("the menu is up before any connection", _menu.visible)
	_ok("both routes are offered", _menu._host_button != null
		and _menu._join_button != null and not _menu._host_button.disabled
		and not _menu._join_button.disabled,
		"there is no discovery, so neither can know in advance")

	_menu._set_busy(true)
	_ok("attempting a connection locks both buttons",
		_menu._host_button.disabled and _menu._join_button.disabled,
		"or a second press stacks a second attempt")

	_menu._on_connection_state(_gc.State.FAILED)
	_ok("a failed join keeps the menu up", _menu.visible and not _menu._dismissed,
		"this is the bug: it used to dismiss on the press and never come back")
	_ok("and says why", _menu._status.text.contains("could not reach"),
		_menu._status.text)
	_ok("and offers a retry", not _menu._host_button.disabled
		and not _menu._join_button.disabled)
	_ok("a failed attempt is torn down so a retry can bind",
		not _gc.is_active and _gc.state == _gc.State.OFFLINE,
		"state %d" % _gc.state)

	_menu._on_connection_state(_gc.State.CONNECTED)
	_ok("the menu leaves only once connected", not _menu.visible and _menu._dismissed)

	print("menu: %d failing" % _fail)
	quit(1 if _fail > 0 else 0)
	return true
