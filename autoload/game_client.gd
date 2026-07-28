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

var _address: String = ""
var _port: int = 0
var _connecting_for: float = 0.0


func _ready() -> void:
	if NetCli.is_tool_run():
		return
	match NetCli.get_mode():
		NetCli.Mode.CLIENT:
			_start_local_systems()
			_connect_to(NetCli.get_connect_address(), NetCli.get_port())
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
	sampler = InputSampler.new()
	sampler.name = "InputSampler"
	add_child(sampler)

	var scanner := InteractionScanner.new()
	scanner.name = "InteractionScanner"
	add_child(scanner)


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
	print("[client] connecting to %s:%d ..." % [address, port])


func _process(delta: float) -> void:
	if state != State.CONNECTING:
		return
	_connecting_for += delta
	if _connecting_for >= CONNECT_TIMEOUT_SEC:
		push_error("[client] no response from %s:%d after %.0f s — wrong address, server not running, or firewalled"
			% [_address, _port, CONNECT_TIMEOUT_SEC])
		_set_state(State.FAILED)


func send_command(cmd: InputCommand) -> void:
	if GameServer.is_active:
		GameServer.submit_command(get_peer_id(), cmd)


func request_dev_damage(amount: float) -> void:
	if GameServer.is_active:
		GameServer.apply_dev_damage(get_peer_id(), amount)


func _on_possession_granted(peer_id: int, entity: Node) -> void:
	if peer_id != get_peer_id():
		return
	set_my_entity(entity)


func set_my_entity(entity: Node) -> void:
	if my_entity != null and is_instance_valid(my_entity) and my_entity.has_method("unpossess"):
		my_entity.unpossess()

	my_entity = entity

	if my_entity != null and my_entity.has_method("possess"):
		my_entity.possess()
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
	if multiplayer.multiplayer_peer == null:
		return 0
	return multiplayer.get_unique_id()


func _set_state(next: State) -> void:
	if state == next:
		return
	state = next
	connection_state_changed.emit(state)


func _on_connected() -> void:
	print("[client] connected to %s:%d as peer %d" % [_address, _port, multiplayer.get_unique_id()])
	_set_state(State.CONNECTED)


func _on_connection_failed() -> void:
	push_error("[client] connection to %s:%d failed" % [_address, _port])
	_set_state(State.FAILED)


func _on_server_disconnected() -> void:
	push_warning("[client] server disconnected")
	set_my_entity(null)
	_set_state(State.OFFLINE)


func request_spawn(spawn_point: SpawnPoint) -> void:
	push_warning("[client] request_spawn(%s) is a stub until M4"
		% [spawn_point.display_name if spawn_point else "<null>"])


func request_enter(vehicle: Node) -> void:
	push_warning("[client] request_enter(%s) is a stub until M5"
		% [vehicle.name if vehicle else "<null>"])


func request_exit() -> void:
	push_warning("[client] request_exit() is a stub until M5")


func request_deploy_map(open: bool) -> void:
	push_warning("[client] request_deploy_map(%s) is a stub until M4" % open)
