extends SceneTree

var _level: Node
var _t := 0
var _fail := 0
var _gs
var _tank
var _heli


func _ok(label: String, cond: bool, detail: String = "") -> void:
	if not cond:
		_fail += 1
	print("%s %s%s" % ["PASS" if cond else "FAIL", label, "  " + detail if detail != "" else ""])


func _initialize() -> void:
	_level = load("res://levels/sandbox/sandbox.tscn").instantiate()
	root.add_child(_level)


func _physics_process(_d: float) -> bool:
	_t += 1
	if _t == 20:
		_setup()
		return false
	if _t == 40:
		_check_cameras()
		_check_slew()
		_check_replication()
		print("gunner view: %d failing" % _fail)
		quit(1 if _fail > 0 else 0)
		return true
	return false


func _setup() -> void:
	_gs = root.get_node_or_null("/root/GameServer")
	_tank = _level.get_node("Vehicles/Tank")
	_heli = _level.get_node("Vehicles/Helicopter")
	_gs.is_active = true
	_gs.phase = _gs.Phase.PLAYING
	_tank.take_seat(11)
	_tank.take_seat(22)
	_heli.take_seat(33)
	_heli.take_seat(44, 1)


func _check_cameras() -> void:
	for pair in [[_tank, "tank"], [_heli, "heli"]]:
		var vehicle = pair[0]
		var name: String = pair[1]
		_ok("%s scene has a gunner rig" % name,
			vehicle.get_node_or_null("GunnerRig/Camera3D") is Camera3D)
		var rig: Node3D = vehicle.get_node_or_null("GunnerRig")
		_ok("%s gunner rig is top_level" % name, rig != null and rig.top_level,
			"else it inherits hull roll")

		vehicle.possess()
		vehicle.set_local_aim(Vector3(0, 0, -1), 0)
		var driver_cam: Camera3D = vehicle.get_node_or_null("GunnerRig/Camera3D")
		_ok("%s driver does not get the gunner camera" % name, not driver_cam.current)

		vehicle.set_local_aim(Vector3(1, 0, 0), 1)
		_ok("%s gunner gets the gunner camera" % name, driver_cam.current)
		if name == "tank":
			var seat_cam: Camera3D = vehicle.get_node_or_null(
				"SeatCameraRig/SpringArm3D/Camera3D")
			_ok("tank driver camera yields to the gunner", not seat_cam.current)
		else:
			var cockpit: Camera3D = vehicle.get_node_or_null("CockpitCam")
			_ok("heli cockpit camera yields to the gunner", not cockpit.current)

		vehicle.unpossess()
		_ok("%s gunner camera released on exit" % name, not driver_cam.current)


func _check_slew() -> void:
	for pair in [[_tank, "tank"], [_heli, "heli"]]:
		var vehicle = pair[0]
		var name: String = pair[1]
		var before: Vector2 = vehicle.gun_angles()
		for _i in 40:
			vehicle.slew_gun(Vector3(1, 0, 0), 1.0 / 60.0)
		var after: Vector2 = vehicle.gun_angles()
		_ok("%s gun slews toward a side aim" % name, absf(after.x - before.x) > 0.05,
			"yaw %.3f -> %.3f rad" % [before.x, after.x])

		var rig: Node3D = vehicle.get_node_or_null("GunnerRig")
		vehicle.possess()
		vehicle.set_local_aim(Vector3(1, 0, 0), 1)
		vehicle._update_gunner_camera()
		var facing := -rig.global_transform.basis.z
		_ok("%s gunner view follows the aim, not the hull" % name,
			facing.dot(Vector3(1, 0, 0)) > 0.9,
			"facing %.2f,%.2f,%.2f" % [facing.x, facing.y, facing.z])

		var ray: Array = vehicle.weapon_ray(1)
		var to_reticle: Vector3 = (ray[1] as Vector3)
		_ok("%s reticle ray lands ahead of the gunner view" % name,
			to_reticle.dot(facing) > 0.5,
			"dot %.2f" % to_reticle.dot(facing))
		vehicle.unpossess()


func _check_replication() -> void:
	for pair in [[_tank, "tank"], [_heli, "heli"]]:
		var vehicle = pair[0]
		var name: String = pair[1]
		var wire: Dictionary = vehicle.get_net_state()
		_ok("%s replicates gun yaw" % name, wire.has("gy"))
		_ok("%s replicates gun pitch" % name, wire.has("gp"))
		_ok("%s replicates gun heat" % name, wire.has("gh"),
			"else a client's readout is pinned at 0")
	_check_distinct_rounds()
	_check_slew_keeps_up()
	_check_eye_clears_the_gun()
	_check_swap_contract()
	_check_shell_only_hides_from_inside()
	_check_first_person()
	_check_hull_indicator()


func _check_distinct_rounds() -> void:
	var manager = _gs.ballistics
	var mg: ProjectileParams = manager.params_for(_tank.gun_params_id)
	var rifle: ProjectileParams = manager.params_for(1)
	if rifle == null:
		_ok("rifle params reachable for comparison", false)
		return
	var same_colour := mg.tracer_colour.is_equal_approx(rifle.tracer_colour)
	_ok("minigun tracer is not the rifle colour", not same_colour,
		"mg %s vs rifle %s" % [mg.tracer_colour, rifle.tracer_colour])
	var hue_gap := absf(mg.tracer_colour.h - rifle.tracer_colour.h) 		+ absf(mg.tracer_length - rifle.tracer_length) / 10.0
	_ok("minigun reads as a distinct round", hue_gap > 0.15, "separation %.2f" % hue_gap)
	_ok("minigun outruns the rifle rate", _tank.gun_rate_per_second >= 16.0,
		"%.0f rounds/s" % _tank.gun_rate_per_second)


func _check_slew_keeps_up() -> void:
	var look_speed := 200.0
	for pair in [[_tank, "tank"], [_heli, "heli"]]:
		_ok("%s gun slews at least as fast as stick look" % pair[1],
			pair[0].gun_slew_deg >= look_speed,
			"%.0f deg/s gun vs %.0f deg/s look" % [pair[0].gun_slew_deg, look_speed])
	_ok("heli gun can depress for air-to-ground", _heli.gun_pitch_min_deg <= -60.0,
		"%.0f deg" % _heli.gun_pitch_min_deg)


func _check_eye_clears_the_gun() -> void:
	for pair in [[_tank, "tank"], [_heli, "heli"]]:
		var vehicle = pair[0]
		var name: String = pair[1]
		var eye: Vector3 = vehicle.gunner_eye()
		var muzzle: Node3D = vehicle.get_node_or_null("GunYaw/GunPitch/Muzzle")
		var to_gun: Vector3 = muzzle.global_position - eye
		var drop := rad_to_deg(asin(clampf(-to_gun.normalized().dot(Vector3.UP), -1.0, 1.0)))
		_ok("%s gun sits well below the gunner's eyeline" % name, drop > 20.0,
			"%.0f deg below centre" % drop)

	var canopy: MeshInstance3D = _heli.get_node_or_null("Visual/Canopy")
	var box: AABB = canopy.global_transform * canopy.mesh.get_aabb()
	var eye: Vector3 = _heli.gunner_eye()
	_ok("heli gunner eye is inside the canopy, not behind it", box.has_point(eye),
		"eye %.2f,%.2f,%.2f vs canopy %s" % [eye.x, eye.y, eye.z, box])
	var glass: StandardMaterial3D = canopy.mesh.material
	_ok("canopy glass is actually transparent",
		glass.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED and glass.albedo_color.a < 0.5,
		"alpha %.2f" % glass.albedo_color.a)


func _check_swap_contract() -> void:
	for pair in [[_tank, "tank"], [_heli, "heli"]]:
		var vehicle = pair[0]
		var name: String = pair[1]
		_ok("%s declares its gunner eye as a marker, not a script constant" % name,
			vehicle.get_node_or_null("GunnerEye") is Marker3D)
		var common = vehicle.common()
		_ok("%s tags shell meshes for occupant hiding" % name,
			common.shell_mesh_count() > 0, "%d meshes" % common.shell_mesh_count())

		common.set_shell_hidden(true)
		var hidden_ok := true
		var shown_ok := true
		for mesh in vehicle.find_children("*", "VisualInstance3D", true, false):
			if mesh.is_in_group(RenderLayers.SHELL_GROUP) 					and mesh.layers != RenderLayers.OWNER_HIDDEN:
				hidden_ok = false
		_ok("%s shell moves to the hidden layer for occupants" % name, hidden_ok)

		common.set_shell_hidden(false)
		for mesh in vehicle.find_children("*", "VisualInstance3D", true, false):
			if mesh.is_in_group(RenderLayers.SHELL_GROUP) 					and mesh.layers != RenderLayers.WORLD_VISIBLE:
				shown_ok = false
		_ok("%s shell returns to the world layer" % name, shown_ok)

		for cam in vehicle.find_children("*", "Camera3D", true, false):
			_ok("%s camera %s excludes the hidden layer" % [name, cam.name],
				(cam.cull_mask & RenderLayers.OWNER_HIDDEN) == 0)

		_ok("%s weapon meshes stay visible to the occupant" % name,
			not vehicle.get_node("GunYaw/GunPitch/Visual/Barrel").is_in_group(
				RenderLayers.SHELL_GROUP),
			"the gunner must still see the gun being aimed")


func _check_shell_only_hides_from_inside() -> void:
	for pair in [[_tank, "tank"], [_heli, "heli"]]:
		var vehicle = pair[0]
		var name: String = pair[1]
		var common = vehicle.common()

		vehicle.unpossess()
		_ok("%s is visible when nobody is aboard" % name, not common.shell_hidden())

		vehicle.possess()
		vehicle.set_local_aim(Vector3(0, 0, -1), 0)
		vehicle._update_camera() if name == "tank" else vehicle._update_cameras(0.016)
		vehicle._refresh_shell()
		_ok("%s driver keeps sight of their own vehicle" % name,
			not common.shell_hidden() or name == "heli",
			"third-person seat must not blank the hull")

		vehicle.set_local_aim(Vector3(0, 0, -1), 1)
		vehicle._update_gunner_camera()
		vehicle._refresh_shell()
		var eye_inside: bool = common.encloses(vehicle.gunner_eye())
		_ok("%s hides the shell only when the eye is inside it" % name,
			common.shell_hidden() == eye_inside,
			"eye inside %s, hidden %s" % [eye_inside, common.shell_hidden()])

		vehicle.unpossess()
		_ok("%s is visible again after the occupant leaves" % name,
			not common.shell_hidden())

	_ok("the tank gunner sits outside the hull, so the tank stays drawn",
		not _tank.common().encloses(_tank.gunner_eye()))
	_ok("the heli gunner sits inside the fuselage, so it is culled",
		_heli.common().encloses(_heli.gunner_eye()))


func _check_first_person() -> void:
	var eye: Marker3D = _tank.get_node_or_null("TurretYaw/CannonPitch/DriverEye")
	_ok("tank declares a driver eye marker", eye is Marker3D)
	var cam: Camera3D = _tank.get_node_or_null("TurretYaw/CannonPitch/DriverEye/Camera3D")
	_ok("tank first-person camera hangs off the cannon", cam is Camera3D,
		"so it inherits turret traverse and gun elevation")
	_ok("first-person camera excludes the hidden layer",
		(cam.cull_mask & RenderLayers.OWNER_HIDDEN) == 0)

	var chase: Camera3D = _tank.get_node_or_null("SeatCameraRig/SpringArm3D/Camera3D")
	_tank.possess()
	_tank.set_local_aim(Vector3(0, 0, -1), 0)
	_ok("tank starts in the chase view", chase.current and not cam.current)

	_tank.toggle_camera()
	_ok("toggle switches to first person", cam.current and not chase.current)
	_ok("first person reports itself", _tank.using_first_person())

	var view := -cam.global_transform.basis.z
	var ray: Array = _tank.weapon_ray(0)
	var barrel: Vector3 = ray[1]
	_ok("the first-person view looks along the cannon", view.dot(barrel) > 0.999,
		"dot %.4f — the reticle should sit centred" % view.dot(barrel))

	_tank.common().set_shell_hidden(false)
	_tank._refresh_shell()
	_ok("first person culls the hull from inside", _tank.common().shell_hidden(),
		"eye is inside the turret")

	_tank.toggle_camera()
	_tank._refresh_shell()
	_ok("toggling back restores the chase view", chase.current and not cam.current)
	_ok("toggling back restores the hull", not _tank.common().shell_hidden())
	_tank.unpossess()


func _check_hull_indicator() -> void:
	var glyph := HullIndicator.new()
	root.add_child(glyph)
	var cam: Camera3D = _tank.get_node("TurretYaw/CannonPitch/DriverEye/Camera3D")
	_tank._cannon_pitch_angle = 0.0
	for degrees in [0.0, 35.0, 90.0, -120.0, 179.0]:
		_tank._turret_yaw_angle = deg_to_rad(degrees)
		_tank._apply_turret()
		glyph.set_hull_angle(_tank.turret_angles().x)
		var hull_forward: Vector3 = -_tank.global_transform.basis.z
		var in_view: Vector3 = cam.global_transform.basis.inverse() * hull_forward
		var expected := Vector2(in_view.x, in_view.z).normalized()
		var got: Vector2 = glyph.forward()
		_ok("hull glyph points where the hull points, turret at %.0f deg" % degrees,
			got.distance_to(expected) < 0.02,
			"glyph (%.2f, %.2f) vs hull (%.2f, %.2f)" % [got.x, got.y,
				expected.x, expected.y])
	_tank._turret_yaw_angle = 0.0
	_tank._apply_turret()
	glyph.set_hull_angle(0.0)
	_ok("glyph is upright when the turret faces forward",
		is_zero_approx(glyph.forward().x) and glyph.forward().y < 0.0)
	glyph.free()
