class_name InteractionScanner
extends Node

const ENTRY_GROUP := "vehicle_entry"

@export var fallback_radius: float = 2.0

var _last_prompt: String = ""
var _interact_latch: bool = false
var _exit_latch: bool = false
var _target: Node = null


func _physics_process(_delta: float) -> void:
	var entity: Node = GameClient.my_entity
	if entity == null:
		_emit("")
		_target = null
		return

	if entity.is_in_group("vehicle"):
		_emit("%s — F to exit" % entity.get_display_name())
		_target = null
		_poll_exit()
		return

	if not entity.has_method("get_interact_target"):
		_emit("")
		return

	_target = _resolve(entity.get_interact_target())
	if _target == null:
		_target = _overlap_fallback(entity)

	_emit("Enter %s [E]" % _target.get_display_name() if _target != null else "")
	_poll_enter()


func can_poll() -> bool:
	return InputFocus.may_act(GameClient.sampler)


func _poll_enter() -> void:
	if not can_poll():
		_interact_latch = false
		return
	var pressed := Input.is_action_pressed("interact")
	if pressed and not _interact_latch and _target != null:
		GameClient.request_enter(_target)
	_interact_latch = pressed


func _poll_exit() -> void:
	if not can_poll():
		_exit_latch = false
		return
	var pressed := Input.is_action_pressed("exit_vehicle")
	if pressed and not _exit_latch:
		GameClient.request_exit()
	_exit_latch = pressed


func _resolve(hit: Node) -> Node:
	var node := hit
	while node != null:
		if node.is_in_group(ENTRY_GROUP):
			return _vehicle_root(node)
		node = node.get_parent()
	return null


func _vehicle_root(node: Node) -> Node:
	var current := node
	while current != null:
		if current.is_in_group("vehicle"):
			return current
		current = current.get_parent()
	return node


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
