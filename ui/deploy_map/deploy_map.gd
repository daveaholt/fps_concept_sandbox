extends Control

const MARKER_SIZE := Vector2(150, 34)
const UNAVAILABLE := Color(0.45, 0.47, 0.5)
const SELECTED := Color(0.4, 1.0, 0.6)
const KIND_ICON := {"infantry": "▲", "tank": "■", "heli": "✕"}
const KIND_LABEL := {"infantry": "", "tank": "TANK ", "heli": "HELI "}

@export var ortho_size: float = 230.0
@export var camera_height: float = 150.0

var _selected: SpawnPoint = null
var _selected_mate: int = 0
var _markers: Dictionary = {}
var _mate_markers: Dictionary = {}
var _built_targets: Array = []

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
	_deploy_button.pressed.connect(_on_deploy_pressed)
	EventBus.deploy_map_toggled.connect(_on_toggled)


func _on_toggled(open: bool) -> void:
	visible = open
	_viewport.render_target_update_mode = \
		SubViewport.UPDATE_ALWAYS if open else SubViewport.UPDATE_DISABLED
	if open:
		_build_markers()
		_refresh()


func _unhandled_input(event: InputEvent) -> void:
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
		button.disabled = not point.enabled
		button.pressed.connect(_on_marker_pressed.bind(point))
		_marker_layer.add_child(button)
		_markers[point] = button

	_built_targets = GameClient.squadmates_on_map()
	for mate in _built_targets:
		var button := Button.new()
		button.custom_minimum_size = MARKER_SIZE
		button.size = MARKER_SIZE
		button.pressed.connect(_on_mate_pressed.bind(mate))
		_marker_layer.add_child(button)
		_mate_markers[mate] = button

	if _selected == null or not _markers.has(_selected):
		_selected = _markers.keys()[0] if not _markers.is_empty() else null


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
	_refresh()


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
	if alive:
		_footer.text = "Recon — deploying while alive is disabled.  M or Esc to return."
	elif _selected_mate != 0:
		_footer.text = "Selected: squadmate %d   —   Deploy or press Enter" % _selected_mate
	elif _selected != null:
		_footer.text = "Selected: %s   —   Deploy or press Enter" % _selected.display_name
	else:
		_footer.text = "No spawn point available."

	for point in _markers:
		var button: Button = _markers[point]
		if not point.enabled:
			button.modulate = UNAVAILABLE
		else:
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
