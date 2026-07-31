extends SceneTree

var _level: Node
var _t := 0
var _fail := 0
var _tuning: InfantryTuning
var _space: PhysicsDirectSpaceState3D


func _ok(label: String, cond: bool, detail: String = "") -> void:
	if not cond:
		_fail += 1
	print("%s %s%s" % ["PASS" if cond else "FAIL", label, "  " + detail if detail != "" else ""])


func _initialize() -> void:
	_level = load("res://levels/sandbox/sandbox.tscn").instantiate()
	root.add_child(_level)


func _physics_process(_d: float) -> bool:
	_t += 1
	if _t < 20:
		return false
	var body: Node3D = load("res://entities/player/player.tscn").instantiate()
	_level.get_node("Players").add_child(body)
	_tuning = body.tuning
	_space = body.get_world_3d().direct_space_state

	_check_slows_you()
	_check_replay_safe()
	_check_optics()

	print("ads: %d failing" % _fail)
	quit(1 if _fail > 0 else 0)
	return true


func _run(buttons: int, steps: int) -> InfantryState:
	var s := InfantryState.new()
	s.arm(_tuning)
	s.position = Vector3(0.0, 1.0, 0.0)
	s.on_floor = true
	for i in steps:
		var cmd := InputCommand.make(i + 1, Vector2(0.0, 1.0), buttons, Vector3.FORWARD)
		s = InfantrySim.simulate(s, cmd, _tuning, _space, 1.0 / 60.0)
	return s


func _check_slows_you() -> void:
	var walk := _run(0, 60)
	var aimed := _run(InputCommand.ADS, 60)
	var walk_speed := Vector2(walk.velocity.x, walk.velocity.z).length()
	var aim_speed := Vector2(aimed.velocity.x, aimed.velocity.z).length()

	_ok("aiming slows you down", aim_speed < walk_speed,
		"%.2f vs %.2f m/s" % [aim_speed, walk_speed])
	_ok("by the tuned fraction",
		absf(aim_speed - walk_speed * _tuning.ads_speed_scale) < 0.2,
		"expected about %.2f" % (walk_speed * _tuning.ads_speed_scale))

	var sprint := _run(InputCommand.SPRINT, 60)
	var sprint_aimed := _run(InputCommand.SPRINT | InputCommand.ADS, 60)
	_ok("you cannot outrun the slowdown by sprinting",
		Vector2(sprint_aimed.velocity.x, sprint_aimed.velocity.z).length()
		< Vector2(sprint.velocity.x, sprint.velocity.z).length(),
		"aiming beats sprinting")


func _check_replay_safe() -> void:
	var commands: Array = []
	for i in 120:
		var buttons := InputCommand.ADS if (i / 20) % 2 == 0 else 0
		commands.append(InputCommand.make(i + 1, Vector2(0.3, 1.0), buttons,
			Vector3.FORWARD))

	var first := InfantryState.new()
	first.arm(_tuning)
	first.on_floor = true
	var second := first.clone()
	for cmd in commands:
		first = InfantrySim.simulate(first, cmd, _tuning, _space, 1.0 / 60.0)
	for cmd in commands:
		second = InfantrySim.simulate(second, cmd, _tuning, _space, 1.0 / 60.0)
	_ok("toggling ADS replays identically",
		first.position.distance_to(second.position) < 0.0001,
		"the flag rides the command, so no new state to reconcile")


func _check_optics() -> void:
	var rifle: WeaponDef = _tuning.weapon_at(0)
	var pistol: WeaponDef = _tuning.weapon_at(1)
	_ok("every weapon defines its own aimed field of view",
		rifle.ads_fov > 0.0 and pistol.ads_fov > 0.0,
		"rifle %.0f, pistol %.0f" % [rifle.ads_fov, pistol.ads_fov])
	_ok("aiming narrows the view", rifle.ads_fov < ZoomOptics.BASE_FOV,
		"%.0f from %.0f" % [rifle.ads_fov, ZoomOptics.BASE_FOV])
	_ok("the rifle magnifies more than the pistol", rifle.ads_fov < pistol.ads_fov)

	_ok("sensitivity is unscaled at rest",
		is_equal_approx(ZoomOptics.sensitivity_for(ZoomOptics.BASE_FOV), 1.0))
	var scaled := ZoomOptics.sensitivity_for(rifle.ads_fov)
	_ok("sensitivity scales with magnification",
		absf(scaled - rifle.ads_fov / ZoomOptics.BASE_FOV) < 0.001,
		"x%.2f — without this, aiming in makes aiming harder" % scaled)
	_ok("the rifle magnifies about twice",
		absf(ZoomOptics.magnification(rifle.ads_fov) - 2.0) < 0.1,
		"x%.2f" % ZoomOptics.magnification(rifle.ads_fov))
