class_name PositionHistory
extends RefCounted

const WINDOW_SECONDS := 1.0

var _times: Array[float] = []
var _positions: Array[Vector3] = []
var _aims: Array[Vector3] = []


func push(time: float, position: Vector3, aim: Vector3) -> void:
	_times.append(time)
	_positions.append(position)
	_aims.append(aim)
	while _times.size() > 1 and time - _times[0] > WINDOW_SECONDS:
		_times.pop_front()
		_positions.pop_front()
		_aims.pop_front()


func depth() -> int:
	return _times.size()


func span() -> float:
	if _times.size() < 2:
		return 0.0
	return _times[_times.size() - 1] - _times[0]


func sample(time: float) -> Dictionary:
	if _times.is_empty():
		return {}
	if time <= _times[0]:
		return {"position": _positions[0], "aim": _aims[0]}
	var last := _times.size() - 1
	if time >= _times[last]:
		return {"position": _positions[last], "aim": _aims[last]}

	for i in range(last):
		if _times[i] <= time and time <= _times[i + 1]:
			var span_i := _times[i + 1] - _times[i]
			var t := 0.0 if span_i <= 0.0 else (time - _times[i]) / span_i
			return {
				"position": _positions[i].lerp(_positions[i + 1], t),
				"aim": _aims[i].lerp(_aims[i + 1], t).normalized(),
			}
	return {"position": _positions[last], "aim": _aims[last]}
