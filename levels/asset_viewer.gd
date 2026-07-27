extends Node3D

@export var orbit_speed: float = 0.008
@export var pan_speed: float = 0.0025
@export var zoom_step: float = 1.15
@export var min_distance: float = 0.5
@export var max_distance: float = 60.0

@onready var _subject: Node3D = $Subject
@onready var _ghosts: Node3D = $CollisionGhosts
@onready var _pivot: Node3D = $OrbitPivot
@onready var _camera: Camera3D = $OrbitPivot/Camera
@onready var _ghost_toggle: CheckBox = $UI/Panel/GhostToggle

var _distance: float = 6.0
var _yaw: float = 0.6
var _pitch: float = -0.45
var _orbiting: bool = false
var _panning: bool = false

var _ghost_material: StandardMaterial3D


func _ready() -> void:
	_ghost_material = StandardMaterial3D.new()
	_ghost_material.albedo_color = Color(0.2, 1.0, 0.45, 0.35)
	_ghost_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_ghost_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_ghost_material.cull_mode = BaseMaterial3D.CULL_DISABLED

	_ghost_toggle.toggled.connect(_on_ghosts_toggled)
	_apply_camera()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		match event.button_index:
			MOUSE_BUTTON_LEFT:
				_orbiting = event.pressed
			MOUSE_BUTTON_MIDDLE:
				_panning = event.pressed
			MOUSE_BUTTON_WHEEL_UP:
				if event.pressed:
					_distance = clampf(_distance / zoom_step, min_distance, max_distance)
					_apply_camera()
			MOUSE_BUTTON_WHEEL_DOWN:
				if event.pressed:
					_distance = clampf(_distance * zoom_step, min_distance, max_distance)
					_apply_camera()
	elif event is InputEventMouseMotion:
		if _orbiting:
			_yaw -= event.relative.x * orbit_speed
			_pitch = clampf(_pitch - event.relative.y * orbit_speed, -1.45, 1.45)
			_apply_camera()
		elif _panning:
			var right := _pivot.global_transform.basis.x
			var up := _pivot.global_transform.basis.y
			_pivot.position -= (right * event.relative.x - up * event.relative.y) * pan_speed * _distance
	elif event.is_action_pressed("ui_home"):
		_frame_subject()


func _apply_camera() -> void:
	_pivot.rotation = Vector3(_pitch, _yaw, 0.0)
	_camera.position = Vector3(0.0, 0.0, _distance)


func _frame_subject() -> void:
	var aabb := _subject_aabb()
	if aabb.size == Vector3.ZERO:
		_pivot.position = Vector3(0.0, 1.0, 0.0)
		_distance = 6.0
	else:
		_pivot.position = aabb.get_center()
		_distance = clampf(aabb.size.length() * 1.4, min_distance, max_distance)
	_apply_camera()


func _subject_aabb() -> AABB:
	var result := AABB()
	var first := true
	for node in _walk(_subject):
		if node is VisualInstance3D:
			var world: AABB = node.global_transform * (node as VisualInstance3D).get_aabb()
			if first:
				result = world
				first = false
			else:
				result = result.merge(world)
	return result


func _on_ghosts_toggled(pressed: bool) -> void:
	for child in _ghosts.get_children():
		child.queue_free()
	if not pressed:
		return

	var count := 0
	for node in _walk(_subject):
		if node is CollisionShape3D:
			var shape_node := node as CollisionShape3D
			if shape_node.shape == null:
				continue
			var ghost := MeshInstance3D.new()
			ghost.mesh = shape_node.shape.get_debug_mesh()
			ghost.material_override = _ghost_material
			_ghosts.add_child(ghost)
			ghost.global_transform = shape_node.global_transform
			count += 1
	if count == 0:
		push_warning("[asset_viewer] no CollisionShape3D found under Subject")


func _walk(root: Node) -> Array[Node]:
	var out: Array[Node] = []
	var stack: Array[Node] = [root]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		out.append(node)
		for child in node.get_children():
			stack.append(child)
	return out
