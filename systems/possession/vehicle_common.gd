class_name VehicleCommon
extends Node

const ENTRY_GROUP := "vehicle_entry"

@export var exit_clearance_radius: float = 0.5

var _entry_zone: Area3D
var _exit_point: Marker3D
var _exit_point_alt: Marker3D


func _ready() -> void:
	_entry_zone = get_node_or_null("EntryZone")
	_exit_point = get_node_or_null("ExitPoint")
	_exit_point_alt = get_node_or_null("ExitPointAlt")
	if _entry_zone != null:
		_entry_zone.add_to_group(ENTRY_GROUP)


func entry_zone() -> Area3D:
	return _entry_zone


func distance_to(point: Vector3) -> float:
	var owner_node := get_parent() as Node3D
	if owner_node == null:
		return INF
	return owner_node.global_position.distance_to(point)


func pick_exit_transform(space: PhysicsDirectSpaceState3D) -> Transform3D:
	var owner_node := get_parent() as Node3D
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
