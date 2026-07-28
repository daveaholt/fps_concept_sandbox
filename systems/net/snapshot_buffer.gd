class_name SnapshotBuffer
extends RefCounted

const MAX_SNAPSHOTS := 32
const RESYNC_TICKS := 30.0
const MAX_RATE_TRIM := 0.1

var interp_delay_ticks: float = NetCli.INTERP_DELAY_MS * 0.001 * NetCli.TICK_RATE
var render_tick: float = -1.0
var latest_tick: int = -1
var received: int = 0
var out_of_order: int = 0
var resyncs: int = 0

var _snapshots: Array[Dictionary] = []


func push(snapshot: Dictionary) -> void:
	var tick: int = snapshot.get("tick", -1)
	if tick < 0:
		return
	for existing in _snapshots:
		if int(existing["tick"]) == tick:
			return

	var index := _snapshots.size()
	while index > 0 and int(_snapshots[index - 1]["tick"]) > tick:
		index -= 1
	if index < _snapshots.size():
		out_of_order += 1
	_snapshots.insert(index, snapshot)

	received += 1
	latest_tick = maxi(latest_tick, tick)
	while _snapshots.size() > MAX_SNAPSHOTS:
		_snapshots.pop_front()


func depth() -> int:
	return _snapshots.size()


func lag_ticks() -> float:
	if latest_tick < 0 or render_tick < 0.0:
		return 0.0
	return float(latest_tick) - render_tick


func advance(delta: float) -> void:
	if latest_tick < 0:
		return

	var target := float(latest_tick) - interp_delay_ticks
	if render_tick < 0.0:
		render_tick = target
		return

	var drift := target - render_tick
	if absf(drift) > RESYNC_TICKS:
		render_tick = target
		resyncs += 1
		return

	var rate := 1.0 + clampf(drift * 0.05, -MAX_RATE_TRIM, MAX_RATE_TRIM)
	render_tick += delta * NetCli.TICK_RATE * rate


func sample() -> Dictionary:
	if _snapshots.is_empty():
		return {}
	if _snapshots.size() == 1:
		return _snapshots[0]["entities"]

	var oldest: Dictionary = _snapshots[0]
	var newest: Dictionary = _snapshots[_snapshots.size() - 1]

	if render_tick <= float(oldest["tick"]):
		return oldest["entities"]

	if render_tick >= float(newest["tick"]):
		var previous: Dictionary = _snapshots[_snapshots.size() - 2]
		var span := float(newest["tick"]) - float(previous["tick"])
		if span <= 0.0:
			return newest["entities"]
		var overshoot := (render_tick - float(newest["tick"])) / span
		return _blend(previous["entities"], newest["entities"], 1.0 + minf(overshoot, 1.0))

	for i in range(_snapshots.size() - 1):
		var a: Dictionary = _snapshots[i]
		var b: Dictionary = _snapshots[i + 1]
		if float(a["tick"]) <= render_tick and render_tick <= float(b["tick"]):
			var span := float(b["tick"]) - float(a["tick"])
			var t := 0.0 if span <= 0.0 else (render_tick - float(a["tick"])) / span
			return _blend(a["entities"], b["entities"], t)

	return newest["entities"]


static func _blend(from_entities: Dictionary, to_entities: Dictionary, t: float) -> Dictionary:
	var out := {}
	for key in to_entities:
		var to_state: Dictionary = to_entities[key]
		if not from_entities.has(key):
			out[key] = to_state
			continue

		var from_state: Dictionary = from_entities[key]
		var blended := to_state.duplicate()
		var clamped := clampf(t, 0.0, 1.0)

		if from_state.has("p") and to_state.has("p"):
			blended["p"] = (from_state["p"] as Vector3).lerp(to_state["p"], t)
		if from_state.has("a") and to_state.has("a"):
			var aim: Vector3 = (from_state["a"] as Vector3).lerp(to_state["a"], clamped)
			blended["a"] = aim.normalized() if aim.length_squared() > 0.000001 else to_state["a"]
		if from_state.has("q") and to_state.has("q"):
			blended["q"] = (from_state["q"] as Quaternion).slerp(to_state["q"], clamped)
		if from_state.has("ty") and to_state.has("ty"):
			blended["ty"] = lerp_angle(from_state["ty"], to_state["ty"], clamped)
		if from_state.has("cp") and to_state.has("cp"):
			blended["cp"] = lerpf(from_state["cp"], to_state["cp"], clamped)

		out[key] = blended
	return out
