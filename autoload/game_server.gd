extends Node

const PLAYER_SCENE_PATH := "res://entities/player/player.tscn"
const DEATH_CAM_SECONDS := 2.5
const MAX_BUFFERED_COMMANDS := 16
const ENTER_RANGE := 4.0
const SPAWN_SPREAD := 2.2
const VEHICLE_RESPAWN_SECONDS := 10.0
const SPAWN_DISPERSAL_RADIUS := 4.5
const SPAWN_DISPERSAL_TRIES := 12
const SPAWN_DISPERSAL_FALLBACK := 1.2

enum Phase { LOBBY, PLAYING, RESULT }

const HOST_PEER := 1
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
var _spawn_tuning_cache: InfantryTuning = null
var ballistics: BallisticsManager = null
var _vehicles: Array = []
var _wrecks: Array = []
var _corpses: Array = []


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
	if ballistics != null:
		ballistics.authoritative = true
	refresh_entity_authority()
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
		if not ballistics.hit_confirmed.is_connected(_on_hit_confirmed):
			ballistics.hit_confirmed.connect(_on_hit_confirmed)


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
	_broadcast_shot(origin, direction, params_id, peer_id)


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
		if vehicle.has_signal("gun_fired"):
			vehicle.gun_fired.connect(_on_vehicle_gun_fired.bind(vehicle))
	if vehicle.has_signal("destroyed") and not vehicle.destroyed.is_connected(
			_on_vehicle_destroyed):
		vehicle.destroyed.connect(_on_vehicle_destroyed)
	if ballistics != null:
		ballistics.register_target(vehicle)


func _on_vehicle_fired(origin: Vector3, direction: Vector3, params_id: int, vehicle: Node) -> void:
	if ballistics == null:
		return
	var peer_id: int = vehicle.owner_peer
	var view_delay := NetCli.INTERP_DELAY_MS * 0.001 + get_peer_rtt(peer_id) * 0.5
	ballistics.spawn(origin, direction, params_id, peer_id, view_delay,
		roster.team_of(peer_id))
	_broadcast_shot(origin, direction, params_id, peer_id)


func _on_vehicle_gun_fired(origin: Vector3, direction: Vector3, params_id: int,
		vehicle: Node) -> void:
	if ballistics == null:
		return
	var peer_id: int = vehicle.gunner_peer()
	var view_delay := NetCli.INTERP_DELAY_MS * 0.001 + get_peer_rtt(peer_id) * 0.5
	ballistics.spawn(origin, direction, params_id, peer_id, view_delay,
		roster.team_of(peer_id))
	_broadcast_shot(origin, direction, params_id, peer_id)


func _broadcast_shot(origin: Vector3, direction: Vector3, params_id: int,
		peer_id: int) -> void:
	GameClient.note_gunshot(origin, peer_id)
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
func request_slot(slot: int, chosen_name: String = "") -> void:
	if is_active:
		handle_slot_request(multiplayer.get_remote_sender_id(), slot, chosen_name)


func handle_slot_request(peer: int, slot: int, chosen_name: String = "") -> void:
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
	roster.set_slot_name(slot, chosen_name)
	print("[server] peer %d took slot %d (%s, team %d)"
		% [peer, slot, Roster.squad_name(roster.squad_of(peer)), roster.team_of(peer)])
	_broadcast_roster()


@rpc("any_peer", "call_remote", "reliable")
func request_start() -> void:
	if is_active:
		handle_start_request(multiplayer.get_remote_sender_id())


@rpc("any_peer", "call_remote", "reliable")
func request_name(chosen_name: String) -> void:
	if is_active:
		handle_name_request(multiplayer.get_remote_sender_id(), chosen_name)


func handle_name_request(peer: int, chosen_name: String) -> void:
	if not is_active:
		return
	var slot := roster.slot_of(peer)
	if slot < 0:
		return
	if roster.name_of_slot(slot) == Roster.sanitise_name(chosen_name):
		return
	roster.set_slot_name(slot, chosen_name)
	_broadcast_roster()


func handle_start_request(peer: int) -> void:
	if not is_active or phase == Phase.PLAYING:
		return
	if peer != HOST_PEER:
		push_warning("[server] REJECTED start from peer %d: only the host starts a match"
			% peer)
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


func _refresh_vehicle_team(vehicle: Node) -> void:
	if vehicle == null or not is_instance_valid(vehicle):
		return
	var occupants: Array = vehicle.seats.occupants()
	if occupants.is_empty():
		vehicle.team = Roster.UNALIGNED
		return
	var driver: int = vehicle.seats.driver()
	vehicle.team = roster.team_of(driver if driver != 0 else int(occupants[0]))


func refresh_entity_authority() -> void:
	for node in get_tree().get_nodes_in_group("controllable"):
		if node.has_method("refresh_authority"):
			node.refresh_authority()


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
	GameClient.apply_roster(roster.to_array(), int(phase), tickets, winning_team,
		roster.names_to_array())
	if get_peer_count() > 0 and multiplayer.multiplayer_peer != null:
		GameClient.receive_roster.rpc(roster.to_array(), int(phase), tickets,
			winning_team, roster.names_to_array())


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
	if not vehicle.has_free_seat():
		push_warning("[server] REJECTED enter from peer %d: %s is full (%d seats)"
			% [peer, vehicle.name, vehicle.seats.count()])
		return

	var distance: float = occupant.global_position.distance_to(vehicle.global_position)
	if distance > ENTER_RANGE:
		push_warning("[server] REJECTED enter from peer %d: %.1f m away, limit %.1f"
			% [peer, distance, ENTER_RANGE])
		return

	_release_entity(peer)
	var seat: int = vehicle.take_seat(peer)
	if seat < 0:
		push_warning("[server] REJECTED enter from peer %d: no seat free" % peer)
		return
	_refresh_vehicle_team(vehicle)
	_bind(peer, vehicle)
	print("[server] peer %d took seat %d of %s" % [peer, seat, vehicle.name])
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
	vehicle.leave_seat(peer)
	_refresh_vehicle_team(vehicle)
	if vehicle.seats.is_empty():
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


func _release_peer(peer_id: int, keep_body: bool = false) -> void:
	var entity: Node = _possession.get(peer_id)
	if entity != null and is_instance_valid(entity):
		if entity.is_in_group("vehicle"):
			entity.leave_seat(peer_id)
			_refresh_vehicle_team(entity)
			if entity.seats.is_empty():
				entity.unpossess()
		else:
			if ballistics != null:
				ballistics.unregister_target(entity)
			if keep_body:
				_corpses.append({"body": entity, "seconds": DEATH_CAM_SECONDS})
			else:
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

	var origin := disperse(point.global_position)
	var entity := _spawn_infantry(peer_id, origin, -point.global_transform.basis.z)
	print("[server] peer %d deployed at %s %v (%d entities)"
		% [peer_id, point.display_name, origin, _possession.size()])
	return entity


func disperse(base: Vector3) -> Vector3:
	if _spawn_root == null or not (_spawn_root is Node3D):
		return base
	var space := (_spawn_root as Node3D).get_world_3d().direct_space_state
	if space == null:
		return base
	for _attempt in SPAWN_DISPERSAL_TRIES:
		var angle := randf() * TAU
		var radius := sqrt(randf()) * SPAWN_DISPERSAL_RADIUS
		var candidate := base + Vector3(cos(angle) * radius, 0.0, sin(angle) * radius)
		if _spawn_is_clear(candidate, space):
			return candidate
	var last := randf() * TAU
	return base + Vector3(cos(last), 0.0, sin(last)) * SPAWN_DISPERSAL_FALLBACK


func _spawn_is_clear(feet: Vector3, space: PhysicsDirectSpaceState3D) -> bool:
	var tuning := _spawn_tuning()
	if tuning == null:
		return true
	var shape := CapsuleShape3D.new()
	shape.radius = maxf(0.05, tuning.capsule_radius - tuning.penetration_inset)
	shape.height = maxf(0.2, tuning.capsule_height - tuning.penetration_inset * 2.0)
	var params := PhysicsShapeQueryParameters3D.new()
	params.shape = shape
	params.collision_mask = tuning.collision_mask
	params.margin = 0.0
	params.transform = Transform3D(Basis(),
		feet + Vector3.UP * tuning.capsule_height * 0.5)
	return space.intersect_shape(params, 1).is_empty()


func _spawn_tuning() -> InfantryTuning:
	if _player_scene == null:
		_player_scene = load(PLAYER_SCENE_PATH)
	if _spawn_tuning_cache == null and _player_scene != null:
		var probe := _player_scene.instantiate()
		_spawn_tuning_cache = probe.tuning
		probe.free()
	return _spawn_tuning_cache


func squadmate_spawn_targets(peer_id: int) -> Array[int]:
	var out: Array[int] = []
	if phase != Phase.PLAYING:
		return out
	for mate in roster.squadmates(peer_id):
		if can_spawn_on(peer_id, mate):
			out.append(mate)
	return out


func can_spawn_on(peer_id: int, mate_peer: int) -> bool:
	if mate_peer == peer_id or not roster.has_peer(peer_id):
		return false
	if roster.squad_of(mate_peer) != roster.squad_of(peer_id):
		return false
	var entity: Node = _possession.get(mate_peer)
	if entity == null or not is_instance_valid(entity):
		return false
	if entity.is_in_group("vehicle"):
		return entity.has_free_seat()
	return true


@rpc("any_peer", "call_remote", "reliable")
func request_squad_spawn_rpc(mate_peer: int) -> void:
	if is_active:
		handle_squad_spawn_request(multiplayer.get_remote_sender_id(), mate_peer)


@rpc("any_peer", "call_remote", "reliable")
func request_switch_seat_rpc() -> void:
	if is_active:
		handle_switch_seat_request(multiplayer.get_remote_sender_id())


func handle_switch_seat_request(peer: int) -> void:
	if not is_active:
		return
	var vehicle: Node = _possession.get(peer)
	if vehicle == null or not is_instance_valid(vehicle) or not vehicle.is_in_group("vehicle"):
		return
	var from: int = vehicle.seat_of(peer)
	var count: int = vehicle.seats.count()
	for step in range(1, count):
		var target := (from + step) % count
		if vehicle.seats.is_free(target):
			vehicle.leave_seat(peer)
			vehicle.take_seat(peer, target)
			_refresh_vehicle_team(vehicle)
			print("[server] peer %d moved from seat %d to %d of %s"
				% [peer, from, target, vehicle.name])
			return
	push_warning("[server] REJECTED seat switch from peer %d: no free seat" % peer)


func handle_squad_spawn_request(peer: int, mate_peer: int) -> void:
	if not is_active:
		return
	if _possession.has(peer):
		push_warning("[server] REJECTED squad spawn from peer %d: already deployed" % peer)
		return
	if not can_spawn_on(peer, mate_peer):
		push_warning("[server] REJECTED squad spawn from peer %d onto peer %d"
			% [peer, mate_peer])
		return
	var mate: Node3D = _possession.get(mate_peer)
	if mate.is_in_group("vehicle"):
		var seat: int = mate.take_seat(peer)
		if seat < 0:
			push_warning("[server] REJECTED squad spawn from peer %d: no seat free" % peer)
			return
		_refresh_vehicle_team(mate)
		_bind(peer, mate)
		print("[server] peer %d spawned into seat %d of %s alongside peer %d"
			% [peer, seat, mate.name, mate_peer])
		return
	var origin := disperse(mate.global_position)
	var entity := _spawn_infantry(peer, origin, -mate.global_transform.basis.z)
	if entity != null:
		print("[server] peer %d deployed on squadmate %d at %v" % [peer, mate_peer, origin])
	return


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


func _may_command(entity: Node, peer_id: int) -> bool:
	if entity.has_method("seat_of"):
		return entity.seat_of(peer_id) >= 0
	return entity.owner_peer == peer_id


func _ingest(peer_id: int, bundle: Array) -> void:
	var entity: Node = _possession.get(peer_id)
	if entity == null or not is_instance_valid(entity):
		return
	if not _may_command(entity, peer_id):
		push_warning("[server] dropped commands from peer %d for an entity it does not occupy" % peer_id)
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
	_tick_wrecks(_delta)
	_tick_corpses(_delta)


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
			if entity.has_method("seat_of"):
				entity.push_command(cmd, entity.seat_of(peer_id))
			else:
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
	print("[server] %s died (peer %d) — awaiting redeploy" % [entity.name, entity.owner_peer])
	_kill_occupant(entity.owner_peer)


func _kill_occupant(peer_id: int) -> void:
	if peer_id == 0:
		return
	var entity: Node = _possession.get(peer_id)
	var died_at := Vector3.ZERO
	if entity != null and is_instance_valid(entity) and entity is Node3D:
		died_at = (entity as Node3D).global_position
	_spend_ticket(roster.team_of(peer_id))
	_release_peer(peer_id, true)
	possession_granted.emit(peer_id, null)
	if peer_id == 1:
		GameClient.on_killed(died_at)
	elif multiplayer.get_peers().has(peer_id):
		GameClient.on_killed.rpc_id(peer_id, died_at)


func _tick_corpses(delta: float) -> void:
	if _corpses.is_empty():
		return
	var waiting: Array = []
	for entry in _corpses:
		var body: Node = entry["body"]
		if not is_instance_valid(body):
			continue
		entry["seconds"] = float(entry["seconds"]) - delta
		if float(entry["seconds"]) > 0.0:
			waiting.append(entry)
		else:
			body.queue_free()
	_corpses = waiting


func _on_vehicle_destroyed(vehicle: Node) -> void:
	if not is_active or vehicle == null or vehicle.wrecked:
		return
	var lost: Array = vehicle.seats.occupants()
	print("[server] %s destroyed with %d aboard" % [vehicle.name, lost.size()])
	for peer in lost:
		_kill_occupant(peer)
	vehicle.enter_wreck()
	vehicle.unpossess()
	_refresh_vehicle_team(vehicle)
	_wrecks.append({"vehicle": vehicle, "seconds": VEHICLE_RESPAWN_SECONDS})


func _tick_wrecks(delta: float) -> void:
	if _wrecks.is_empty():
		return
	var still_down: Array = []
	for entry in _wrecks:
		var vehicle: Node = entry["vehicle"]
		if not is_instance_valid(vehicle):
			continue
		entry["seconds"] = float(entry["seconds"]) - delta
		if float(entry["seconds"]) > 0.0:
			if float(entry["seconds"]) <= VEHICLE_RESPAWN_SECONDS - DEATH_CAM_SECONDS:
				vehicle.hide_wreck()
			still_down.append(entry)
			continue
		vehicle.revive()
		print("[server] %s back in service" % vehicle.name)
	_wrecks = still_down


func _on_hit_confirmed(shooter_peer: int, damage: float, killed: bool,
		label: String) -> void:
	if shooter_peer == 0:
		return
	if shooter_peer == 1:
		GameClient.on_hit_confirmed(damage, killed, label)
	elif multiplayer.multiplayer_peer != null and multiplayer.get_peers().has(shooter_peer):
		GameClient.on_hit_confirmed.rpc_id(shooter_peer, damage, killed, label)


