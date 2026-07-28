class_name WindowMode
extends Node


func _ready() -> void:
	set_process_unhandled_input(not _is_headless())


func is_fullscreen() -> bool:
	var mode := DisplayServer.window_get_mode()
	return mode == DisplayServer.WINDOW_MODE_FULLSCREEN \
		or mode == DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN


func set_fullscreen(enabled: bool) -> void:
	if _is_headless():
		return
	DisplayServer.window_set_mode(
		DisplayServer.WINDOW_MODE_FULLSCREEN if enabled else DisplayServer.WINDOW_MODE_WINDOWED)


func toggle() -> void:
	set_fullscreen(not is_fullscreen())


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_fullscreen"):
		toggle()
		get_viewport().set_input_as_handled()


func _is_headless() -> bool:
	return DisplayServer.get_name() == "headless"
