class_name VehicleCommon
extends Node3D

const ENTRY_GROUP := "vehicle_entry"

@export var exit_clearance_radius: float = 0.5

var _entry_zone: Area3D
var _exit_point: Marker3D
var _exit_point_alt: Marker3D
var _shell_meshes: Array = []
var _shell_hidden: bool = false
var _shell_bounds := AABB()
var _tinted: Array[StandardMaterial3D] = []
var _base_albedo: Array[Color] = []
var _smoke: GPUParticles3D
var _shown_state: int = -1


func _ready() -> void:
	_entry_zone = get_node_or_null("EntryZone")
	_exit_point = get_node_or_null("ExitPoint")
	_exit_point_alt = get_node_or_null("ExitPointAlt")
	if _entry_zone != null:
		_entry_zone.add_to_group(ENTRY_GROUP)
	_collect_shell()
	_cache_materials()
	_build_smoke()


func _cache_materials() -> void:
	var vehicle := get_parent()
	if vehicle == null:
		return
	for mesh in vehicle.find_children("*", "MeshInstance3D", true, false):
		var source: Material = mesh.get_active_material(0)
		if source == null or not source is StandardMaterial3D:
			continue
		var copy: StandardMaterial3D = source.duplicate()
		mesh.material_override = copy
		_tinted.append(copy)
		_base_albedo.append(copy.albedo_color)


func _build_smoke() -> void:
	_smoke = GPUParticles3D.new()
	_smoke.name = "DamageSmoke"
	_smoke.emitting = false
	_smoke.amount = 20
	_smoke.lifetime = 2.4
	_smoke.local_coords = false
	_smoke.visibility_aabb = AABB(Vector3(-8.0, -2.0, -8.0), Vector3(16.0, 18.0, 16.0))

	var process := ParticleProcessMaterial.new()
	process.direction = Vector3.UP
	process.spread = 14.0
	process.initial_velocity_min = 1.1
	process.initial_velocity_max = 2.8
	process.gravity = Vector3(0.0, 1.2, 0.0)
	process.scale_min = 0.6
	process.scale_max = 1.8
	process.color = Color(0.09, 0.09, 0.1, 0.55)
	_smoke.process_material = process

	var puff := QuadMesh.new()
	puff.size = Vector2(1.3, 1.3)
	var material := StandardMaterial3D.new()
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	material.vertex_color_use_as_albedo = true
	material.albedo_color = Color(0.1, 0.1, 0.11, 0.6)
	puff.material = material
	_smoke.draw_pass_1 = puff

	add_child(_smoke)
	if _shell_bounds.size != Vector3.ZERO:
		_smoke.position = Vector3(_shell_bounds.get_center().x,
			_shell_bounds.position.y + _shell_bounds.size.y * 0.8,
			_shell_bounds.get_center().z)


func set_damage_state(state: int) -> void:
	if state == _shown_state:
		return
	_shown_state = state
	apply_damage_tint(state)
	if _smoke == null:
		return
	_smoke.emitting = state == VehicleDamage.State.DAMAGED 		or state == VehicleDamage.State.CRITICAL
	_smoke.amount = 34 if state == VehicleDamage.State.CRITICAL else 16


func smoking() -> bool:
	return _smoke != null and _smoke.emitting


func apply_damage_tint(state: int) -> void:
	var factor := VehicleDamage.tint(state)
	for i in _tinted.size():
		var base: Color = _base_albedo[i]
		var material: StandardMaterial3D = _tinted[i]
		material.albedo_color = Color(base.r * factor, base.g * factor, base.b * factor,
			base.a)


func tinted_material_count() -> int:
	return _tinted.size()


func _collect_shell() -> void:
	_shell_meshes = []
	var vehicle := get_parent() as Node3D
	if vehicle == null:
		return
	var inverse: Transform3D = vehicle.global_transform.affine_inverse()
	for node in vehicle.find_children("*", "VisualInstance3D", true, false):
		if not node.is_in_group(RenderLayers.SHELL_GROUP):
			continue
		_shell_meshes.append(node)
		var mesh: Mesh = node.mesh
		if mesh == null:
			continue
		var local: AABB = inverse * node.global_transform * mesh.get_aabb()
		_shell_bounds = local if _shell_meshes.size() == 1 else _shell_bounds.merge(local)


func encloses(global_point: Vector3) -> bool:
	if _shell_meshes.is_empty():
		return false
	var vehicle := get_parent() as Node3D
	if vehicle == null:
		return false
	return _shell_bounds.has_point(vehicle.to_local(global_point))


func shell_bounds() -> AABB:
	return _shell_bounds


func set_shell_hidden(hidden: bool) -> void:
	if hidden == _shell_hidden:
		return
	_shell_hidden = hidden
	var bits := RenderLayers.OWNER_HIDDEN if hidden else RenderLayers.WORLD_VISIBLE
	for node in _shell_meshes:
		node.layers = bits


func shell_mesh_count() -> int:
	return _shell_meshes.size()


func shell_hidden() -> bool:
	return _shell_hidden


func entry_radius() -> float:
	if _entry_zone == null:
		return 0.0
	var best := 0.0
	for shape in _entry_zone.find_children("*", "CollisionShape3D", true, false):
		var box := shape.shape as BoxShape3D
		if box == null:
			continue
		best = maxf(best, maxf(box.size.x, box.size.z) * 0.5)
	return best


func entry_zone() -> Area3D:
	return _entry_zone


func distance_to(point: Vector3) -> float:
	var owner_node := get_parent() as Node3D
	if owner_node == null:
		return INF
	return owner_node.global_position.distance_to(point)


func pick_exit_transform(space: PhysicsDirectSpaceState3D) -> Transform3D:
	var owner_node := get_parent() as Node3D
	if owner_node == null:
		return global_transform
	for candidate in [_exit_point, _exit_point_alt]:
		if candidate == null:
			continue
		if _is_clear(candidate.global_position, space):
			return candidate.global_transform
	return Transform3D(owner_node.global_transform.basis, _hull_top(owner_node))


func _hull_top(owner_node: Node3D) -> Vector3:
	return owner_node.global_position + Vector3.UP * 2.4


func _is_clear(point: Vector3, space: PhysicsDirectSpaceState3D) -> bool:
	if space == null:
		return true
	var shape := SphereShape3D.new()
	shape.radius = exit_clearance_radius
	var params := PhysicsShapeQueryParameters3D.new()
	params.shape = shape
	params.transform = Transform3D(Basis(), point + Vector3.UP * exit_clearance_radius)
	params.collision_mask = 1
	return space.intersect_shape(params, 1).is_empty()
