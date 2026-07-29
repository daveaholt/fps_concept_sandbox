class_name InputHints
extends RefCounted

const PAD_DEADZONE := 0.5

const PAD_BUTTONS := {
	JOY_BUTTON_A: "A",
	JOY_BUTTON_B: "B",
	JOY_BUTTON_X: "X",
	JOY_BUTTON_Y: "Y",
	JOY_BUTTON_LEFT_SHOULDER: "LB",
	JOY_BUTTON_RIGHT_SHOULDER: "RB",
	JOY_BUTTON_LEFT_STICK: "LS",
	JOY_BUTTON_RIGHT_STICK: "RS",
	JOY_BUTTON_BACK: "BACK",
	JOY_BUTTON_START: "START",
	JOY_BUTTON_DPAD_UP: "DPAD UP",
	JOY_BUTTON_DPAD_DOWN: "DPAD DOWN",
	JOY_BUTTON_DPAD_LEFT: "DPAD LEFT",
	JOY_BUTTON_DPAD_RIGHT: "DPAD RIGHT",
}

const PAD_AXES := {
	JOY_AXIS_TRIGGER_LEFT: "LT",
	JOY_AXIS_TRIGGER_RIGHT: "RT",
	JOY_AXIS_LEFT_X: "LS",
	JOY_AXIS_LEFT_Y: "LS",
	JOY_AXIS_RIGHT_X: "RS",
	JOY_AXIS_RIGHT_Y: "RS",
}

const MOUSE_BUTTONS := {
	MOUSE_BUTTON_LEFT: "LMB",
	MOUSE_BUTTON_RIGHT: "RMB",
	MOUSE_BUTTON_MIDDLE: "MMB",
}

static var pad: bool = false


static func note(event: InputEvent) -> void:
	if event is InputEventJoypadButton:
		if (event as InputEventJoypadButton).pressed:
			pad = true
	elif event is InputEventJoypadMotion:
		if absf((event as InputEventJoypadMotion).axis_value) > PAD_DEADZONE:
			pad = true
	elif event is InputEventKey or event is InputEventMouseButton:
		pad = false


static func label(action: String) -> String:
	if not InputMap.has_action(action):
		return action.to_upper()
	var fallback := ""
	for event in InputMap.action_get_events(action):
		var name := _label_for(event)
		if name == "":
			continue
		if _is_pad(event) == pad:
			return name
		if fallback == "":
			fallback = name
	return fallback if fallback != "" else action.to_upper()


static func _is_pad(event: InputEvent) -> bool:
	return event is InputEventJoypadButton or event is InputEventJoypadMotion


static func _label_for(event: InputEvent) -> String:
	if event is InputEventJoypadButton:
		return PAD_BUTTONS.get((event as InputEventJoypadButton).button_index, "")
	if event is InputEventJoypadMotion:
		return PAD_AXES.get((event as InputEventJoypadMotion).axis, "")
	if event is InputEventKey:
		var key := event as InputEventKey
		var code := key.physical_keycode if key.physical_keycode != 0 else key.keycode
		return OS.get_keycode_string(code)
	if event is InputEventMouseButton:
		return MOUSE_BUTTONS.get((event as InputEventMouseButton).button_index, "")
	return ""
