extends SceneTree

var failures := 0
var _level: Node
var _tank: VehicleBody3D
var _t := 0
var _fired_count := 0

func _ok(c: bool, label: String, detail := "") -> void:
	if c: print("  ok   %s %s" % [label, detail])
	else:
		failures += 1
		print("  FAIL %s %s" % [label, detail])

func _initialize() -> void:
	_level = load("res://levels/sandbox/sandbox.tscn").instantiate()
	root.add_child(_level)
	_tank = _level.get_node("Vehicles/Tank")
	print("[05 - firing the cannon should produce a shell in flight]")

func _physics_process(_d: float) -> bool:
	_t += 1
	var gs = root.get_node_or_null("/root/GameServer")
	var bm = gs.ballistics if gs != null else null
	if _t == 10:
		_ok(bm != null, "ballistics manager reachable from GameServer")
		if bm == null:
			print("   GameServer autoload: %s" % str(gs))
		_ok(_tank.fired.get_connections().size() > 0, "tank 'fired' signal is connected",
			"%d connection(s)" % _tank.fired.get_connections().size())
		_tank.fired.connect(func(_o, _d2, _p): _fired_count += 1)
		_tank.owner_peer = 1
		return false
	if _t < 40:
		_tank.push_command(InputCommand.make(0, Vector2.ZERO, InputCommand.FIRE, Vector3(0, 0, -1)))
		return false
	if _t == 40:
		_ok(_fired_count > 0, "the tank emitted a shot", "%d shot(s)" % _fired_count)
		_ok(bm.live_count() > 0 if bm.has_method("live_count") else true,
			"a projectile exists after firing")
		return false
	if _t == 60:
		var shell: ProjectileParams = bm.params_for(_tank.shell_params_id)
		_ok(shell.display_name == "Tank shell", "shell id %d is the tank shell" % _tank.shell_params_id,
			shell.display_name)
		var base: float = BallisticsManager.TRACER_BASE_WIDTH
		var xf := Ballistics.tracer_transform(Vector3.ZERO, Vector3.FORWARD,
			shell.tracer_length, shell.tracer_width / base)
		_ok(absf(xf.basis.z.length() - shell.tracer_length) < 0.01,
			"the shell tracer is drawn at its authored length, not clipped by speed",
			"%.1f m drawn vs %.1f m authored" % [xf.basis.z.length(), shell.tracer_length])
		var drawn_width: float = xf.basis.x.length() * base
		_ok(absf(drawn_width - shell.tracer_width) < 0.001,
			"and at its authored width", "%.2f m" % drawn_width)
		_ok(drawn_width > base * 2.0, "the shell tracer is fatter than a bullet",
			"%.2f m vs the %.2f m bullet default" % [drawn_width, base])
		var rifle: ProjectileParams = bm.params_for(0)
		var rxf := Ballistics.tracer_transform(Vector3.ZERO, Vector3.FORWARD,
			rifle.tracer_length, rifle.tracer_width / base)
		_ok(absf(rxf.basis.x.length() * base - base) < 0.0001,
			"rifle tracers are unchanged by the shell fix",
			"%.3f m wide, %.1f m long" % [rxf.basis.x.length() * base, rxf.basis.z.length()])
		return false
	if _t == 100:
		var n := 0
		if bm != null and bm.has_method("live_count"):
			n = bm.live_count()
		print("   projectiles alive 1 s after the shot: %d" % n)
		print("\n%s  (%d failures)" % ["PASS" if failures == 0 else "FAIL", failures])
		quit(1 if failures > 0 else 0)
		return true
	return false
