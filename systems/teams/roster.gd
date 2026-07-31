class_name Roster
extends RefCounted

const SQUAD_SIZE := 4
const SQUAD_COUNT := 4
const SLOT_COUNT := SQUAD_SIZE * SQUAD_COUNT
const UNALIGNED := 0

const SQUAD_NAMES := ["Red", "Yellow", "Blue", "Green"]
const SQUAD_COLOURS := [
	Color(0.85, 0.22, 0.20),
	Color(0.90, 0.75, 0.18),
	Color(0.22, 0.45, 0.85),
	Color(0.28, 0.68, 0.32),
]

var _slots: Array[int] = []
var _names: Array[String] = []


func _init() -> void:
	clear()


func clear() -> void:
	_slots = []
	_names = []
	for i in SLOT_COUNT:
		_slots.append(0)
		_names.append("")


const CALLSIGNS := [
	"Alder", "Brack", "Cobb", "Dray",
	"Ewart", "Finch", "Gale", "Hoyt",
	"Ivor", "Jessop", "Kerr", "Lund",
	"Mercer", "Nash", "Oakes", "Pike",
]


static func callsign(slot: int) -> String:
	if slot < 0 or slot >= CALLSIGNS.size():
		return "—"
	return CALLSIGNS[slot]


const NAME_MAX_LENGTH := 14


static func sanitise_name(raw: String) -> String:
	var cleaned := ""
	for character in raw.strip_edges():
		if character.length() != 1 or character.unicode_at(0) < 32:
			continue
		cleaned += character
		if cleaned.length() >= NAME_MAX_LENGTH:
			break
	return cleaned.strip_edges()


func name_of_slot(slot: int) -> String:
	if not is_valid_slot(slot):
		return "—"
	return _names[slot] if _names[slot] != "" else callsign(slot)


func set_slot_name(slot: int, raw: String) -> void:
	if is_valid_slot(slot):
		_names[slot] = sanitise_name(raw)


func name_of(peer_id: int) -> String:
	return name_of_slot(slot_of(peer_id))


static func squad_of_slot(slot: int) -> int:
	return slot / SQUAD_SIZE


static func team_of_slot(slot: int) -> int:
	return 1 + squad_of_slot(slot) / 2


static func squad_name(squad: int) -> String:
	if squad < 0 or squad >= SQUAD_NAMES.size():
		return "None"
	return SQUAD_NAMES[squad]


static func squad_colour(squad: int) -> Color:
	if squad < 0 or squad >= SQUAD_COLOURS.size():
		return Color.WHITE
	return SQUAD_COLOURS[squad]


static func blocks_damage(shooter_team: int, target_team: int) -> bool:
	return shooter_team != UNALIGNED and shooter_team == target_team


func is_valid_slot(slot: int) -> bool:
	return slot >= 0 and slot < SLOT_COUNT


func occupant(slot: int) -> int:
	return _slots[slot] if is_valid_slot(slot) else 0


func is_free(slot: int) -> bool:
	return is_valid_slot(slot) and _slots[slot] == 0


func slot_of(peer_id: int) -> int:
	if peer_id == 0:
		return -1
	return _slots.find(peer_id)


func has_peer(peer_id: int) -> bool:
	return slot_of(peer_id) >= 0


func squad_of(peer_id: int) -> int:
	var slot := slot_of(peer_id)
	return squad_of_slot(slot) if slot >= 0 else -1


func team_of(peer_id: int) -> int:
	var slot := slot_of(peer_id)
	return team_of_slot(slot) if slot >= 0 else UNALIGNED


func assign(peer_id: int, slot: int) -> bool:
	if peer_id == 0 or not is_valid_slot(slot) or not is_free(slot):
		return false
	release(peer_id)
	_slots[slot] = peer_id
	return true


func first_free_slot() -> int:
	return _slots.find(0)


func release(peer_id: int) -> void:
	var slot := slot_of(peer_id)
	if slot >= 0:
		_slots[slot] = 0
		_names[slot] = ""


func occupied_count() -> int:
	var total := 0
	for occupied in _slots:
		if occupied != 0:
			total += 1
	return total


func peers_on_team(team: int) -> Array[int]:
	var out: Array[int] = []
	for slot in SLOT_COUNT:
		if _slots[slot] != 0 and team_of_slot(slot) == team:
			out.append(_slots[slot])
	return out


func squadmates(peer_id: int) -> Array[int]:
	var out: Array[int] = []
	var squad := squad_of(peer_id)
	if squad < 0:
		return out
	for slot in SLOT_COUNT:
		var occupier := _slots[slot]
		if occupier != 0 and occupier != peer_id and squad_of_slot(slot) == squad:
			out.append(occupier)
	return out


func to_array() -> Array[int]:
	return _slots.duplicate()


func names_to_array() -> Array[String]:
	return _names.duplicate()


func names_from_array(values: Array) -> void:
	for i in mini(values.size(), SLOT_COUNT):
		_names[i] = sanitise_name(str(values[i]))


func from_array(values: Array) -> void:
	clear()
	for i in mini(values.size(), SLOT_COUNT):
		_slots[i] = int(values[i])
