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


static func all_args() -> PackedStringArray:
	var args := OS.get_cmdline_args()
	args.append_array(OS.get_cmdline_user_args())
	return args


static func is_tool_run() -> bool:
	return OS.get_cmdline_args().has("--script")


static func is_net_log() -> bool:
	return all_args().has("--net-log")


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
