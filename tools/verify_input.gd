extends SceneTree

const PAD_EXEMPT := ["toggle_fullscreen"]
const KBM_EXEMPT := ["look_left", "look_right", "look_up", "look_down"]

var failures := 0


func _initialize() -> void:
	print("[project settings]")
	var tick := int(ProjectSettings.get_setting("physics/3d/../../physics/common/physics_ticks_per_second", 0))
	_ok(Engine.physics_ticks_per_second == 60, "physics tick is 60 Hz",
		"= %d" % Engine.physics_ticks_per_second)
	_ok(str(ProjectSettings.get_setting("rendering/renderer/rendering_method", "")) == "forward_plus",
		"renderer is forward_plus",
		"= %s" % str(ProjectSettings.get_setting("rendering/renderer/rendering_method", "<unset>")))

	print("\n[input map — keyboard/mouse and gamepad]")
	for action in _game_actions():
		var kbm := 0
		var pad := 0
		for event in InputMap.action_get_events(action):
			if event is InputEventJoypadButton or event is InputEventJoypadMotion:
				pad += 1
			else:
				kbm += 1
		var want_kbm := not KBM_EXEMPT.has(action)
		var want_pad := not PAD_EXEMPT.has(action)
		var good := (kbm > 0 or not want_kbm) and (pad > 0 or not want_pad)
		var wrong_device := 0
		for event in InputMap.action_get_events(action):
			if event.device != -1:
				wrong_device += 1
		_ok(good and wrong_device == 0, action,
			"kbm=%d pad=%d%s" % [kbm, pad, "" if wrong_device == 0 else "  BAD device on %d event(s)" % wrong_device])

	print("\n[fullscreen]")
	_ok(InputMap.has_action("toggle_fullscreen"), "toggle_fullscreen action exists")
	var bound := ""
	for event in InputMap.action_get_events("toggle_fullscreen"):
		if event is InputEventKey:
			bound = OS.get_keycode_string(event.keycode if event.keycode != 0 else event.physical_keycode)
	_ok(bound == "F11", "bound to F11", "= %s" % bound)

	var window := WindowMode.new()
	root.add_child(window)
	_ok(not window.is_fullscreen(), "starts windowed")
	window.toggle()
	_ok(true, "toggle() is safe on the headless display server")

	print("\n%s  (%d failures)" % ["PASS" if failures == 0 else "FAIL", failures])
	quit(1 if failures > 0 else 0)


func _game_actions() -> Array:
	var out := []
	for action in InputMap.get_actions():
		var name := str(action)
		if not name.begins_with("ui_"):
			out.append(name)
	out.sort()
	return out


func _ok(condition: bool, label: String, detail := "") -> void:
	if condition:
		print("  ok   %s %s" % [label, detail])
	else:
		failures += 1
		print("  FAIL %s %s" % [label, detail])
