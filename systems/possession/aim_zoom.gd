class_name AimZoom
extends Node

const BLEND_RATE := 12.0

var _fov: float = ZoomOptics.BASE_FOV


func _process(delta: float) -> void:
	var camera := _active_camera()
	if camera == null:
		_fov = ZoomOptics.BASE_FOV
		return
	var want := target_fov()
	var at_rest := absf(_fov - ZoomOptics.BASE_FOV) < 0.05
	if is_equal_approx(want, ZoomOptics.BASE_FOV) and at_rest:
		_fov = ZoomOptics.BASE_FOV
		return
	_fov = lerpf(_fov, want, clampf(BLEND_RATE * delta, 0.0, 1.0))
	camera.fov = _fov


func sensitivity_scale() -> float:
	return ZoomOptics.sensitivity_for(_fov)


func aiming() -> bool:
	var sampler := GameClient.sampler
	if sampler == null or not sampler.can_zoom():
		return false
	return InputFocus.may_act(sampler) and Input.is_action_pressed("zoom")


func target_fov() -> float:
	if not aiming():
		return ZoomOptics.BASE_FOV
	var sampler := GameClient.sampler
	if sampler != null and sampler.vehicle_seat() >= Seats.DRIVER:
		return ZoomOptics.VEHICLE_FOV
	return infantry_fov()


func infantry_fov() -> float:
	var entity: Node = GameClient.my_entity
	if entity == null or not is_instance_valid(entity):
		return ZoomOptics.BASE_FOV
	if not entity.has_method("get_active_weapon"):
		return ZoomOptics.BASE_FOV
	var weapon: WeaponDef = entity.get_active_weapon()
	return weapon.ads_fov if weapon != null else ZoomOptics.BASE_FOV


func _active_camera() -> Camera3D:
	var tree := get_tree()
	if tree == null or tree.root == null:
		return null
	var viewport := tree.root.get_viewport()
	return viewport.get_camera_3d() if viewport != null else null
