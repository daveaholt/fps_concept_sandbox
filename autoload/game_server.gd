extends Node

const PLAYER_SCENE_PATH := "res://entities/player/player.tscn"
const RESPAWN_DELAY := 2.0
const MAX_BUFFERED_COMMANDS := 16
const ENTER_RANGE := 4.0
const SPAWN_SPREAD := 2.2

enum Phase { LOBBY, PLAYING, RESULT }

const START_TICKETS := 25
const RESULT_SECONDS := 8.0

signal server_started(port: int)
signal peer_joined(peer_id: int)
signal peer_left(peer_id: int)
signal possession_granted(peer_id: int, entity: Node)
signal roster_changed()
signal phase_changed(phase: int)

var is_active: bool = false
var tick: int = 0
var phase: Phase = Phase.LOBBY
var roster := Roster.new()
var tickets := {1: START_TICKETS, 2: START_TICKETS}
var winning_team: int = 0

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
var _vehicles: Array = []


func _ready() -> void:
	if NetCli.is_tool_run() or not NetCli.has_explicit_mode():
		return
	var mode := NetCli.get_mode()
	if mode == NetCli.Mode.SERVER or mode == NetCli.Mode.HOST:
		begin_hosting(NetCli.get_port(), mode)


func begin_hosting(port: int, mode: NetCli.Mode) -> void:
	_start(port, mode)
	if not is_active:
		return
	if NetCli.has_explicit_mode():
		phase = Phase.PLAYING
		if mode == NetCli.Mode.HOST:
			roster.assign(1, roster.first_free_slot())
		phase_changed.emit(phase)
		_broadcast_roster()


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
	ballistics.spawn(origin, direction, params_id, peer_id, view_delay,
		roster.team_of(peer_id))
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


func register_vehicle(vehicle: Node) -> void:
	if not _vehicles.has(vehicle):
		_vehicles.append(vehicle)
		if vehicle.has_signal("fired"):
			vehicle.fired.connect(_on_vehicle_fired.bind(vehicle))
	if ballistics != null:
		ballistics.register_target(vehicle)


func _on_vehicle_fired(origin: Vector3, direction: Vector3, params_id: int, vehicle: Node) -> void:
	if ballistics == null:
		return
	var peer_id: int = vehicle.owner_peer
	var view_delay := NetCli.INTERP_DELAY_MS * 0.001 + get_peer_rtt(peer_id) * 0.5
	ballistics.spawn(origin, direction, params_id, peer_id, view_delay,
		roster.team_of(peer_id))
	if get_peer_count() > 0 and multiplayer.multiplayer_peer != null:
		GameClient.spawn_tracer.rpc(origin, direction, params_id, peer_id)


func get_vehicles() -> Array:
	return _vehicles


func _find_vehicle(vehicle_name: String) -> Node:
	for vehicle in _vehicles:
		if is_instance_valid(vehicle) and vehicle.name == vehicle_name:
			return vehicle
	return null


@rpc("any_peer", "call_remote", "reliable")
func request_enter_rpc(vehicle_name: String) -> void:
	if is_active:
		handle_enter_request(multiplayer.get_remote_sender_id(), _find_vehicle(vehicle_name))


@rpc("any_peer", "call_remote", "reliable")
func request_exit_rpc() -> void:
	if is_active:
		handle_exit_request(multiplayer.get_remote_sender_id())


@rpc("any_peer", "call_remote", "reliable")
func request_slot(slot: int) -> void:
	if is_active:
		handle_slot_request(multiplayer.get_remote_sender_id(), slot)


func handle_slot_request(peer: int, slot: int) -> void:
	if not is_active:
		return
	if not roster.is_valid_slot(slot):
		push_warning("[server] REJECTED slot from peer %d: %d is not a slot" % [peer, slot])
		return
	if not roster.is_free(slot):
		push_warning("[server] REJECTED slot %d for peer %d: held by peer %d"
			% [slot, peer, roster.occupant(slot)])
		return
	if phase == Phase.PLAYING and roster.has_peer(peer):
		push_warning("[server] REJECTED slot from peer %d: cannot switch mid-match" % peer)
		return
	if not roster.assign(peer, slot):
		push_warning("[server] REJECTED slot %d for peer %d" % [slot, peer])
		return
	print("[server] peer %d took slot %d (%s, team %d)"
		% [peer, slot, Roster.squad_name(roster.squad_of(peer)), roster.team_of(peer)])
	_broadcast_roster()


@rpc("any_peer", "call_remote", "reliable")
func request_start() -> void:
	if is_active:
		handle_start_request(multiplayer.get_remote_sender_id())


func handle_start_request(peer: int) -> void:
	if not is_active or phase == Phase.PLAYING:
		return
	if not roster.has_peer(peer):
		push_warning("[server] REJECTED start from peer %d: holds no slot" % peer)
		return
	fill_with_bots()
	tickets = {1: START_TICKETS, 2: START_TICKETS}
	winning_team = 0
	phase = Phase.PLAYING
	print("[server] match started by peer %d with %d players"
		% [peer, roster.occupied_count()])
	phase_changed.emit(phase)
	_broadcast_roster()


func fill_with_bots() -> void:
	pass


func _spend_ticket(team: int) -> void:
	if phase != Phase.PLAYING or not tickets.has(team):
		return
	tickets[team] = maxi(int(tickets[team]) - 1, 0)
	print("[server] team %d down to %d tickets" % [team, tickets[team]])
	if int(tickets[team]) <= 0:
		_end_match(2 if team == 1 else 1)
	else:
		_broadcast_roster()


func _end_match(winner: int) -> void:
	winning_team = winner
	phase = Phase.RESULT
	print("[server] match over — team %d wins (%d v %d tickets)"
		% [winner, tickets.get(1, 0), tickets.get(2, 0)])
	phase_changed.emit(phase)
	_broadcast_roster()
	await get_tree().create_timer(RESULT_SECONDS).timeout
	_return_to_lobby()


func _return_to_lobby() -> void:
	if phase != Phase.RESULT:
		return
	for peer_id in _possession.keys():
		_release_peer(peer_id)
		possession_granted.emit(peer_id, null)
	tickets = {1: START_TICKETS, 2: START_TICKETS}
	winning_team = 0
	phase = Phase.LOBBY
	print("[server] back to the lobby with slots kept (%d players)"
		% roster.occupied_count())
	phase_changed.emit(phase)
	_broadcast_roster()


func team_of_peer(peer_id: int) -> int:
	return roster.team_of(peer_id)


func _broadcast_roster() -> void:
	roster_changed.emit()
	GameClient.apply_roster(roster.to_array(), int(phase), tickets, winning_team)
	if get_peer_count() > 0 and multiplayer.multiplayer_peer != null:
		GameClient.receive_roster.rpc(roster.to_array(), int(phase), tickets, winning_team)


func handle_enter_request(peer: int, vehicle: Node) -> void:
	if not is_active:
		return
	if vehicle == null or not is_instance_valid(vehicle):
		push_warning("[server] REJECTED enter from peer %d: unknown vehicle" % peer)
		return

	var occupant: Node = _possession.get(peer)
	if occupant == null:
		push_warning("[server] REJECTED enter from peer %d: peer is not deployed" % peer)
		return
	if occupant.is_in_group("vehicle"):
		push_warning("[server] REJECTED enter from peer %d: already in a vehicle" % peer)
		return
	if vehicle.is_occupied():
		push_warning("[server] REJECTED enter from peer %d: %s is occupied by peer %d"
			% [peer, vehicle.name, vehicle.owner_peer])
		return

	var distance: float = occupant.global_position.distance_to(vehicle.global_position)
	if distance > ENTER_RANGE:
		push_warning("[server] REJECTED enter from peer %d: %.1f m away, limit %.1f"
			% [peer, distance, ENTER_RANGE])
		return

	_release_entity(peer)
	vehicle.owner_peer = peer
	vehicle.team = roster.team_of(peer)
	_bind(peer, vehicle)
	print("[server] peer %d entered %s" % [peer, vehicle.name])


func handle_exit_request(peer: int) -> void:
	if not is_active:
		return
	var vehicle: Node = _possession.get(peer)
	if vehicle == null or not vehicle.is_in_group("vehicle"):
		push_warning("[server] REJECTED exit from peer %d: not in a vehicle" % peer)
		return
	if not vehicle.can_exit():
		push_warning("[server] REJECTED exit from peer %d: %s cannot be exited now"
			% [peer, vehicle.name])
		return

	var space := (vehicle as Node3D).get_world_3d().direct_space_state
	var exit_transform: Transform3D = vehicle.common().pick_exit_transform(space)
	vehicle.owner_peer = 0
	vehicle.team = Roster.UNALIGNED
	vehicle.unpossess()
	_possession.erase(peer)
	_inputs.erase(peer)

	var entity := _spawn_infantry(peer, exit_transform.origin, -exit_transform.basis.z)
	if entity != null:
		print("[server] peer %d exited %s at %v" % [peer, vehicle.name, exit_transform.origin])


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


func _release_entity(peer_id: int) -> void:
	var entity: Node = _possession.get(peer_id)
	if entity != null and is_instance_valid(entity) and not entity.is_in_group("vehicle"):
		if ballistics != null:
			ballistics.unregister_target(entity)
		entity.queue_free()
	_possession.erase(peer_id)


func _bind(peer_id: int, entity: Node) -> void:
	_possession[peer_id] = entity
	_last_processed[peer_id] = _last_processed.get(peer_id, 0)
	_starved[peer_id] = 0
	if peer_id != 1:
		GameClient.grant_possession.rpc_id(peer_id, entity.name)
	possession_granted.emit(peer_id, entity)


func _release_peer(peer_id: int) -> void:
	var entity: Node = _possession.get(peer_id)
	if entity != null and is_instance_valid(entity):
		if entity.is_in_group("vehicle"):
			entity.owner_peer = 0
			entity.team = Roster.UNALIGNED
			entity.unpossess()
		else:
			if ballistics != null:
				ballistics.unregister_target(entity)
			entity.queue_free()
	_possession.erase(peer_id)
	_inputs.erase(peer_id)
	_last_processed.erase(peer_id)
	_last_command.erase(peer_id)
	_starved.erase(peer_id)


@rpc("any_peer", "call_remote", "reliable")
func client_ready(auto_slot: bool = true) -> void:
	if is_active:
		client_ready_local(multiplayer.get_remote_sender_id(), auto_slot)


func client_ready_local(peer_id: int, auto_slot: bool = true) -> void:
	if auto_slot and phase == Phase.PLAYING and not roster.has_peer(peer_id):
		var free := roster.first_free_slot()
		if free >= 0:
			roster.assign(peer_id, free)
			print("[server] peer %d auto-assigned slot %d (%s)"
				% [peer_id, free, Roster.squad_name(roster.squad_of(peer_id))])
		else:
			push_warning("[server] peer %d joined a full board" % peer_id)
	_broadcast_roster()
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

	var entity := _spawn_infantry(peer_id, origin, -point.global_transform.basis.z)
	print("[server] peer %d deployed at %s %v (%d entities)"
		% [peer_id, point.display_name, origin, _possession.size()])
	return entity


func _spawn_infantry(peer_id: int, origin: Vector3, aim: Vector3) -> Node:
	if _player_scene == null:
		_player_scene = load(PLAYER_SCENE_PATH)
	if _player_scene == null or _spawn_root == null:
		return null

	var entity := _player_scene.instantiate()
	entity.team = roster.team_of(peer_id)
	entity.name = "Player_%d" % peer_id
	entity.owner_peer = peer_id
	entity.position = origin
	_spawn_root.add_child(entity, true)
	entity.state.position = origin
	entity.set_spawn_aim(aim)
	entity.died.connect(entity_died)
	entity.fired.connect(_on_entity_fired.bind(peer_id))
	if ballistics != null:
		ballistics.register_target(entity)

	_bind(peer_id, entity)
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
		if is_instance_valid(entity) and not entity.is_in_group("vehicle"):
			entities[entity.name] = entity.get_net_state()
	for vehicle in _vehicles:
		if is_instance_valid(vehicle):
			entities[vehicle.name] = vehicle.get_net_state()

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


static func blocks_damage(shooter_team: int, target_team: int) -> bool:
	return Roster.blocks_damage(shooter_team, target_team)


func entity_died(entity: Node) -> void:
	if not is_active or entity == null:
		return
	var peer_id: int = entity.owner_peer
	print("[server] %s died (peer %d) — awaiting redeploy" % [entity.name, peer_id])
	_spend_ticket(roster.team_of(peer_id))
	_release_peer(peer_id)
	possession_granted.emit(peer_id, null)
	if peer_id == 1:
		GameClient.on_killed()
	elif multiplayer.get_peers().has(peer_id):
		GameClient.on_killed.rpc_id(peer_id)


