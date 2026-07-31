extends SceneTree

var failures := 0
var _level: Node
var _tank: VehicleBody3D
var _t := 0

func _ok(c: bool, label: String, detail := "") -> void:
	if c: print("  ok   %s %s" % [label, detail])
	else:
		failures += 1
		print("  FAIL %s %s" % [label, detail])

func _initialize() -> void:
	_level = load("res://levels/sandbox/sandbox.tscn").instantiate()
	root.add_child(_level)
	_tank = _level.get_node("Vehicles/Tank")
	print("[05 - at full elevation the gunner must see what the reticle is on]")

func _physics_process(_d: float) -> bool:
	_t += 1
	if _t < 40:
		return false

	var cam_hi: float = _tank.camera_pitch_max_deg
	var cam_lo: float = _tank.camera_pitch_min_deg
	var gun_hi: float = _tank.cannon_pitch_max_deg
	var gun_lo: float = _tank.cannon_pitch_min_deg
	_ok(cam_hi <= gun_hi, "camera cannot look higher than the gun can elevate",
		"camera +%.0f vs gun +%.0f" % [cam_hi, gun_hi])
	_ok(cam_lo >= gun_lo, "camera cannot look lower than the gun can depress",
		"camera %.0f vs gun %.0f" % [cam_lo, gun_lo])

	var hull_y: float = _tank.global_position.y
	var arm: float = _tank.camera_spring_length
	var pivot: float = _tank.camera_pivot_height
	var theta := deg_to_rad(cam_hi)
	var arm_pitch: float = minf(theta, 0.0)

	var roof := -999.0
	for node in _tank.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		if mi.mesh == null:
			continue
		var box: AABB = mi.global_transform * mi.mesh.get_aabb()
		roof = maxf(roof, box.end.y)
	var rear: float = _tank.hit_half_extents().z

	var cam_h: float = hull_y + pivot - arm * sin(arm_pitch)
	var cam_back: float = arm * cos(arm_pitch)
	_ok(cam_h > roof - 0.4, "looking fully up keeps the camera near the hull roof",
		"camera %.2f m vs roof %.2f m" % [cam_h, roof])

	var sight_at_rear: float = cam_h + (cam_back - rear) * tan(theta)
	_ok(sight_at_rear > roof + 0.3, "the sight line clears the tank's own hull at full elevation",
		"line is %.2f m at the rear face, roof is %.2f m" % [sight_at_rear, roof])
	print("   tank stands %.2f m tall, belly %.2f m off the ground"
		% [roof - (hull_y - 0.59), hull_y + 0.2])

	var turret: Node3D = _tank.get_node("TurretYaw")
	var parallax: float = pivot - turret.position.y
	_ok(absf(parallax) <= 0.6, "camera sits close to the gun line so the barrel reads on the reticle",
		"%.2f m above the turret axis" % parallax)

	print("\n%s  (%d failures)" % ["PASS" if failures == 0 else "FAIL", failures])
	quit(1 if failures > 0 else 0)
	return true
