extends SceneTree

var _level: Node
var _t := 0
var _fail := 0
var _spawn := {}


func _ok(label: String, cond: bool, detail: String = "") -> void:
	if not cond:
		_fail += 1
	print("%s %s%s" % ["PASS" if cond else "FAIL", label, "  " + detail if detail != "" else ""])


func _initialize() -> void:
	_level = load("res://levels/sandbox/sandbox.tscn").instantiate()
	root.add_child(_level)


func _physics_process(_d: float) -> bool:
	_t += 1
	if _t == 5:
		for vehicle in _level.get_node("Vehicles").get_children():
			_spawn[vehicle.name] = vehicle.global_position
		return false
	if _t < 200:
		return false

	var vehicles: Array = _level.get_node("Vehicles").get_children()
	_ok("the map carries two tanks and two helicopters", vehicles.size() == 4,
		"%d vehicles" % vehicles.size())

	var names: Array = []
	for vehicle in vehicles:
		names.append(vehicle.name)
	_ok("every vehicle has a unique name", names.size() == _unique(names).size(),
		str(names))

	for vehicle in vehicles:
		var started: Vector3 = _spawn[vehicle.name]
		var now: Vector3 = vehicle.global_position
		_ok("%s settles instead of falling" % vehicle.name,
			absf(now.y - started.y) < 1.5,
			"y %.2f -> %.2f after %d ticks" % [started.y, now.y, _t])
		_ok("%s stays where it was placed" % vehicle.name,
			Vector2(now.x - started.x, now.z - started.z).length() < 2.0,
			"drifted %.2f m" % Vector2(now.x - started.x, now.z - started.z).length())
		var up: Vector3 = vehicle.global_transform.basis.y
		_ok("%s rests level" % vehicle.name, up.dot(Vector3.UP) > 0.98,
			"tilt %.1f deg" % rad_to_deg(acos(clampf(up.dot(Vector3.UP), -1.0, 1.0))))

	for i in vehicles.size():
		for j in range(i + 1, vehicles.size()):
			var a = vehicles[i]
			var b = vehicles[j]
			var gap: float = a.global_position.distance_to(b.global_position)
			if gap > 60.0:
				continue
			_ok("%s and %s are not stacked" % [a.name, b.name], gap > 12.0,
				"%.1f m apart" % gap)

	print("placement: %d failing" % _fail)
	quit(1 if _fail > 0 else 0)
	return true


func _unique(items: Array) -> Array:
	var seen: Array = []
	for item in items:
		if not seen.has(item):
			seen.append(item)
	return seen
