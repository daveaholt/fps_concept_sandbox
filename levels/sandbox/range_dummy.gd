extends StaticBody3D

@export var tuning: InfantryTuning
@export var hit_zones: HitZones
@export var facing: Vector3 = Vector3(0, 0, 1)

var owner_peer: int = -1

var _history := PositionHistory.new()
var _damage_taken: float = 0.0


func _ready() -> void:
	if tuning == null:
		tuning = InfantryTuning.new()
	_history.push(0.0, global_position, facing)
	_history.push(1e9, global_position, facing)
	if GameServer.ballistics != null:
		GameServer.ballistics.register_target(self)


func get_history() -> PositionHistory:
	return _history


func team_id() -> int:
	return Roster.UNALIGNED


func apply_damage(amount: float) -> void:
	_damage_taken += amount


func damage_taken() -> float:
	return _damage_taken
