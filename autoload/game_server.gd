extends Node

const PLAYER_SCENE_PATH := "res://entities/player/player.tscn"
const RESPAWN_DELAY := 2.0

signal server_started(port: int)
signal peer_joined(peer_id: int)
signal peer_left(peer_id: int)
signal possession_granted(peer_id: int, entity: Node)

var is_active: bool = false

var _port: int = 0
var _possession: Dictionary = {}
var _spawn_root: Node = null
var _default_spawn: SpawnPoint = null
var _player_scene: PackedScene = null


func _ready() -> void:
	if NetCli.is_tool_run():
		return
	var mode := NetCli.get_mode()
	if mode == NetCli.Mode.SERVER or mode == NetCli.Mode.HOST:
		_start(NetCli.get_port(), mode)


func _start(port: int, mode: NetCli.Mode) -> void:
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_server(port, NetCli.MAX_PEERS)
	if err != OK:
		push_error("[server] could not listen on port %d (error %d) — is another instance running?" % [port, err])
		return

	multiplayer.multiplayer_peer = peer
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)

	is_active = true
	_port = port
	print("[server] listening on udp/%d as peer %d (%s mode, max %d peers)"
		% [port, multiplayer.get_unique_id(), NetCli.mode_name(mode), NetCli.MAX_PEERS])
	server_started.emit(port)


func register_level(spawn_root: Node, default_spawn: SpawnPoint) -> void:
	_spawn_root = spawn_root
	_default_spawn = default_spawn


func get_port() -> int:
	return _port


func get_peer_count() -> int:
	if not is_active:
		return 0
	return multiplayer.get_peers().size()


func get_possessed(peer_id: int) -> Node:
	return _possession.get(peer_id)


func _on_peer_connected(peer_id: int) -> void:
	print("[server] peer %d connected (%d connected)" % [peer_id, get_peer_count()])
	peer_joined.emit(peer_id)


func _on_peer_disconnected(peer_id: int) -> void:
	var entity: Node = _possession.get(peer_id)
	if entity != null and is_instance_valid(entity):
		entity.queue_free()
	_possession.erase(peer_id)
	print("[server] peer %d disconnected (%d connected)" % [peer_id, get_peer_count()])
	peer_left.emit(peer_id)


func spawn_infantry(peer_id: int, spawn_point: SpawnPoint) -> Node:
	if not is_active or _spawn_root == null:
		return null
	if _possession.has(peer_id):
		push_warning("[server] peer %d already has an entity; spawn refused" % peer_id)
		return null

	var point := spawn_point if spawn_point != null else _default_spawn
	if point == null:
		push_error("[server] no spawn point available for peer %d" % peer_id)
		return null

	if _player_scene == null:
		_player_scene = load(PLAYER_SCENE_PATH)
	if _player_scene == null:
		push_error("[server] player scene missing at %s" % PLAYER_SCENE_PATH)
		return null

	var entity := _player_scene.instantiate()
	entity.name = "Player_%d" % peer_id
	entity.owner_peer = peer_id
	entity.position = point.global_position
	_spawn_root.add_child(entity, true)
	entity.state.position = point.global_position

	_possession[peer_id] = entity
	entity.died.connect(_on_entity_died)
	print("[server] peer %d deployed at %s %v" % [peer_id, point.display_name, point.global_position])
	possession_granted.emit(peer_id, entity)
	return entity


func submit_command(peer_id: int, cmd: InputCommand) -> void:
	var entity: Node = _possession.get(peer_id)
	if entity == null or not is_instance_valid(entity):
		return
	if entity.owner_peer != peer_id:
		push_warning("[server] dropped command from peer %d for an entity it does not own" % peer_id)
		return
	entity.push_command(cmd)


func apply_dev_damage(peer_id: int, amount: float) -> void:
	var entity: Node = _possession.get(peer_id)
	if entity == null or not is_instance_valid(entity):
		return
	entity.apply_damage(amount)


func _on_entity_died(entity: Node) -> void:
	entity_died(entity)


func entity_died(entity: Node) -> void:
	if not is_active or entity == null:
		return
	var peer_id: int = entity.owner_peer
	print("[server] %s died (peer %d)" % [entity.name, peer_id])
	_possession.erase(peer_id)
	possession_granted.emit(peer_id, null)
	entity.queue_free()
	_respawn_after_delay(peer_id)


func _respawn_after_delay(peer_id: int) -> void:
	await get_tree().create_timer(RESPAWN_DELAY).timeout
	if not is_active:
		return
	if peer_id != 1 and not multiplayer.get_peers().has(peer_id):
		return
	spawn_infantry(peer_id, _default_spawn)


func handle_spawn_request(peer: int, spawn_point: SpawnPoint) -> void:
	push_warning("[server] handle_spawn_request(peer %d, %s) is a stub until M4"
		% [peer, spawn_point.display_name if spawn_point else "<null>"])


func handle_enter_request(peer: int, vehicle: Node) -> void:
	push_warning("[server] handle_enter_request(peer %d, %s) is a stub until M5"
		% [peer, vehicle.name if vehicle else "<null>"])


func handle_exit_request(peer: int) -> void:
	push_warning("[server] handle_exit_request(peer %d) is a stub until M5" % peer)
