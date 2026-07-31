extends Control

const MARKER_SIZE := Vector2(150, 34)
const UNAVAILABLE := Color(0.45, 0.47, 0.5)
const SELECTED := Color(0.4, 1.0, 0.6)
const KIND_ICON := {"infantry": "▲", "tank": "■", "heli": "✕"}
const KIND_LABEL := {"infantry": "", "tank": "TANK ", "heli": "HELI "}

const NAV_DEADZONE := 0.5
const NAV_ALIGNMENT := 0.35

@export var ortho_size: float = 230.0
@export var camera_height: float = 150.0

var _selected: SpawnPoint = null
var _selected_mate: int = 0
var _markers: Dictionary = {}
var _mate_markers: Dictionary = {}
var _built_targets: Array = []
var _reticle: DeployReticle
var _nav_latched: bool = false

@onready var _viewport: SubViewport = $ViewportBox/Viewport
@onready var _camera: Camera3D = $ViewportBox/Viewport/TopDownCamera
@onready var _marker_layer: Control = $MarkerLayer
@onready var _header: Label = $Header
@onready var _footer: Label = $Footer
@onready var _deploy_button: Button = $DeployButton


func _ready() -> void:
	visible = false
	_viewport.world_3d = get_viewport().world_3d
	_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	_camera.size = ortho_size
	_camera.position = Vector3(0.0, camera_height, 0.0)
	_camera.rotation_degrees = Vector3(-90.0, 0.0, 0.0)
	_camera.current = true
	_reticle = DeployReticle.new()
	_reticle.name = "Reticle"
	_marker_layer.add_child(_reticle)
	_deploy_button.focus_mode = Control.FOCUS_NONE
	_deploy_button.pressed.connect(_on_deploy_pressed)
	EventBus.deploy_map_toggled.connect(_on_toggled)


func _on_toggled(open: bool) -> void:
	visible = open
	_viewport.render_target_update_mode = \
		SubViewport.UPDATE_ALWAYS if open else SubViewport.UPDATE_DISABLED
	if open:
		_build_markers()
		_refresh()


func may_act() -> bool:
	return InputFocus.may_act(GameClient.sampler)


func _unhandled_input(event: InputEvent) -> void:
	if not may_act():
		return
	if event.is_action_pressed("toggle_deploy_map"):
		GameClient.request_deploy_map(not GameClient.deploy_map_open)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_cancel") and GameClient.deploy_map_open:
		GameClient.request_deploy_map(false)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("deploy_confirm") and GameClient.deploy_map_open:
		_on_deploy_pressed()
		get_viewport().set_input_as_handled()


func _build_markers() -> void:
	for child in _marker_layer.get_children():
		if child == _reticle:
			continue
		child.queue_free()
	_markers.clear()
	_mate_markers.clear()

	for node in get_tree().get_nodes_in_group("spawn_points"):
		if not node is SpawnPoint:
			continue
		var point: SpawnPoint = node
		var button := Button.new()
		button.text = point.display_name
		button.custom_minimum_size = MARKER_SIZE
		button.size = MARKER_SIZE
		button.disabled = not point.available_to(GameClient.my_team)
		button.focus_mode = Control.FOCUS_NONE
		button.pressed.connect(_on_marker_pressed.bind(point))
		_marker_layer.add_child(button)
		_markers[point] = button

	_built_targets = GameClient.squadmates_on_map()
	for mate in _built_targets:
		var button := Button.new()
		button.custom_minimum_size = MARKER_SIZE
		button.size = MARKER_SIZE
		button.focus_mode = Control.FOCUS_NONE
		button.pressed.connect(_on_mate_pressed.bind(mate))
		_marker_layer.add_child(button)
		_mate_markers[mate] = button

	if _selected == null or not _markers.has(_selected):
		_selected = _markers.keys()[0] if not _markers.is_empty() else null
	if is_instance_valid(_reticle):
		_marker_layer.move_child(_reticle, -1)


func _refusal(point: SpawnPoint) -> String:
	if not point.enabled:
		return "  (closed)"
	if point.is_contested():
		return "  (contested)"
	return "  (enemy)"


func _on_marker_pressed(point: SpawnPoint) -> void:
	_selected = point
	_selected_mate = 0
	_refresh()


func _on_mate_pressed(mate: int) -> void:
	var info: Dictionary = GameClient.squadmate_marker_info(mate)
	if info.is_empty() or not bool(info["available"]):
		return
	_selected_mate = mate
	_selected = null
	_refresh()


func _on_deploy_pressed() -> void:
	if GameClient.is_alive():
		return
	if _selected_mate != 0:
		GameClient.request_squad_spawn(_selected_mate)
	elif _selected != null:
		GameClient.request_spawn(_selected)


func _process(_delta: float) -> void:
	if not visible:
		return
	if GameClient.squadmates_on_map() != _built_targets:
		_build_markers()
	_project_markers()
	_poll_navigation()
	_refresh()
	_place_reticle()


func nav_vector() -> Vector2:
	var stick := Vector2(
		Input.get_action_strength("look_right") - Input.get_action_strength("look_left"),
		Input.get_action_strength("look_down") - Input.get_action_strength("look_up"))
	if stick.length() >= NAV_DEADZONE:
		return stick
	return Vector2(
		Input.get_action_strength("move_right") - Input.get_action_strength("move_left"),
		Input.get_action_strength("move_back") - Input.get_action_strength("move_forward"))


func _poll_navigation() -> void:
	if not may_act():
		_nav_latched = false
		return
	var nav := nav_vector()
	if nav.length() < NAV_DEADZONE:
		_nav_latched = false
		return
	if _nav_latched:
		return
	_nav_latched = true
	step_selection(nav.normalized())


func selectable_targets() -> Array:
	var out: Array = []
	for point in _markers:
		if not is_instance_valid(point) or not point.available_to(GameClient.my_team):
			continue
		var button: Button = _markers[point]
		out.append({"centre": button.position + button.size * 0.5,
			"point": point, "mate": 0})
	for mate in _mate_markers:
		var button: Button = _mate_markers[mate]
		if not button.visible or button.disabled:
			continue
		out.append({"centre": button.position + button.size * 0.5,
			"point": null, "mate": mate})
	return out


func selected_button() -> Button:
	if _selected_mate != 0 and _mate_markers.has(_selected_mate):
		return _mate_markers[_selected_mate]
	if _selected != null and _markers.has(_selected):
		return _markers[_selected]
	return null


func step_selection(direction: Vector2) -> void:
	var options := selectable_targets()
	if options.is_empty():
		return
	var current := selected_button()
	if current == null:
		_apply_selection(options[0])
		return

	var from: Vector2 = current.position + current.size * 0.5
	var best: Dictionary = {}
	var best_score := 0.0
	for option in options:
		var delta: Vector2 = (option["centre"] as Vector2) - from
		if delta.length() < 1.0:
			continue
		if delta.normalized().dot(direction) < NAV_ALIGNMENT:
			continue
		var score: float = delta.normalized().dot(direction) / delta.length()
		if best.is_empty() or score > best_score:
			best = option
			best_score = score
	if not best.is_empty():
		_apply_selection(best)


func _apply_selection(option: Dictionary) -> void:
	_selected = option["point"]
	_selected_mate = int(option["mate"])
	_refresh()


func _place_reticle() -> void:
	if not is_instance_valid(_reticle):
		return
	var button := selected_button()
	if button == null or not button.visible:
		_reticle.clear_target()
		return
	_reticle.aim_at(Rect2(button.position, button.size))


func _project_markers() -> void:
	var view_size := _viewport.size
	if view_size.x <= 0 or view_size.y <= 0:
		return
	var scale := _marker_layer.size / Vector2(view_size)

	for point in _markers:
		if not is_instance_valid(point):
			continue
		var projected := _camera.unproject_position(point.global_position)
		var button: Button = _markers[point]
		button.position = projected * scale - button.size * 0.5

	for mate in _mate_markers:
		var body := GameClient.squadmate_entity(mate)
		var button: Button = _mate_markers[mate]
		if body == null or not is_instance_valid(body):
			button.visible = false
			continue
		button.visible = true
		button.position = _camera.unproject_position(body.global_position) * scale 			- button.size * 0.5


func _refresh() -> void:
	var alive := GameClient.is_alive()
	_header.text = "KILLED IN ACTION" if GameClient.was_killed else "DEPLOY"
	_header.modulate = Color(1, 0.45, 0.4) if GameClient.was_killed else Color(1, 1, 1)

	_deploy_button.disabled = alive or (_selected == null and _selected_mate == 0)
	var confirm := InputHints.label("deploy_confirm")
	var move := "stick" if InputHints.pad else "mouse"
	if alive:
		_footer.text = "Recon — deploying while alive is disabled.  %s to return." 			% InputHints.label("toggle_deploy_map")
	elif _selected_mate != 0:
		_footer.text = "Selected: squadmate %d   —   %s to deploy, %s to choose" 			% [_selected_mate, confirm, move]
	elif _selected != null:
		_footer.text = "Selected: %s   —   %s to deploy, %s to choose" 			% [_selected.display_name, confirm, move]
	else:
		_footer.text = "No spawn point available."

	for point in _markers:
		var button: Button = _markers[point]
		var open_to_me: bool = point.available_to(GameClient.my_team)
		button.disabled = not open_to_me
		if not open_to_me:
			button.text = "%s%s" % [point.display_name, _refusal(point)]
			button.modulate = UNAVAILABLE
		else:
			button.text = point.display_name
			button.modulate = SELECTED if point == _selected else Color(1, 1, 1)

	var squad_colour := Roster.squad_colour(Roster.squad_of_slot(GameClient.my_slot()))
	for mate in _mate_markers:
		var button: Button = _mate_markers[mate]
		var info: Dictionary = GameClient.squadmate_marker_info(mate)
		if info.is_empty():
			button.visible = false
			continue
		var kind: String = info["kind"]
		var free: bool = bool(info["available"])
		button.text = "%s %sPlayer %d%s" % [KIND_ICON.get(kind, "▲"),
			KIND_LABEL.get(kind, ""), mate, "" if free else "  (full)"]
		button.disabled = not free
		if not free:
			button.modulate = UNAVAILABLE
		elif mate == _selected_mate:
			button.modulate = SELECTED
		else:
			button.modulate = squad_colour
