class_name Nameplates
extends Node

const FRIEND_RANGE := 220.0
const ENEMY_RANGE := 70.0
const WORLD_MASK := 1


func _process(_delta: float) -> void:
	var tree := get_tree()
	if tree == null:
		return
	var camera := tree.root.get_viewport().get_camera_3d()
	for body in tree.get_nodes_in_group("infantry"):
		_refresh(body, camera)


func _refresh(body: Node, camera: Camera3D) -> void:
	var plate: Label3D = body.get_node_or_null("Nameplate")
	if plate == null:
		return
	var peer: int = body.owner_peer
	if camera == null or peer == 0 or peer == GameClient.get_peer_id():
		plate.visible = false
		return

	var relation := relationship(peer)
	var distance: float = camera.global_position.distance_to(
		(body as Node3D).global_position)
	var hostile := Relations.is_enemy(relation)

	if distance > (ENEMY_RANGE if hostile else FRIEND_RANGE):
		plate.visible = false
		return
	if hostile and not has_line_of_sight(camera, body):
		plate.visible = false
		return

	plate.text = GameClient.roster.name_of(peer)
	plate.modulate = relation
	plate.no_depth_test = not hostile
	plate.visible = true


func relationship(peer: int) -> Color:
	return Relations.colour_for(GameClient.roster, GameClient.get_peer_id(),
		GameClient.my_team, peer)


func has_line_of_sight(camera: Camera3D, body: Node) -> bool:
	var space := camera.get_world_3d().direct_space_state
	var target: Vector3 = (body as Node3D).global_position + Vector3.UP * 1.4
	var query := PhysicsRayQueryParameters3D.create(camera.global_position, target)
	query.collision_mask = WORLD_MASK
	return space.intersect_ray(query).is_empty()
