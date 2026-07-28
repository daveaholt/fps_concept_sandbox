extends Label


func _process(_delta: float) -> void:
	var lines: Array[String] = []
	lines.append("mode: %s   peer id: %d"
		% [NetCli.mode_name(NetCli.get_mode()), GameClient.get_peer_id()])

	if GameServer.is_active:
		lines.append("server: udp/%d   clients: %d   entities: %d   tick: %d"
			% [GameServer.get_port(), GameServer.get_peer_count(), GameServer.get_entity_count(), GameServer.tick])
	if GameClient.is_active:
		lines.append("client: %s:%d   %s"
			% [GameClient.get_address(), GameClient.get_port(), _state_text(GameClient.state)])
	if GameClient.is_active and not GameServer.is_active:
		var buffer := GameClient.buffer
		lines.append("snapshots: %d recv   buffer: %d   lag: %.1f ticks   reorder: %d   resync: %d"
			% [buffer.received, buffer.depth(), buffer.lag_ticks(), buffer.out_of_order, buffer.resyncs])
		lines.append("acked cmd tick: %d" % GameClient.get_acked_tick())
	if GameClient.shim != null and GameClient.shim.enabled:
		lines.append("shim: %.0f ms rtt / %.0f ms jitter / %.1f%% loss   dropped: %d   in flight: %d"
			% [GameClient.shim.latency_rtt_ms, GameClient.shim.jitter_ms, GameClient.shim.loss * 100.0,
				GameClient.shim.dropped, GameClient.shim.pending()])

	lines.append("WASD move · Space jump · Shift sprint · 1/2 weapons · K dev damage · F11 fullscreen · Esc free mouse")
	text = "\n".join(lines)


func _state_text(state: int) -> String:
	match state:
		GameClient.State.CONNECTING: return "connecting"
		GameClient.State.CONNECTED: return "connected"
		GameClient.State.FAILED: return "failed"
		_: return "offline"
