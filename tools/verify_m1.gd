extends SceneTree

const TICK := 1.0 / 60.0
const FORWARD := Vector3(0, 0, -1)
const EAST := Vector3(1, 0, 0)

var failures := 0
var _warmup := 0
var _level: Node = null
var _tuning: InfantryTuning
var _space: PhysicsDirectSpaceState3D


func _initialize() -> void:
	_level = load("res://levels/sandbox/sandbox.tscn").instantiate()
	root.add_child(_level)
	_tuning = load("res://entities/player/player_tuning.tres")
	_tuning.gravity = ProjectSettings.get_setting("physics/3d/default_gravity", 9.8)


func _physics_process(_delta: float) -> bool:
	_warmup += 1
	if _warmup < 5:
		return false

	_space = _level.get_viewport().world_3d.direct_space_state
	_check_purity()
	_check_ground_and_walk()
	_check_sprint()
	_check_jump()
	_check_wall()
	_check_ramp()
	_check_weapons()
	_check_spawn_recovery()

	print("\n%s  (%d failures)" % ["PASS" if failures == 0 else "FAIL", failures])
	quit(1 if failures > 0 else 0)
	return true


func _ok(condition: bool, label: String, detail := "") -> void:
	if condition:
		print("  ok   %s %s" % [label, detail])
	else:
		failures += 1
		print("  FAIL %s %s" % [label, detail])


func _cmd(move: Vector2, aim: Vector3, buttons := 0) -> InputCommand:
	return InputCommand.make(0, move, buttons, aim)


func _run(state: InfantryState, cmd: InputCommand, seconds: float) -> InfantryState:
	var s := state
	for _i in range(int(seconds / TICK)):
		s = InfantrySim.simulate(s, cmd, _tuning, _space, TICK)
	return s


func _settle(at: Vector3, seconds := 2.0) -> InfantryState:
	var s := InfantryState.new()
	s.position = at
	return _run(s, _cmd(Vector2.ZERO, FORWARD), seconds)


func _check_purity() -> void:
	print("\n[sim purity — 01 / 10 / M1 gate]")
	var banned := ["Input.", "EventBus", "get_node", "get_tree", "$"]
	for path in ["res://entities/player/infantry_sim.gd", "res://entities/player/infantry_state.gd",
			"res://entities/player/infantry_tuning.gd"]:
		var text := FileAccess.get_file_as_string(path)
		var hits: Array[String] = []
		for token in banned:
			if text.contains(token):
				hits.append(token)
		_ok(hits.is_empty(), path.get_file(), "" if hits.is_empty() else "contains %s" % str(hits))


func _check_ground_and_walk() -> void:
	print("\n[grounding and walk speed — 03]")
	var s := _settle(Vector3(0, 3, -150))
	_ok(s.on_floor, "settles on the range floor", "y=%.3f" % s.position.y)
	_ok(absf(s.position.y) < 0.05, "rests at ground height", "y=%.3f" % s.position.y)

	var walked := _run(s, _cmd(Vector2(0, 1), FORWARD), 2.0)
	var speed := Vector3(walked.velocity.x, 0, walked.velocity.z).length()
	_ok(absf(speed - _tuning.walk_speed) < 0.15, "walk speed",
		"%.2f m/s (target %.1f)" % [speed, _tuning.walk_speed])
	_ok(walked.position.z < s.position.z - 8.0, "walks toward -Z",
		"travelled %.1f m" % (s.position.z - walked.position.z))

	var stopped := _run(walked, _cmd(Vector2.ZERO, FORWARD), 1.0)
	var residual := Vector3(stopped.velocity.x, 0, stopped.velocity.z).length()
	_ok(residual < 0.01, "stops when input released", "%.4f m/s" % residual)


func _check_sprint() -> void:
	print("\n[sprint gating — 03]")
	var s := _settle(Vector3(0, 3, -150))
	var fwd := _run(s, _cmd(Vector2(0, 1), FORWARD, InputCommand.SPRINT), 2.0)
	var fwd_speed := Vector3(fwd.velocity.x, 0, fwd.velocity.z).length()
	_ok(absf(fwd_speed - _tuning.sprint_speed) < 0.15, "sprint forward reaches sprint_speed",
		"%.2f m/s (target %.1f)" % [fwd_speed, _tuning.sprint_speed])

	var side := _run(s, _cmd(Vector2(1, 0), FORWARD, InputCommand.SPRINT), 2.0)
	var side_speed := Vector3(side.velocity.x, 0, side.velocity.z).length()
	_ok(absf(side_speed - _tuning.walk_speed) < 0.15, "sprint sideways stays at walk_speed",
		"%.2f m/s" % side_speed)


func _check_jump() -> void:
	print("\n[jump — 03]")
	var s := _settle(Vector3(0, 3, -150))
	var base_y := s.position.y
	var peak := base_y
	var cur := s
	var jump_cmd := _cmd(Vector2.ZERO, FORWARD, InputCommand.JUMP)
	cur = InfantrySim.simulate(cur, jump_cmd, _tuning, _space, TICK)
	for _i in range(120):
		cur = InfantrySim.simulate(cur, _cmd(Vector2.ZERO, FORWARD), _tuning, _space, TICK)
		peak = maxf(peak, cur.position.y)
		if cur.on_floor and cur.position.y <= base_y + 0.001:
			break
	var apex := peak - base_y
	var expected := _tuning.jump_velocity * _tuning.jump_velocity / (2.0 * _tuning.gravity_accel())
	_ok(absf(apex - expected) < 0.12, "jump apex", "%.2f m (expected %.2f)" % [apex, expected])
	_ok(cur.on_floor, "lands again", "y=%.3f" % cur.position.y)


func _check_wall() -> void:
	print("\n[wall collision — 03]")
	var s := _settle(Vector3(0, 3, -150))
	var pushed := _run(s, _cmd(Vector2(0, 1), EAST), 6.0)
	_ok(pushed.position.x < 30.0, "stopped by the lane wall at x=30",
		"x=%.2f" % pushed.position.x)
	_ok(pushed.position.x > 26.0, "reached the wall rather than snagging early",
		"x=%.2f" % pushed.position.x)


func _check_ramp() -> void:
	print("\n[slopes — 03]")
	var on_ramp := _settle(Vector3(38, 8, 28), 3.0)
	_ok(on_ramp.on_floor, "lands on the 20 deg ramp", "y=%.2f" % on_ramp.position.y)
	var grade := rad_to_deg(on_ramp.floor_normal.angle_to(Vector3.UP))
	_ok(absf(grade - 20.0) < 1.5, "reports the ramp grade", "%.1f deg" % grade)

	var idle := _run(on_ramp, _cmd(Vector2.ZERO, FORWARD), 3.0)
	var drift := Vector2(idle.position.x - on_ramp.position.x, idle.position.z - on_ramp.position.z).length()
	_ok(drift < 0.05, "no sliding when standing still on 20 deg", "drift %.4f m" % drift)

	var climbed := _run(on_ramp, _cmd(Vector2(0, 1), FORWARD), 1.5)
	_ok(climbed.position.y > on_ramp.position.y + 0.5, "walks up the ramp",
		"climbed %.2f m" % (climbed.position.y - on_ramp.position.y))


func _check_weapons() -> void:
	print("\n[weapon switching — 03]")
	var rifle: WeaponDef = _tuning.weapon_at(0)
	var pistol: WeaponDef = _tuning.weapon_at(1)
	_ok(rifle != null and rifle.display_name == "Rifle", "rifle in slot 1")
	_ok(pistol != null and pistol.fire_mode == WeaponDef.FireMode.SEMI_AUTO, "pistol is semi-auto")

	var s := _settle(Vector3(0, 3, -150))
	var to_pistol := _cmd(Vector2.ZERO, FORWARD, InputCommand.WEAPON_SECONDARY)
	var t := InfantrySim.simulate(s, to_pistol, _tuning, _space, TICK)
	_ok(t.weapon_index == 1 and t.switch_progress < 1.0, "pressing 2 starts the pistol draw",
		"progress %.2f" % t.switch_progress)

	var mid := _run(t, _cmd(Vector2.ZERO, FORWARD, InputCommand.FIRE), pistol.draw_time * 0.5)
	_ok(mid.shots_fired == 0, "firing during the draw does nothing", "shots=%d" % mid.shots_fired)

	var drawn := _run(t, _cmd(Vector2.ZERO, FORWARD), pistol.draw_time + 0.05)
	_ok(drawn.switch_progress >= 1.0, "pistol draw completes in %.2fs" % pistol.draw_time)

	var held := _run(drawn, _cmd(Vector2.ZERO, FORWARD, InputCommand.FIRE), 1.0)
	_ok(held.shots_fired == 1, "held trigger fires the semi-auto once", "shots=%d" % held.shots_fired)

	var back := InfantrySim.simulate(drawn, _cmd(Vector2.ZERO, FORWARD, InputCommand.WEAPON_PRIMARY), _tuning, _space, TICK)
	var ready := _run(back, _cmd(Vector2.ZERO, FORWARD), rifle.draw_time + 0.05)
	_ok(ready.weapon_index == 0 and ready.switch_progress >= 1.0, "back to rifle after its draw time")

	var auto := _run(ready, _cmd(Vector2.ZERO, FORWARD, InputCommand.FIRE), 1.0)
	var expected_shots := int(1.0 / rifle.seconds_per_shot())
	_ok(absi(auto.shots_fired - expected_shots) <= 1, "rifle full-auto rate",
		"%d shots in 1 s (expected ~%d at %.0f rpm)" % [auto.shots_fired, expected_shots, rifle.rpm])


func _check_spawn_recovery() -> void:
	print("\n[spawn robustness]")
	var spawn: SpawnPoint = _level.get_node("SpawnPoints/MainBase")
	var settled := _settle(spawn.global_position, 2.0)
	_ok(settled.on_floor, "Main Base spawn point lands on ground",
		"%v" % settled.position)
	_ok(absf(settled.position.y) < 0.2, "spawn does not sink", "y=%.3f" % settled.position.y)

	var buried := _settle(Vector3(1.0, 0.6, 63.0), 2.0)
	_ok(buried.on_floor and buried.position.y > -1.0,
		"a spawn buried inside a crate pushes out instead of falling through world",
		"%v" % buried.position)
