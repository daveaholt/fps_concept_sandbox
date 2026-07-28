class_name NetCli
extends RefCounted

enum Mode {
	HOST,
	SERVER,
	CLIENT,
}

const DEFAULT_PORT := 27015
const DEFAULT_ADDRESS := "127.0.0.1"
const MAX_PEERS := 8

const TICK_RATE := 60
const SNAPSHOT_EVERY_TICKS := 3
const INTERP_DELAY_MS := 100.0
const COMMAND_REDUNDANCY := 4


static func all_args() -> PackedStringArray:
	var args := OS.get_cmdline_args()
	args.append_array(OS.get_cmdline_user_args())
	return args


static func is_tool_run() -> bool:
	return OS.get_cmdline_args().has("--script")


static func is_net_log() -> bool:
	return all_args().has("--net-log")


static func is_bot() -> bool:
	return all_args().has("--bot") or all_args().has("--bot-wall")


static func is_bot_wall() -> bool:
	return all_args().has("--bot-wall")


static func is_bot_firing() -> bool:
	return all_args().has("--bot-fire")


static func is_bot_suicidal() -> bool:
	return all_args().has("--bot-suicide")


static func is_net_trace() -> bool:
	return all_args().has("--net-trace")


static func get_latency_rtt_ms() -> float:
	return maxf(0.0, _flag_value("--latency", "0").to_float())


static func get_jitter_ms() -> float:
	return maxf(0.0, _flag_value("--jitter", "0").to_float())


static func get_loss() -> float:
	return clampf(_flag_value("--loss", "0").to_float(), 0.0, 1.0)


static func shim_enabled() -> bool:
	return get_latency_rtt_ms() > 0.0 or get_jitter_ms() > 0.0 or get_loss() > 0.0


static func get_mode() -> Mode:
	var args := all_args()
	if args.has("--client"):
		return Mode.CLIENT
	if args.has("--server"):
		return Mode.SERVER
	return Mode.HOST


static func mode_name(mode: Mode) -> String:
	match mode:
		Mode.SERVER: return "server"
		Mode.CLIENT: return "client"
		_: return "host"


static func get_port() -> int:
	var port := _flag_value("--port", str(DEFAULT_PORT)).to_int()
	return port if port > 0 and port < 65536 else DEFAULT_PORT


static func get_connect_address() -> String:
	return _flag_value("--connect", DEFAULT_ADDRESS)


static func _flag_value(flag: String, fallback: String) -> String:
	var args := all_args()
	var i := args.find(flag)
	if i != -1 and i + 1 < args.size():
		return args[i + 1]
	return fallback
