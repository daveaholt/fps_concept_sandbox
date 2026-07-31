extends Control

const SLOT_MIN_WIDTH := 190
const SLOT_HEIGHT := 40

var _slot_buttons: Array[Button] = []
var _start_button: Button
var _status: Label
var _name_field: LineEdit


func _ready() -> void:
	EventBus.roster_changed.connect(_refresh)
	_build()
	_refresh()
	set_process(true)


func _build() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var dim := ColorRect.new()
	dim.color = Color(0.05, 0.06, 0.08, 0.88)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(dim)

	var root_box := VBoxContainer.new()
	root_box.set_anchors_preset(Control.PRESET_CENTER)
	root_box.grow_horizontal = Control.GROW_DIRECTION_BOTH
	root_box.grow_vertical = Control.GROW_DIRECTION_BOTH
	root_box.add_theme_constant_override("separation", 18)
	add_child(root_box)

	var title := Label.new()
	title.text = "CHOOSE A SLOT"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root_box.add_child(title)

	var name_row := HBoxContainer.new()
	name_row.alignment = BoxContainer.ALIGNMENT_CENTER
	name_row.add_theme_constant_override("separation", 10)
	root_box.add_child(name_row)

	var name_label := Label.new()
	name_label.text = "CALLSIGN"
	name_row.add_child(name_label)

	_name_field = LineEdit.new()
	_name_field.max_length = Roster.NAME_MAX_LENGTH
	_name_field.custom_minimum_size = Vector2(200, 38)
	_name_field.placeholder_text = "leave blank for a default"
	name_row.add_child(_name_field)

	var teams := HBoxContainer.new()
	teams.add_theme_constant_override("separation", 40)
	root_box.add_child(teams)

	for team in [1, 2]:
		var team_box := VBoxContainer.new()
		team_box.add_theme_constant_override("separation", 10)
		teams.add_child(team_box)

		var team_label := Label.new()
		team_label.text = "TEAM %d" % team
		team_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		team_box.add_child(team_label)

		var squads := HBoxContainer.new()
		squads.add_theme_constant_override("separation", 14)
		team_box.add_child(squads)

		for squad in range((team - 1) * 2, (team - 1) * 2 + 2):
			squads.add_child(_build_squad(squad))

	_status = Label.new()
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root_box.add_child(_status)

	_start_button = Button.new()
	_start_button.text = "START"
	_start_button.custom_minimum_size = Vector2(220, 46)
	_start_button.focus_mode = Control.FOCUS_NONE
	_start_button.pressed.connect(_on_start)
	root_box.add_child(_start_button)


func _build_squad(squad: int) -> VBoxContainer:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)

	var heading := Label.new()
	heading.text = Roster.squad_name(squad).to_upper()
	heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	heading.add_theme_color_override("font_color", Roster.squad_colour(squad))
	box.add_child(heading)

	for seat in Roster.SQUAD_SIZE:
		var slot := squad * Roster.SQUAD_SIZE + seat
		var button := Button.new()
		button.custom_minimum_size = Vector2(SLOT_MIN_WIDTH, SLOT_HEIGHT)
		button.focus_mode = Control.FOCUS_NONE
		button.pressed.connect(_on_slot_pressed.bind(slot))
		box.add_child(button)
		_slot_buttons.append(button)
	return box


func _on_slot_pressed(slot: int) -> void:
	GameClient.request_slot(slot, _name_field.text)


func _on_start() -> void:
	GameClient.request_start()


func _process(_delta: float) -> void:
	var want := GameClient.is_active and (GameClient.phase == GameServer.Phase.LOBBY
		or GameClient.my_slot() < 0)
	if visible != want:
		visible = want
		if want and GameClient.sampler != null:
			GameClient.sampler.release_mouse()


func _refresh() -> void:
	var mine := GameClient.my_slot()
	for slot in _slot_buttons.size():
		var button := _slot_buttons[slot]
		var occupant := GameClient.roster.occupant(slot)
		var squad := Roster.squad_of_slot(slot)
		if occupant == 0:
			button.text = "— empty —"
			button.disabled = false
		elif occupant == GameClient.get_peer_id():
			button.text = "%s (you)" % GameClient.roster.name_of_slot(slot)
			button.disabled = true
		else:
			button.text = GameClient.roster.name_of_slot(slot)
			button.disabled = true
		button.add_theme_color_override("font_color",
			Roster.squad_colour(squad) if occupant != 0 else Color(0.55, 0.58, 0.62))

	var filled := GameClient.roster.occupied_count()
	if mine < 0 and GameClient.phase == GameServer.Phase.PLAYING:
		_status.text = "match in progress — pick a slot to drop in"
	elif mine < 0:
		_status.text = "%d in the lobby — pick a slot to join" % filled
	else:
		_status.text = "%s squad, team %d — %d in the lobby, empty slots stay empty" % [
			Roster.squad_name(Roster.squad_of_slot(mine)),
			Roster.team_of_slot(mine), filled]
	var in_lobby := GameClient.phase == GameServer.Phase.LOBBY
	_start_button.visible = in_lobby and GameClient.is_host()
	_start_button.disabled = mine < 0
	if in_lobby and not GameClient.is_host():
		_status.text += "
waiting for the host to start"
