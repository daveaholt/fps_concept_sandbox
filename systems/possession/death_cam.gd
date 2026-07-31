class_name DeathCam
extends Node3D

const BACK_OFF := 5.5
const RISE := 3.2
const ORBIT_DEG_PER_SECOND := 14.0
const LOOK_HEIGHT := 1.0

var _camera: Camera3D
var _focus := Vector3.ZERO
var _angle := 0.0
var _active := false


func _ready() -> void:
	_camera = Camera3D.new()
	_camera.name = "Camera3D"
	_camera.cull_mask = 1048573
	_camera.far = 2000.0
	_camera.current = false
	add_child(_camera)
	set_process(true)


func begin(focus: Vector3, facing: float) -> void:
	_focus = focus
	_angle = facing
	_active = true
	_camera.current = true
	_place()


func stop() -> void:
	if not _active:
		return
	_active = false
	_camera.current = false


func is_active() -> bool:
	return _active


func focus_point() -> Vector3:
	return _focus


func _process(delta: float) -> void:
	if not _active:
		return
	_angle += deg_to_rad(ORBIT_DEG_PER_SECOND) * delta
	_place()


func _place() -> void:
	var offset := Vector3(sin(_angle) * BACK_OFF, RISE, cos(_angle) * BACK_OFF)
	_camera.global_position = _focus + offset
	_camera.look_at(_focus + Vector3.UP * LOOK_HEIGHT, Vector3.UP)
