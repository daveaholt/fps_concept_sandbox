extends Node

signal server_started(port: int)
signal peer_joined(peer_id: int)
signal peer_left(peer_id: int)

var is_active: bool = false

var _port: int = 0
var _possession: Dictionary = {}


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


func get_port() -> int:
	return _port


func get_peer_count() -> int:
	if not is_active:
		return 0
	return multiplayer.get_peers().size()


func _on_peer_connected(peer_id: int) -> void:
	print("[server] peer %d connected (%d connected)" % [peer_id, get_peer_count()])
	peer_joined.emit(peer_id)


func _on_peer_disconnected(peer_id: int) -> void:
	_possession.erase(peer_id)
	print("[server] peer %d disconnected (%d connected)" % [peer_id, get_peer_count()])
	peer_left.emit(peer_id)


func handle_spawn_request(peer: int, spawn_point: SpawnPoint) -> void:
	push_warning("[server] handle_spawn_request(peer %d, %s) is a stub until M4"
		% [peer, spawn_point.display_name if spawn_point else "<null>"])


func handle_enter_request(peer: int, vehicle: Node) -> void:
	push_warning("[server] handle_enter_request(peer %d, %s) is a stub until M5"
		% [peer, vehicle.name if vehicle else "<null>"])


func handle_exit_request(peer: int) -> void:
	push_warning("[server] handle_exit_request(peer %d) is a stub until M5" % peer)


func entity_died(entity: Node) -> void:
	push_warning("[server] entity_died(%s) is a stub until M4" % [entity.name if entity else "<null>"])
