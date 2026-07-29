class_name Seats
extends RefCounted

const DRIVER := 0

var _occupants: Array[int] = []


func _init(count: int = 1) -> void:
	resize(count)


func resize(count: int) -> void:
	_occupants = []
	for i in maxi(count, 1):
		_occupants.append(0)


func count() -> int:
	return _occupants.size()


func occupant(seat: int) -> int:
	return _occupants[seat] if seat >= 0 and seat < _occupants.size() else 0


func driver() -> int:
	return occupant(DRIVER)


func seat_of(peer_id: int) -> int:
	if peer_id == 0:
		return -1
	return _occupants.find(peer_id)


func has_peer(peer_id: int) -> bool:
	return seat_of(peer_id) >= 0


func is_free(seat: int) -> bool:
	return seat >= 0 and seat < _occupants.size() and _occupants[seat] == 0


func first_free() -> int:
	return _occupants.find(0)


func occupied_count() -> int:
	var total := 0
	for peer in _occupants:
		if peer != 0:
			total += 1
	return total


func is_empty() -> bool:
	return occupied_count() == 0


func occupants() -> Array[int]:
	var out: Array[int] = []
	for peer in _occupants:
		if peer != 0:
			out.append(peer)
	return out


func take(peer_id: int, seat: int) -> bool:
	if peer_id == 0 or not is_free(seat):
		return false
	release(peer_id)
	_occupants[seat] = peer_id
	return true


func take_first_free(peer_id: int) -> int:
	var seat := first_free()
	if seat < 0 or not take(peer_id, seat):
		return -1
	return seat


func release(peer_id: int) -> void:
	var seat := seat_of(peer_id)
	if seat >= 0:
		_occupants[seat] = 0


func clear() -> void:
	resize(_occupants.size())


func to_array() -> Array[int]:
	return _occupants.duplicate()
