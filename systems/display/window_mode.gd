class_name WindowMode
extends Node


func _ready() -> void:
	set_process_unhandled_input(not _is_headless())


func is_fullscreen() -> bool:
	var mode := DisplayServer.window_get_mode()
	return mode == DisplayServer.WINDOW_MODE_FULLSCREEN \
		or mode == DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN


func set_fullscreen(enabled: bool) -> bool:
	if _is_headless():
		return false

	var target := DisplayServer.WINDOW_MODE_FULLSCREEN if enabled \
		else DisplayServer.WINDOW_MODE_WINDOWED
	DisplayServer.window_set_mode(target)
	if DisplayServer.window_get_mode() == target:
		return true

	push_warning("[display] window manager refused %s. A game embedded in the editor only allows Windowed — set Editor Settings > Run > Window Placement > Game Embed Mode to 'Make Game Workspace Floating', or run the project standalone."
		% ["fullscreen" if enabled else "windowed"])
	return false


func toggle() -> bool:
	return set_fullscreen(not is_fullscreen())


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_fullscreen"):
		toggle()
		get_viewport().set_input_as_handled()


func _is_headless() -> bool:
	return DisplayServer.get_name() == "headless"
