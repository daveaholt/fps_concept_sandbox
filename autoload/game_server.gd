extends Node

const PLAYER_SCENE_PATH := "res://entities/player/player.tscn"
const RESPAWN_DELAY := 2.0
const MAX_BUFFERED_COMMANDS := 16
const SPAWN_SPREAD := 2.2

signal server_started(port: int)
signal peer_joined(peer_id: int)
signal peer_left(peer_id: int)
signal possession_granted(peer_id: int, entity: Node)

var is_active: bool = false
var tick: int = 0

var _port: int = 0
var _possession: Dictionary = {}
var _inputs: Dictionary = {}
var _last_processed: Dictionary = {}
var _last_command: Dictionary = {}
var _starved: Dictionary = {}
var _spawn_root: Node = null
var _default_spawn: SpawnPoint = null
var _player_scene: PackedScene = null
var ballistics: BallisticsManager = null


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


func register_level(spawn_root: Node, default_spawn: SpawnPoint,
		ballistics_manager: BallisticsManager = null) -> void:
	_spawn_root = spawn_root
	_default_spawn = default_spawn
	ballistics = ballistics_manager
	if ballistics != null:
		ballistics.authoritative = is_active


func get_peer_rtt(peer_id: int) -> float:
	if peer_id == 1 or multiplayer.multiplayer_peer == null:
		return 0.0
	var enet := multiplayer.multiplayer_peer as ENetMultiplayerPeer
	if enet == null:
		return 0.0
	var packet_peer := enet.get_peer(peer_id)
	if packet_peer == null:
		return 0.0
	return float(packet_peer.get_statistic(ENetPacketPeer.PEER_ROUND_TRIP_TIME)) * 0.001


func _on_entity_fired(origin: Vector3, direction: Vector3, params_id: int, peer_id: int) -> void:
	if ballistics == null:
		return
	var view_delay := NetCli.INTERP_DELAY_MS * 0.001 + get_peer_rtt(peer_id) * 0.5
	ballistics.spawn(origin, direction, params_id, peer_id, view_delay)
	if get_peer_count() > 0 and multiplayer.multiplayer_peer != null:
		GameClient.spawn_tracer.rpc(origin, direction, params_id, peer_id)


func get_port() -> int:
	return _port


func get_peer_count() -> int:
	if not is_active:
		return 0
	return multiplayer.get_peers().size()


func get_possessed(peer_id: int) -> Node:
	return _possession.get(peer_id)


func get_entity_count() -> int:
	return _possession.size()


func get_starvation(peer_id: int) -> int:
	return _starved.get(peer_id, 0)


func _on_peer_connected(peer_id: int) -> void:
	print("[server] peer %d connected (%d connected)" % [peer_id, get_peer_count()])
	peer_joined.emit(peer_id)


func _on_peer_disconnected(peer_id: int) -> void:
	_release_peer(peer_id)
	print("[server] peer %d disconnected (%d connected, %d entities)"
		% [peer_id, get_peer_count(), _possession.size()])
	peer_left.emit(peer_id)


func _release_peer(peer_id: int) -> void:
	var entity: Node = _possession.get(peer_id)
	if entity != null and is_instance_valid(entity):
		if ballistics != null:
			ballistics.unregister_target(entity)
		entity.queue_free()
	_possession.erase(peer_id)
	_inputs.erase(peer_id)
	_last_processed.erase(peer_id)
	_last_command.erase(peer_id)
	_starved.erase(peer_id)


@rpc("any_peer", "call_remote", "reliable")
func client_ready() -> void:
	if is_active:
		client_ready_local(multiplayer.get_remote_sender_id())


func client_ready_local(peer_id: int) -> void:
	print("[server] peer %d is ready and awaiting deployment" % peer_id)


func find_spawn_point(display_name: String) -> SpawnPoint:
	for node in get_tree().get_nodes_in_group("spawn_points"):
		if node is SpawnPoint and node.display_name == display_name:
			return node
	return null


@rpc("any_peer", "call_remote", "reliable")
func request_spawn_rpc(spawn_name: String) -> void:
	if not is_active:
		return
	handle_spawn_request(multiplayer.get_remote_sender_id(), find_spawn_point(spawn_name))


func handle_spawn_request(peer: int, spawn_point: SpawnPoint) -> void:
	if not is_active:
		return
	if _possession.has(peer):
		push_warning("[server] REJECTED spawn from peer %d: already deployed" % peer)
		return
	if spawn_point == null:
		push_warning("[server] REJECTED spawn from peer %d: unknown spawn point" % peer)
		return
	if not spawn_point.enabled:
		push_warning("[server] REJECTED spawn from peer %d: spawn point '%s' is disabled"
			% [peer, spawn_point.display_name])
		return
	deploy(peer, spawn_point)


func deploy(peer_id: int, spawn_point: SpawnPoint = null) -> Node:
	if not is_active or _spawn_root == null:
		return null
	if _possession.has(peer_id):
		return _possession[peer_id]

	var point := spawn_point if spawn_point != null else _default_spawn
	if point == null:
		push_error("[server] no spawn point available for peer %d" % peer_id)
		return null

	if _player_scene == null:
		_player_scene = load(PLAYER_SCENE_PATH)

	var slot := _possession.size()
	var angle := TAU * float(slot) / float(NetCli.MAX_PEERS)
	var offset := Vector3(cos(angle), 0.0, sin(angle)) * SPAWN_SPREAD if slot > 0 else Vector3.ZERO
	var origin := point.global_position + offset

	var entity := _player_scene.instantiate()
	entity.name = "Player_%d" % peer_id
	entity.owner_peer = peer_id
	entity.position = origin
	_spawn_root.add_child(entity, true)
	entity.state.position = origin
	entity.set_spawn_aim(-point.global_transform.basis.z)
	entity.died.connect(entity_died)
	entity.fired.connect(_on_entity_fired.bind(peer_id))
	if ballistics != null:
		ballistics.register_target(entity)

	_possession[peer_id] = entity
	_last_processed[peer_id] = 0
	_starved[peer_id] = 0
	print("[server] peer %d deployed at %s %v (%d entities)"
		% [peer_id, point.display_name, origin, _possession.size()])

	if peer_id != 1:
		GameClient.grant_possession.rpc_id(peer_id, entity.name)
	possession_granted.emit(peer_id, entity)
	return entity


@rpc("any_peer", "call_remote", "unreliable")
func receive_commands(bundle: Array) -> void:
	if not is_active:
		return
	_ingest(multiplayer.get_remote_sender_id(), bundle)


func submit_local_commands(peer_id: int, bundle: Array) -> void:
	_ingest(peer_id, bundle)


func _ingest(peer_id: int, bundle: Array) -> void:
	var entity: Node = _possession.get(peer_id)
	if entity == null or not is_instance_valid(entity):
		return
	if entity.owner_peer != peer_id:
		push_warning("[server] dropped commands from peer %d for an entity it does not own" % peer_id)
		return

	var queue: Array = _inputs.get(peer_id, [])
	var acked: int = _last_processed.get(peer_id, 0)

	for raw in bundle:
		var cmd := InputCommand.from_dict(raw)
		if cmd.tick <= acked:
			continue
		var duplicate := false
		for queued in queue:
			if queued.tick == cmd.tick:
				duplicate = true
				break
		if not duplicate:
			queue.append(cmd)

	queue.sort_custom(func(a, b): return a.tick < b.tick)
	while queue.size() > MAX_BUFFERED_COMMANDS:
		queue.pop_front()
	_inputs[peer_id] = queue


func _physics_process(_delta: float) -> void:
	if not is_active:
		return

	if tick % NetCli.SNAPSHOT_EVERY_TICKS == 0:
		_broadcast_snapshot()

	tick += 1
	_feed_commands()


func _feed_commands() -> void:
	for peer_id in _possession:
		var entity: Node = _possession[peer_id]
		if not is_instance_valid(entity):
			continue

		var queue: Array = _inputs.get(peer_id, [])
		var cmd: InputCommand = null
		if queue.is_empty():
			cmd = _last_command.get(peer_id)
			if cmd != null:
				_starved[peer_id] = _starved.get(peer_id, 0) + 1
		else:
			cmd = queue.pop_front()
			_inputs[peer_id] = queue
			_last_processed[peer_id] = cmd.tick
			_last_command[peer_id] = cmd

		if cmd != null:
			entity.push_command(cmd)


func _broadcast_snapshot() -> void:
	if _possession.is_empty() and get_peer_count() == 0:
		return

	var entities := {}
	for peer_id in _possession:
		var entity: Node = _possession[peer_id]
		if is_instance_valid(entity):
			entities[entity.name] = entity.get_net_state()

	var snapshot := {"tick": tick, "entities": entities, "acks": _last_processed}
	if get_peer_count() > 0 and multiplayer.multiplayer_peer != null:
		GameClient.receive_snapshot.rpc(snapshot)


@rpc("any_peer", "call_remote", "reliable")
func request_dev_damage(amount: float) -> void:
	if is_active:
		apply_dev_damage(multiplayer.get_remote_sender_id(), clampf(amount, 0.0, 100.0))


func apply_dev_damage(peer_id: int, amount: float) -> void:
	var entity: Node = _possession.get(peer_id)
	if entity != null and is_instance_valid(entity):
		entity.apply_damage(amount)


func entity_died(entity: Node) -> void:
	if not is_active or entity == null:
		return
	var peer_id: int = entity.owner_peer
	print("[server] %s died (peer %d) — awaiting redeploy" % [entity.name, peer_id])
	_release_peer(peer_id)
	possession_granted.emit(peer_id, null)
	if peer_id == 1:
		GameClient.on_killed()
	elif multiplayer.get_peers().has(peer_id):
		GameClient.on_killed.rpc_id(peer_id)


func handle_enter_request(peer: int, vehicle: Node) -> void:
	push_warning("[server] handle_enter_request(peer %d, %s) is a stub until M5"
		% [peer, vehicle.name if vehicle else "<null>"])


func handle_exit_request(peer: int) -> void:
	push_warning("[server] handle_exit_request(peer %d) is a stub until M5" % peer)
