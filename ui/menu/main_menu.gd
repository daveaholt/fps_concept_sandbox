extends Control

var _address: LineEdit
var _status: Label
var _buttons: VBoxContainer
var _host_button: Button
var _join_button: Button
var _dismissed: bool = false


func _ready() -> void:
	if NetCli.has_explicit_mode():
		queue_free()
		return
	_build()
	GameClient.connection_state_changed.connect(_on_connection_state)
	if GameClient.sampler != null:
		GameClient.sampler.release_mouse()


func _build() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var dim := ColorRect.new()
	dim.color = Color(0.04, 0.05, 0.07, 0.96)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(dim)

	_buttons = VBoxContainer.new()
	_buttons.set_anchors_preset(Control.PRESET_CENTER)
	_buttons.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_buttons.grow_vertical = Control.GROW_DIRECTION_BOTH
	_buttons.add_theme_constant_override("separation", 14)
	add_child(_buttons)

	var title := Label.new()
	title.text = "FPS CONCEPT SANDBOX"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_buttons.add_child(title)

	_host_button = Button.new()
	_host_button.text = "HOST"
	_host_button.custom_minimum_size = Vector2(260, 46)
	_host_button.focus_mode = Control.FOCUS_NONE
	_host_button.pressed.connect(_on_host)
	_buttons.add_child(_host_button)

	var join_row := HBoxContainer.new()
	join_row.add_theme_constant_override("separation", 8)
	_buttons.add_child(join_row)

	_join_button = Button.new()
	_join_button.text = "JOIN"
	_join_button.custom_minimum_size = Vector2(120, 46)
	_join_button.focus_mode = Control.FOCUS_NONE
	_join_button.pressed.connect(_on_join)
	join_row.add_child(_join_button)

	_address = LineEdit.new()
	_address.text = NetCli.get_connect_address()
	_address.custom_minimum_size = Vector2(132, 46)
	join_row.add_child(_address)

	var quit := Button.new()
	quit.text = "QUIT"
	quit.custom_minimum_size = Vector2(260, 46)
	quit.focus_mode = Control.FOCUS_NONE
	quit.pressed.connect(_on_quit)
	_buttons.add_child(quit)

	_status = Label.new()
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_buttons.add_child(_status)


func _on_host() -> void:
	_status.text = "starting server ..."
	GameServer.begin_hosting(NetCli.get_port(), NetCli.Mode.HOST)
	if not GameServer.is_active:
		_status.text = "could not listen on udp/%d — another instance running?" % NetCli.get_port()
		return
	GameClient.begin(NetCli.Mode.HOST)
	_dismiss()


func _on_join() -> void:
	var address := _address.text.strip_edges()
	if address == "":
		_status.text = "enter an address first"
		return
	_status.text = "connecting to %s ..." % address
	_set_busy(true)
	GameClient.begin(NetCli.Mode.CLIENT, address, NetCli.get_port())


func _set_busy(busy: bool) -> void:
	_host_button.disabled = busy
	_join_button.disabled = busy


func _on_connection_state(state: int) -> void:
	if _dismissed:
		return
	if state == GameClient.State.CONNECTED:
		_dismiss()
	elif state == GameClient.State.FAILED:
		_status.text = "could not reach %s — wrong address, no server, or firewalled" 			% _address.text.strip_edges()
		_set_busy(false)
		GameClient.abandon_connection()


func _on_quit() -> void:
	get_tree().quit()


func _dismiss() -> void:
	_dismissed = true
	visible = false
	set_process(false)
