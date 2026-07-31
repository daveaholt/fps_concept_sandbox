extends SceneTree

var failures := 0


func _initialize() -> void:
	_check_input_map()
	_check_layers()
	_check_materials()
	_check_sandbox()
	_check_asset_viewer()
	print("\n%s  (%d failures)" % ["PASS" if failures == 0 else "FAIL", failures])
	quit(1 if failures > 0 else 0)


func _ok(condition: bool, label: String, detail := "") -> void:
	if condition:
		print("  ok   %s %s" % [label, detail])
	else:
		failures += 1
		print("  FAIL %s %s" % [label, detail])


func _check_input_map() -> void:
	print("\n[input map — 02]")
	var expected := [
		"toggle_deploy_map", "interact", "ui_cancel",
		"move_forward", "move_back", "move_left", "move_right",
		"jump", "sprint", "fire", "weapon_primary", "weapon_secondary",
		"weapon_cycle_up", "weapon_cycle_down",
		"brake", "exit_vehicle",
		"collective_up", "collective_down",
		"cyclic_forward", "cyclic_back", "cyclic_left", "cyclic_right",
		"toggle_engine", "toggle_camera", "switch_seat", "vehicle_fire", "zoom",
		"deploy_confirm",
	]
	for action in expected:
		var events: Array = InputMap.action_get_events(action) if InputMap.has_action(action) else []
		_ok(InputMap.has_action(action) and events.size() > 0, action, "-> %d event(s)" % events.size())


func _check_layers() -> void:
	print("\n[physics layers — 01]")
	var expected := ["world", "infantry", "vehicle", "projectile", "interact"]
	for i in range(expected.size()):
		var key := "layer_names/3d_physics/layer_%d" % (i + 1)
		var got := str(ProjectSettings.get_setting(key, ""))
		_ok(got == expected[i], key, "= %s" % got)


func _check_materials() -> void:
	print("\n[materials — 09]")
	var dir := DirAccess.open("res://assets/materials")
	var n := 0
	for f in dir.get_files():
		if f.ends_with(".tres"):
			n += 1
			_ok(load("res://assets/materials/" + f) is StandardMaterial3D, f)
	_ok(n >= 10, "shared palette size", "= %d" % n)


func _check_sandbox() -> void:
	print("\n[sandbox graybox — 08 / 11]")
	var scene: PackedScene = load("res://levels/sandbox/sandbox.tscn")
	_ok(scene != null, "sandbox.tscn loads")
	var root := scene.instantiate()
	root.name = "SandboxUnderTest"

	_ok(root.get_node_or_null("WorldEnvironment") != null, "WorldEnvironment present")
	_ok(root.get_node_or_null("Sun") != null, "Sun present")

	var terrain: StaticBody3D = root.get_node("Terrain")
	_ok(terrain.get_node_or_null("Visual") != null, "Terrain/Visual present")

	var meshes_outside := 0
	var generated := 0
	for node in _walk(root):
		if node is MeshInstance3D and not _under_visual(node, root):
			meshes_outside += 1
		if node is CollisionShape3D:
			var s: Shape3D = (node as CollisionShape3D).shape
			if not (s is BoxShape3D or s is CapsuleShape3D or s is SphereShape3D or s is CylinderShape3D):
				generated += 1
	_ok(meshes_outside == 0, "all meshes under Visual", "(%d outside)" % meshes_outside)
	_ok(generated == 0, "all colliders are primitive shapes", "(%d other)" % generated)

	var ground: CollisionShape3D = terrain.get_node("Ground")
	_ok((ground.shape as BoxShape3D).size.x >= 200.0, "ground is ~200 x 200 m",
		"= %v" % (ground.shape as BoxShape3D).size)

	_ok(_is_close(_grade_deg(terrain.get_node("Ramp20")), 20.0), "ramp grade",
		"= %.1f deg" % _grade_deg(terrain.get_node("Ramp20")))
	_ok(_is_close(_grade_deg(terrain.get_node("CrossSlope25")), 25.0), "cross-slope grade",
		"= %.1f deg" % _grade_deg(terrain.get_node("CrossSlope25")))
	_ok(_is_close(_grade_deg(terrain.get_node("HilltopRamp")), 20.0), "hilltop access ramp grade",
		"= %.1f deg" % _grade_deg(terrain.get_node("HilltopRamp")))

	var ramp: CollisionShape3D = terrain.get_node("Ramp20")
	var north_end: Vector3 = ramp.transform * Vector3(0, 0, -10)
	var south_end: Vector3 = ramp.transform * Vector3(0, 0, 10)
	_ok(north_end.y > south_end.y, "ramp climbs north", "(%.2f m rise)" % (north_end.y - south_end.y))

	var hill: CollisionShape3D = terrain.get_node("HilltopMass")
	var top := hill.position.y + (hill.shape as BoxShape3D).size.y * 0.5
	_ok(_is_close(top, 15.0, 0.51), "hilltop pad height", "= %.1f m" % top)

	_ok(terrain.get_node_or_null("AirfieldPad") != null, "airfield pad present")
	_ok(terrain.get_node_or_null("BaseBuildingW") != null, "main base cluster present")
	_ok(terrain.get_node_or_null("WallLong") != null, "walls / cover present")

	var range_root: Node3D = root.get_node("FiringRange")
	var geom: StaticBody3D = range_root.get_node("RangeGeometry")
	var line: Node3D = geom.get_node("Visual/FiringLine")
	for m in [100, 200, 300, 400, 500]:
		var board: Node3D = geom.get_node("Board%d" % m)
		var dist := absf(board.position.z - line.position.z)
		_ok(_is_close(dist, float(m), 0.51), "board %d m" % m, "= %.1f m downrange" % dist)

	_ok(geom.get_node_or_null("GridWall") != null, "grid wall present")
	var grid_lines := 0
	for node in _walk(geom.get_node("Visual")):
		if node.name.begins_with("Grid"):
			grid_lines += 1
	_ok(grid_lines >= 20, "grid wall is painted", "(%d lines)" % grid_lines)

	var dummy: StaticBody3D = range_root.get_node("TargetDummy")
	var dummy_dist := absf(dummy.position.z - line.position.z)
	_ok(_is_close(dummy_dist, 25.0, 0.51), "target dummy at 25 m", "= %.1f m" % dummy_dist)
	_ok(dummy.get_node("BodyShape").shape is CapsuleShape3D, "dummy body is a capsule")
	for zone in ["Head", "Torso", "ArmL", "LegL"]:
		_ok(dummy.get_node_or_null("Visual/" + zone) != null, "dummy zone band: %s" % zone)

	var spawns: Node3D = root.get_node("SpawnPoints")
	for n in ["MainBase", "Hilltop", "Airfield"]:
		var sp := spawns.get_node_or_null(n)
		_ok(sp is SpawnPoint, "spawn point %s" % n,
			"= '%s'" % (sp.display_name if sp is SpawnPoint else "?"))

	_ok(root.get_node_or_null("Vehicles") != null, "Vehicles holder present (M5/M6)")

	root.free()


func _check_asset_viewer() -> void:
	print("\n[asset viewer — 09]")
	var scene: PackedScene = load("res://levels/asset_viewer.tscn")
	_ok(scene != null, "asset_viewer.tscn loads")
	var root := scene.instantiate()
	_ok(root.get_script() != null, "viewer script attached")
	for n in ["Subject", "CollisionGhosts", "OrbitPivot/Camera", "Lights/Key",
			"Lights/Fill", "Lights/Back", "Floor/Grid", "Floor/ForwardArrow",
			"Reference/MeterCube", "Reference/PersonCapsule", "UI/Panel/GhostToggle"]:
		_ok(root.get_node_or_null(n) != null, n)
	root.free()


func _grade_deg(node: Node3D) -> float:
	return rad_to_deg((node.transform.basis * Vector3.UP).angle_to(Vector3.UP))


func _is_close(a: float, b: float, eps := 0.05) -> bool:
	return absf(a - b) <= eps


func _under_visual(node: Node, root: Node) -> bool:
	var n := node.get_parent()
	while n != null and n != root.get_parent():
		if n.name == "Visual":
			return true
		n = n.get_parent()
	return false


func _walk(root: Node) -> Array[Node]:
	var out: Array[Node] = []
	var stack: Array[Node] = [root]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		out.append(node)
		for child in node.get_children():
			stack.append(child)
	return out
