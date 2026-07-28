extends Label


func _process(_delta: float) -> void:
	var lines: Array[String] = []
	lines.append("mode: %s   peer id: %d"
		% [NetCli.mode_name(NetCli.get_mode()), GameClient.get_peer_id()])

	if GameServer.is_active:
		lines.append("server: udp/%d   clients connected: %d"
			% [GameServer.get_port(), GameServer.get_peer_count()])
	if GameClient.is_active:
		lines.append("client: %s:%d   %s"
			% [GameClient.get_address(), GameClient.get_port(), _state_text(GameClient.state)])

	lines.append("WASD move · Space jump · Shift sprint · 1/2 weapons · K dev damage · Esc free mouse")
	text = "\n".join(lines)


func _state_text(state: int) -> String:
	match state:
		GameClient.State.CONNECTING: return "connecting"
		GameClient.State.CONNECTED: return "connected"
		GameClient.State.FAILED: return "failed"
		_: return "offline"
