extends Node3D

@export var gravity: float = 20.0
@export var bounds_center: Vector3 = Vector3.ZERO
@export var bounds_extents: Vector2 = Vector2(40.0, 40.0)
@export var radius: float = 1.0
@export var initial_velocity: Vector3 = Vector3(11.0, 0.0, 7.0)

var _vel: Vector3
var _log_countdown: int = 0


func _ready() -> void:
	_vel = initial_velocity


func _physics_process(delta: float) -> void:
	_log_tick()
	if not _is_authority():
		return

	_vel.y -= gravity * delta
	var p := position + _vel * delta
	var floor_y := bounds_center.y + radius

	if p.y <= floor_y:
		p.y = floor_y
		_vel.y = absf(_vel.y)

	var half_x := bounds_extents.x
	var half_z := bounds_extents.y
	if absf(p.x - bounds_center.x) > half_x:
		p.x = bounds_center.x + signf(p.x - bounds_center.x) * half_x
		_vel.x = -_vel.x
	if absf(p.z - bounds_center.z) > half_z:
		p.z = bounds_center.z + signf(p.z - bounds_center.z) * half_z
		_vel.z = -_vel.z

	position = p
	sync_position.rpc(p)


func _is_authority() -> bool:
	if multiplayer.multiplayer_peer == null:
		return true
	return multiplayer.is_server()


@rpc("authority", "call_remote", "unreliable")
func sync_position(p: Vector3) -> void:
	position = p


func _log_tick() -> void:
	if not NetCli.is_net_log():
		return
	_log_countdown -= 1
	if _log_countdown > 0:
		return
	_log_countdown = 60
	print("[ball] %s pos=%v" % ["authoritative" if _is_authority() else "replicated", position])
