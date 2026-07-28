class_name NetShim
extends Node

@export var enabled: bool = false
@export var latency_rtt_ms: float = 0.0
@export var jitter_ms: float = 0.0
@export var loss: float = 0.0

var dropped: int = 0
var delivered: int = 0

var _queue: Array[Dictionary] = []
var _clock: float = 0.0
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.randomize()
	process_priority = -100


func configure_from_cli() -> void:
	enabled = NetCli.shim_enabled()
	latency_rtt_ms = NetCli.get_latency_rtt_ms()
	jitter_ms = NetCli.get_jitter_ms()
	loss = NetCli.get_loss()
	if enabled:
		print("[shim] %.0f ms RTT, %.0f ms jitter, %.1f%% loss"
			% [latency_rtt_ms, jitter_ms, loss * 100.0])


func one_way_seconds() -> float:
	var base := latency_rtt_ms * 0.5
	var jitter := _rng.randf_range(-jitter_ms, jitter_ms) * 0.5
	return maxf(0.0, (base + jitter) * 0.001)


func dispatch(target: Callable, args: Array = []) -> void:
	if not enabled:
		target.callv(args)
		delivered += 1
		return

	if loss > 0.0 and _rng.randf() < loss:
		dropped += 1
		return

	_queue.append({"due": _clock + one_way_seconds(), "target": target, "args": args})


func pending() -> int:
	return _queue.size()


func _process(delta: float) -> void:
	_clock += delta
	if _queue.is_empty():
		return

	var ready: Array[Dictionary] = []
	var still_waiting: Array[Dictionary] = []
	for item in _queue:
		if item["due"] <= _clock:
			ready.append(item)
		else:
			still_waiting.append(item)
	_queue = still_waiting

	for item in ready:
		var target: Callable = item["target"]
		if target.is_valid():
			target.callv(item["args"])
			delivered += 1
