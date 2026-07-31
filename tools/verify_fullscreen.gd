extends SceneTree

var _mode: WindowMode
var _frames := 0
var _results: Array[String] = []
var _failures := 0


func _initialize() -> void:
	root.add_child(load("res://levels/sandbox/sandbox.tscn").instantiate())

	var client := root.get_node_or_null("/root/GameClient")
	if client != null:
		client._start_local_systems()
		_mode = client.window
		print("  (via GameClient autoload)")
	if _mode == null:
		_mode = WindowMode.new()
		root.add_child(_mode)
		print("  (autoload absent in --script mode; WindowMode added directly under the real scene)")


func _process(_delta: float) -> bool:
	_frames += 1
	match _frames:
		5:
			_expect(false, "starts windowed")
			_ok(_mode.set_fullscreen(true), "set_fullscreen(true) reports success")
			_ok(_mode.set_fullscreen(false), "set_fullscreen(false) reports success")
			_press_f11()
		15:
			_expect(true, "F11 switched to fullscreen")
			_press_f11()
		25:
			_expect(false, "F11 switched back to windowed")
			print("\n%s  (%d failures)" % ["PASS" if _failures == 0 else "FAIL", _failures])
			quit(1 if _failures > 0 else 0)
			return true
	return false


func _ok(condition: bool, label: String) -> void:
	if condition:
		print("  ok   %s" % label)
	else:
		_failures += 1
		print("  FAIL %s" % label)


func _expect(fullscreen: bool, label: String) -> void:
	var actual := _mode.is_fullscreen()
	if actual == fullscreen:
		print("  ok   %s (window_mode=%d)" % [label, DisplayServer.window_get_mode()])
	else:
		_failures += 1
		print("  FAIL %s — expected fullscreen=%s, got %s (window_mode=%d)"
			% [label, fullscreen, actual, DisplayServer.window_get_mode()])


func _press_f11() -> void:
	var event := InputEventKey.new()
	event.device = -1
	event.keycode = KEY_F11
	event.physical_keycode = KEY_F11
	event.pressed = true
	Input.parse_input_event(event)
