extends Node

signal connection_state_changed(state: State)

enum State {
	OFFLINE,
	CONNECTING,
	CONNECTED,
	FAILED,
}

const CONNECT_TIMEOUT_SEC := 8.0

var my_entity: Node = null
var is_active: bool = false
var state: State = State.OFFLINE

var sampler: InputSampler = null
var window: WindowMode = null
var shim: NetShim = null
var buffer := SnapshotBuffer.new()
var prediction := PredictionBuffer.new()
var ballistics: BallisticsManager = null

var _address: String = ""
var _port: int = 0
var _connecting_for: float = 0.0
var _outbox: Array[InputCommand] = []
var _players_root: Node = null
var _pending_entity_name: String = ""
var _acked_tick: int = 0
var _log_countdown: float = 1.0
var _uptime: float = 0.0
var _peer_id: int = 0
var deploy_map_open: bool = false
var was_killed: bool = false
var _pending_auth: Dictionary = {}
var _pending_auth_tick: int = 0


func _ready() -> void:
	if NetCli.is_tool_run() or not NetCli.has_explicit_mode():
		return
	begin(NetCli.get_mode())


func begin(mode: NetCli.Mode, address := "", port := 0) -> void:
	match mode:
		NetCli.Mode.CLIENT:
			_start_local_systems()
			_connect_to(address if address != "" else NetCli.get_connect_address(),
				port if port > 0 else NetCli.get_port())
		NetCli.Mode.HOST:
			_start_local_systems()
			is_active = true
			_address = "local"
			_port = GameServer.get_port()
			_set_state(State.CONNECTED if GameServer.is_active else State.FAILED)
			GameServer.possession_granted.connect(_on_possession_granted)
			print("[client] host mode — local player is peer %d" % multiplayer.get_unique_id())
		NetCli.Mode.SERVER:
			print("[client] dedicated server — no local client")


func _start_local_systems() -> void:
	shim = NetShim.new()
	shim.name = "NetShim"
	add_child(shim)
	shim.configure_from_cli()

	sampler = InputSampler.new()
	sampler.name = "InputSampler"
	add_child(sampler)

	var scanner := InteractionScanner.new()
	scanner.name = "InteractionScanner"
	add_child(scanner)

	window = WindowMode.new()
	window.name = "WindowMode"
	add_child(window)


func register_level(players_root: Node, ballistics_manager: BallisticsManager = null) -> void:
	_players_root = players_root
	ballistics = ballistics_manager
	if not is_active:
		return
	var auto_slot := NetCli.has_explicit_mode()
	if GameServer.is_active:
		GameServer.client_ready_local(get_peer_id(), auto_slot)
	elif can_rpc():
		GameServer.client_ready.rpc_id(1, auto_slot)
	set_deploy_map(true)


func _connect_to(address: String, port: int) -> void:
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_client(address, port)
	if err != OK:
		push_error("[client] could not create client peer for %s:%d (error %d)" % [address, port, err])
		_set_state(State.FAILED)
		return

	multiplayer.multiplayer_peer = peer
	multiplayer.connected_to_server.connect(_on_connected)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)

	is_active = true
	_address = address
	_port = port
	_set_state(State.CONNECTING)
	GameServer.refresh_entity_authority()
	print("[client] connecting to %s:%d ..." % [address, port])


var roster := Roster.new()
var phase: int = 0
var my_team: int = Roster.UNALIGNED
var tickets: Dictionary = {}
var winning_team: int = 0


func is_predicting() -> bool:
	if my_entity == null or not is_instance_valid(my_entity):
		return false
	if not my_entity.has_method("is_predicted"):
		return false
	return my_entity.is_predicted()


func _physics_process(delta: float) -> void:
	if sampler == null or my_entity == null or not is_instance_valid(my_entity):
		return

	_reconcile(delta)
	var cmd := sampler.build_command(delta)
	if is_predicting():
		_predict(cmd, delta)
	elif my_entity.has_method("set_local_aim"):
		my_entity.set_local_aim(cmd.aim)
	send_command(cmd)


func _predict(cmd: InputCommand, delta: float) -> void:
	var entity := my_entity
	var shots_before: int = entity.state.shots_fired
	var space := (entity as Node3D).get_world_3d().direct_space_state
	var next := InfantrySim.simulate(entity.state, cmd, entity.tuning, space, delta)
	entity.set_predicted_state(next, cmd.aim)
	prediction.push(cmd.tick, cmd, next.clone())
	if next.shots_fired != shots_before and ballistics != null:
		ballistics.spawn(entity.muzzle_origin(), cmd.aim, next.weapon_index, get_peer_id(),
			0.0, my_team)


func _reconcile(delta: float) -> void:
	if _pending_auth.is_empty() or not is_predicting():
		_pending_auth = {}
		return

	var entity := my_entity
	var authoritative: InfantryState = entity.authoritative_state_from(_pending_auth)
	var acked := _pending_auth_tick
	_pending_auth = {}

	var space := (entity as Node3D).get_world_3d().direct_space_state
	var result := prediction.reconcile(acked, authoritative, entity.tuning, space, delta)
	if not result.get("corrected", false):
		return

	entity.set_predicted_state(result["state"], sampler.aim_vector())
	entity.add_visual_error(result["error"])


func send_command(cmd: InputCommand) -> void:
	_outbox.append(cmd)
	while _outbox.size() > NetCli.COMMAND_REDUNDANCY:
		_outbox.pop_front()

	var bundle: Array = []
	for queued in _outbox:
		bundle.append(queued.to_dict())

	if GameServer.is_active:
		GameServer.submit_local_commands(get_peer_id(), bundle)
	elif can_rpc():
		shim.dispatch(_send_bundle, [bundle])


func can_rpc() -> bool:
	if state != State.CONNECTED or multiplayer.multiplayer_peer == null:
		return false
	return multiplayer.multiplayer_peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED


func _send_bundle(bundle: Array) -> void:
	if can_rpc():
		GameServer.receive_commands.rpc_id(1, bundle)


@rpc("authority", "call_remote", "unreliable")
func receive_snapshot(snapshot: Dictionary) -> void:
	shim.dispatch(_accept_snapshot, [snapshot])


func _accept_snapshot(snapshot: Dictionary) -> void:
	buffer.push(snapshot)
	var acks: Dictionary = snapshot.get("acks", {})
	_acked_tick = acks.get(get_peer_id(), _acked_tick)

	if not is_predicting():
		return
	var entities: Dictionary = snapshot.get("entities", {})
	if entities.has(my_entity.name):
		_pending_auth = entities[my_entity.name]
		_pending_auth_tick = _acked_tick


@rpc("authority", "call_remote", "unreliable")
func spawn_tracer(origin: Vector3, direction: Vector3, params_id: int, shooter_peer: int) -> void:
	if ballistics == null:
		return
	if shooter_peer == get_peer_id() and is_predicting():
		return
	ballistics.spawn(origin, direction, params_id, shooter_peer, 0.0,
		roster.team_of(shooter_peer))


@rpc("authority", "call_remote", "reliable")
func receive_roster(slots: Array, new_phase: int, new_tickets: Dictionary,
		winner: int) -> void:
	apply_roster(slots, new_phase, new_tickets, winner)


func apply_roster(slots: Array, new_phase: int, new_tickets := {}, winner := 0) -> void:
	tickets = new_tickets
	winning_team = winner
	roster.from_array(slots)
	var was := phase
	phase = new_phase
	my_team = roster.team_of(get_peer_id())
	EventBus.roster_changed.emit()
	if phase == GameServer.Phase.PLAYING and was != phase and not is_alive():
		set_deploy_map(true)
	elif phase != GameServer.Phase.PLAYING and deploy_map_open:
		close_deploy_map()


func request_slot(slot: int) -> void:
	if GameServer.is_active:
		GameServer.handle_slot_request(get_peer_id(), slot)
	elif can_rpc():
		GameServer.request_slot.rpc_id(1, slot)


func request_start() -> void:
	if GameServer.is_active:
		GameServer.handle_start_request(get_peer_id())
	elif can_rpc():
		GameServer.request_start.rpc_id(1)


func my_slot() -> int:
	return roster.slot_of(get_peer_id())


@rpc("authority", "call_remote", "reliable")
func grant_possession(entity_name: String) -> void:
	_pending_entity_name = entity_name
	_bind_pending()


func _bind_pending() -> void:
	if _pending_entity_name == "" or _players_root == null:
		return
	var entity := _find_replicated(_pending_entity_name)
	if entity == null:
		return
	_pending_entity_name = ""
	set_my_entity(entity)


func get_acked_tick() -> int:
	return _acked_tick


func _process(delta: float) -> void:
	if state == State.CONNECTING:
		_connecting_for += delta
		if _connecting_for >= CONNECT_TIMEOUT_SEC:
			push_error("[client] no response from %s:%d after %.0f s — wrong address, server not running, or firewalled"
				% [_address, _port, CONNECT_TIMEOUT_SEC])
			_set_state(State.FAILED)

	if _pending_entity_name != "":
		_bind_pending()

	if _players_root == null:
		return
	if GameServer.is_active:
		_uptime += delta
		_net_log(delta)
		return

	_uptime += delta
	_net_log(delta)
	buffer.advance(delta)
	var states := buffer.sample()
	for entity_name in states:
		var entity := _find_replicated(entity_name)
		if entity != null and entity.has_method("apply_replicated_state"):
			entity.apply_replicated_state(states[entity_name])
	_trace(states)


func _find_replicated(entity_name: String) -> Node:
	var entity := _players_root.get_node_or_null(NodePath(entity_name))
	if entity != null:
		return entity
	for vehicle in get_tree().get_nodes_in_group("vehicle"):
		if vehicle.name == entity_name:
			return vehicle
	return null


func _net_log(delta: float) -> void:
	if not NetCli.is_net_log():
		return
	_log_countdown -= delta
	if _log_countdown > 0.0:
		return
	_log_countdown = 1.0
	if GameServer.is_active and GameServer.ballistics != null:
		print("[ball] auth=%s live=%d hits=%d targets=%d"
			% [GameServer.ballistics.authoritative, GameServer.ballistics.live_count(),
				GameServer.ballistics.hits_logged, GameServer.get_entity_count()])
		return
	print("[net] snapshots=%d rate=%.1f/s buffer=%d lag=%.1ft reorder=%d resync=%d acked=%d entities=%d dropped=%d"
		% [buffer.received, buffer.received / maxf(_uptime, 0.001), buffer.depth(), buffer.lag_ticks(),
			buffer.out_of_order, buffer.resyncs, _acked_tick,
			_players_root.get_child_count() if _players_root != null else 0,
			shim.dropped if shim != null else 0])
	if is_predicting():
		print("[pred] pending=%d corrections=%d replayed=%d last_error=%.4fm visual_error=%.4fm"
			% [prediction.depth(), prediction.corrections, prediction.replayed_commands,
				prediction.last_error, my_entity.get_visual_error()])


func _trace(states: Dictionary) -> void:
	if not NetCli.is_net_trace():
		return
	var stamp := Time.get_ticks_msec()
	for entity_name in states:
		var p: Vector3 = states[entity_name]["p"]
		print("TRACE %d %s %.4f %.4f %.4f %d" % [stamp, entity_name, p.x, p.y, p.z, _players_root.get_child_count()])


func request_dev_damage(amount: float) -> void:
	if GameServer.is_active:
		GameServer.apply_dev_damage(get_peer_id(), amount)
	elif can_rpc():
		GameServer.request_dev_damage.rpc_id(1, amount)


func _on_possession_granted(peer_id: int, entity: Node) -> void:
	if peer_id != get_peer_id():
		return
	set_my_entity(entity)


func set_my_entity(entity: Node) -> void:
	if my_entity != null and is_instance_valid(my_entity) and my_entity.has_method("unpossess"):
		my_entity.unpossess()

	my_entity = entity

	prediction.clear()
	if my_entity != null and my_entity.has_method("possess"):
		my_entity.possess()
		was_killed = false
		deploy_map_open = false
		EventBus.deploy_map_toggled.emit(false)
		if sampler != null:
			sampler.capture_mouse()
	elif sampler != null:
		sampler.release_mouse()

	EventBus.possession_changed.emit(my_entity)


func get_address() -> String:
	return _address


func get_port() -> int:
	return _port


func get_peer_id() -> int:
	var peer := multiplayer.multiplayer_peer
	if peer != null and peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED:
		_peer_id = multiplayer.get_unique_id()
	return _peer_id


func _set_state(next: State) -> void:
	if state == next:
		return
	state = next
	connection_state_changed.emit(state)


func _on_connected() -> void:
	print("[client] connected to %s:%d as peer %d" % [_address, _port, multiplayer.get_unique_id()])
	_set_state(State.CONNECTED)
	GameServer.refresh_entity_authority()
	if _players_root != null and can_rpc():
		GameServer.client_ready.rpc_id(1, NetCli.has_explicit_mode())


func _on_connection_failed() -> void:
	push_error("[client] connection to %s:%d failed" % [_address, _port])
	_set_state(State.FAILED)


func _on_server_disconnected() -> void:
	push_warning("[client] server disconnected")
	set_my_entity(null)
	_set_state(State.OFFLINE)


func request_spawn(spawn_point: SpawnPoint) -> void:
	if spawn_point == null:
		return
	if GameServer.is_active:
		GameServer.handle_spawn_request(get_peer_id(), spawn_point)
	elif can_rpc():
		GameServer.request_spawn_rpc.rpc_id(1, spawn_point.display_name)


func squadmate_entity(mate_peer: int) -> Node3D:
	if _players_root != null:
		var body := _players_root.get_node_or_null("Player_%d" % mate_peer)
		if body != null and not body.is_queued_for_deletion():
			return body as Node3D
	for vehicle in get_tree().get_nodes_in_group("vehicle"):
		if vehicle.seats.has_peer(mate_peer):
			return vehicle as Node3D
	return null


func squadmate_spawn_targets() -> Array:
	var out: Array = []
	if phase != GameServer.Phase.PLAYING:
		return out
	for mate in roster.squadmates(get_peer_id()):
		var body := squadmate_entity(mate)
		if body != null and is_instance_valid(body):
			out.append(mate)
	return out


func request_squad_spawn(mate_peer: int) -> void:
	if mate_peer <= 0:
		return
	if GameServer.is_active:
		GameServer.handle_squad_spawn_request(get_peer_id(), mate_peer)
	elif can_rpc():
		GameServer.request_squad_spawn_rpc.rpc_id(1, mate_peer)


func request_forged_spawn(spawn_point: SpawnPoint) -> void:
	if spawn_point == null:
		return
	print("[client] sending a deliberately illegal spawn request while alive")
	if GameServer.is_active:
		GameServer.handle_spawn_request(get_peer_id(), spawn_point)
	elif can_rpc():
		GameServer.request_spawn_rpc.rpc_id(1, spawn_point.display_name)


func is_alive() -> bool:
	return my_entity != null and is_instance_valid(my_entity)


@rpc("authority", "call_remote", "reliable")
func on_killed() -> void:
	was_killed = true
	set_my_entity(null)
	set_deploy_map(true)


func close_deploy_map() -> void:
	if not deploy_map_open:
		return
	deploy_map_open = false
	if sampler != null:
		sampler.release_mouse()
	EventBus.deploy_map_toggled.emit(false)


func set_deploy_map(open: bool) -> void:
	if open and phase != GameServer.Phase.PLAYING:
		return
	if open == deploy_map_open:
		return
	if not open and not is_alive():
		return
	deploy_map_open = open
	if sampler != null:
		if open:
			sampler.release_mouse()
		else:
			sampler.capture_mouse()
	EventBus.deploy_map_toggled.emit(open)
	if open and NetCli.is_bot():
		_auto_deploy()


func _auto_deploy() -> void:
	await get_tree().create_timer(0.5).timeout
	if is_alive() or not is_active:
		return
	var points := get_tree().get_nodes_in_group("spawn_points")
	for point in points:
		if point is SpawnPoint and point.enabled:
			request_spawn(point)
			return


func request_enter(vehicle: Node) -> void:
	if vehicle == null:
		return
	if GameServer.is_active:
		GameServer.handle_enter_request(get_peer_id(), vehicle)
	elif can_rpc():
		GameServer.request_enter_rpc.rpc_id(1, vehicle.name)


func request_exit() -> void:
	if GameServer.is_active:
		GameServer.handle_exit_request(get_peer_id())
	elif can_rpc():
		GameServer.request_exit_rpc.rpc_id(1)


func request_deploy_map(open: bool) -> void:
	set_deploy_map(open)
