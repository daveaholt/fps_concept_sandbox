class_name InteractionScanner
extends Node

const ENTRY_GROUP := "vehicle_entry"

@export var fallback_radius: float = 2.0

var _last_prompt: String = ""


func _physics_process(_delta: float) -> void:
	var entity: Node = GameClient.my_entity
	if entity == null or not entity.has_method("get_interact_target"):
		_emit("")
		return

	var target := _resolve(entity.get_interact_target())
	if target == null:
		target = _overlap_fallback(entity)

	_emit("Enter %s [E]" % target.name if target != null else "")


func _resolve(hit: Node) -> Node:
	var node := hit
	while node != null:
		if node.is_in_group(ENTRY_GROUP):
			return node
		node = node.get_parent()
	return null


func _overlap_fallback(entity: Node) -> Node:
	if not entity is Node3D:
		return null
	var space := (entity as Node3D).get_world_3d().direct_space_state
	var shape := SphereShape3D.new()
	shape.radius = fallback_radius

	var params := PhysicsShapeQueryParameters3D.new()
	params.shape = shape
	params.transform = Transform3D(Basis(), (entity as Node3D).global_position + Vector3.UP)
	params.collision_mask = 1 << 4
	params.collide_with_areas = true
	params.collide_with_bodies = false

	for hit in space.intersect_shape(params, 4):
		var found := _resolve(hit.get("collider"))
		if found != null:
			return found
	return null


func _emit(text: String) -> void:
	if text == _last_prompt:
		return
	_last_prompt = text
	EventBus.interaction_prompt.emit(text)
