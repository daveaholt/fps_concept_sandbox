class_name GunnerZoom
extends Node

const BASE_FOV := 75.0
const ZOOMED_FOV := 34.0
const BLEND_RATE := 12.0

var _fov: float = BASE_FOV


func _process(delta: float) -> void:
	var camera := _active_camera()
	if camera == null:
		_fov = BASE_FOV
		return
	var want := target_fov()
	if is_equal_approx(want, BASE_FOV) and absf(_fov - BASE_FOV) < 0.05:
		_fov = BASE_FOV
		return
	_fov = lerpf(_fov, want, clampf(BLEND_RATE * delta, 0.0, 1.0))
	camera.fov = _fov


func target_fov() -> float:
	if not zooming():
		return BASE_FOV
	return ZOOMED_FOV


func zooming() -> bool:
	var sampler := GameClient.sampler
	if sampler == null or not sampler.can_zoom():
		return false
	return InputFocus.may_act(sampler) and Input.is_action_pressed("zoom")


func _active_camera() -> Camera3D:
	var tree := get_tree()
	if tree == null or tree.root == null:
		return null
	var viewport := tree.root.get_viewport()
	return viewport.get_camera_3d() if viewport != null else null
