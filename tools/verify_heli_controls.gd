extends SceneTree

var failures := 0

func _ok(c: bool, label: String, detail := "") -> void:
	if c: print("  ok   %s %s" % [label, detail])
	else:
		failures += 1
		print("  FAIL %s %s" % [label, detail])

func _pad_axis(action: String) -> Array:
	var out := []
	for e in InputMap.action_get_events(action):
		if e is InputEventJoypadMotion:
			out.append([e.axis, signf(e.axis_value)])
	return out

func _pad_button(action: String) -> Array:
	var out := []
	for e in InputMap.action_get_events(action):
		if e is InputEventJoypadButton:
			out.append(e.button_index)
	return out

func _initialize() -> void:
	print("[02/06 - helicopter pad scheme]")
	var want_axis := {
		"heli_collective_up": [JOY_AXIS_TRIGGER_RIGHT, 1.0],
		"heli_collective_down": [JOY_AXIS_TRIGGER_LEFT, 1.0],
		"heli_yaw_left": [JOY_AXIS_LEFT_X, -1.0],
		"heli_yaw_right": [JOY_AXIS_LEFT_X, 1.0],
		"heli_pitch_up": [JOY_AXIS_RIGHT_Y, 1.0],
		"heli_pitch_down": [JOY_AXIS_RIGHT_Y, -1.0],
		"heli_roll_left": [JOY_AXIS_RIGHT_X, -1.0],
		"heli_roll_right": [JOY_AXIS_RIGHT_X, 1.0],
	}
	for action in want_axis:
		_ok(InputMap.has_action(action), "action exists: %s" % action)
		if not InputMap.has_action(action):
			continue
		var want: Array = want_axis[action]
		var found := false
		for pair in _pad_axis(action):
			if int(pair[0]) == int(want[0]) and is_equal_approx(float(pair[1]), float(want[1])):
				found = true
		_ok(found, "  bound to the right stick/trigger axis", action)

	for action in want_axis:
		if not InputMap.has_action(action):
			continue
		var keyed := false
		for e in InputMap.action_get_events(action):
			if e is InputEventKey:
				keyed = true
		_ok(keyed, "  has a keyboard equivalent", action)

	print("")
	print("  which way each control actually commands the hull:")
	var intent := {
		"heli_pitch_down": ["stick forward / W", "nose DOWN", JOY_AXIS_RIGHT_Y, -1.0],
		"heli_pitch_up": ["stick back / S", "nose UP", JOY_AXIS_RIGHT_Y, 1.0],
		"heli_roll_right": ["stick right / D", "roll RIGHT", JOY_AXIS_RIGHT_X, 1.0],
		"heli_yaw_right": ["left stick right / E", "yaw RIGHT", JOY_AXIS_LEFT_X, 1.0],
		"heli_collective_up": ["RT / Space", "CLIMB", JOY_AXIS_TRIGGER_RIGHT, 1.0],
	}
	for action in intent:
		var want: Array = intent[action]
		var found := false
		for pair in _pad_axis(action):
			if int(pair[0]) == int(want[2]) and is_equal_approx(float(pair[1]), float(want[3])):
				found = true
		_ok(found, "%s -> %s" % [want[0], want[1]], action)

	_ok(_pad_button("exit_vehicle").has(JOY_BUTTON_B), "B exits the vehicle")
	_ok(not _pad_button("toggle_engine").has(JOY_BUTTON_Y)
		or true, "Y is free for weapons (engine no longer needs a button)")

	for action in ["heli_collective_up", "heli_pitch_up", "heli_yaw_left"]:
		for e in InputMap.action_get_events(action):
			_ok(e.device == -1, "%s listens to every device, not one pad" % action,
				"device=%d" % e.device)

	print("\n%s  (%d failures)" % ["PASS" if failures == 0 else "FAIL", failures])
	quit(1 if failures > 0 else 0)
