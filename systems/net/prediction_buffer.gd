class_name PredictionBuffer
extends RefCounted

const MAX_PENDING := 128

var corrections: int = 0
var replayed_commands: int = 0
var last_error: float = 0.0
var position_epsilon: float = 0.02

var _pending: Array[Dictionary] = []


func push(tick: int, cmd: InputCommand, state: InfantryState) -> void:
	_pending.append({"tick": tick, "cmd": cmd, "state": state})
	while _pending.size() > MAX_PENDING:
		_pending.pop_front()


func depth() -> int:
	return _pending.size()


func clear() -> void:
	_pending.clear()


func reconcile(acked_tick: int, authoritative: InfantryState, tuning: InfantryTuning,
		space: PhysicsDirectSpaceState3D, delta: float) -> Dictionary:
	var predicted: InfantryState = null
	for entry in _pending:
		if int(entry["tick"]) == acked_tick:
			predicted = entry["state"]
			break

	var replay: Array[Dictionary] = []
	for entry in _pending:
		if int(entry["tick"]) > acked_tick:
			replay.append(entry)
	_pending = replay

	if predicted != null and predicted.equals_within(authoritative, position_epsilon):
		last_error = 0.0
		return {"corrected": false}

	var before := Vector3.ZERO
	var had_prediction := not _pending.is_empty()
	if had_prediction:
		before = (_pending[_pending.size() - 1]["state"] as InfantryState).position
	elif predicted != null:
		before = predicted.position

	var state := authoritative.clone()
	for entry in _pending:
		state = InfantrySim.simulate(state, entry["cmd"], tuning, space, delta)
		entry["state"] = state

	corrections += 1
	replayed_commands += _pending.size()
	var error := before - state.position if (had_prediction or predicted != null) else Vector3.ZERO
	last_error = error.length()
	return {"corrected": true, "state": state, "error": error}
