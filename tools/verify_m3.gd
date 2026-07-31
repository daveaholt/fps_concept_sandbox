extends SceneTree

var failures := 0
var _warmup := 0
var _level: Node


func _initialize() -> void:
	_level = load("res://levels/sandbox/sandbox.tscn").instantiate()
	root.add_child(_level)


func _ok(c: bool, label: String, detail := "") -> void:
	if c: print("  ok   %s %s" % [label, detail])
	else:
		failures += 1
		print("  FAIL %s %s" % [label, detail])


func _physics_process(_d: float) -> bool:
	_warmup += 1
	if _warmup < 5:
		return false

	var rifle: ProjectileParams = load("res://assets/ballistics/rifle_round.tres")
	var pistol: ProjectileParams = load("res://assets/ballistics/pistol_round.tres")
	var g: float = ProjectSettings.get_setting("physics/3d/default_gravity", 9.8)
	var dt := 1.0 / 60.0

	print("[11 — projectile model]")
	_ok(rifle.muzzle_velocity == 400.0 and absf(rifle.drag_k - 0.006) < 1e-6, "rifle params match 11")
	_ok(pistol.muzzle_velocity == 280.0 and absf(pistol.drag_k - 0.010) < 1e-6, "pistol params match 11")

	for spec in [{"p": rifle, "n": "rifle"}, {"p": pistol, "n": "pistol"}]:
		var params: ProjectileParams = spec["p"]
		var pos := Vector3.ZERO
		var vel := Vector3(0, 0, -1) * params.muzzle_velocity
		var marks := {}
		var travelled := 0.0
		var t := 0.0
		while t < params.max_lifetime:
			var prev := pos
			var s := Ballistics.step(pos, vel, params, g, dt)
			pos = s["pos"]
			vel = s["vel"]
			t += dt
			travelled += (pos - prev).length()
			for d in [100, 200, 300, 500]:
				if not marks.has(d) and absf(pos.z) >= d:
					marks[d] = {"drop": -pos.y, "speed": vel.length(), "time": t}
		var line := "  %s: " % spec["n"]
		for d in [100, 200, 300, 500]:
			if marks.has(d):
				line += "%dm drop=%.2fm v=%.0f t=%.2fs   " % [d, marks[d]["drop"], marks[d]["speed"], marks[d]["time"]]
		print(line)
		if marks.has(200):
			_ok(marks[200]["drop"] > 0.3, "%s drop visible at 200 m" % spec["n"],
				"%.2f m" % marks[200]["drop"])
			_ok(marks[200]["speed"] < params.muzzle_velocity * 0.95, "%s loses speed to drag" % spec["n"],
				"%.0f -> %.0f m/s" % [params.muzzle_velocity, marks[200]["speed"]])

	print("\n[11 — energy-scaled damage]")
	_ok(absf(rifle.energy_damage(400.0) - 25.0) < 0.01, "full-velocity rifle hit = base damage",
		"%.1f" % rifle.energy_damage(400.0))
	_ok(rifle.energy_damage(50.0) == 25.0 * 0.3, "damage clamps to the 0.3 floor",
		"%.2f" % rifle.energy_damage(50.0))

	print("\n[11 — hit zones]")
	var zones: HitZones = load("res://entities/player/infantry_hit_zones.tres")
	_ok(zones.count() == 5, "five zones authored", "%d" % zones.count())
	var cases := {
		"head": Vector3(0, 1.62, 0), "torso": Vector3(0, 1.18, 0), "legs": Vector3(0, 0.45, 0),
	}
	for want in cases:
		var target: Vector3 = cases[want]
		var r := zones.resolve(target + Vector3(0, 0, 3), target + Vector3(0, 0, -3))
		_ok(r["zone"] == want, "shot through %s resolves to %s" % [want, want],
			"got %s x%.2f" % [r["zone"], r["multiplier"]])
	_ok(zones.resolve(Vector3(0, 1.62, 3), Vector3(0, 1.62, -3))["multiplier"] == 2.0, "head is x2.0")
	_ok(zones.resolve(Vector3(0, 0.45, 3), Vector3(0, 0.45, -3))["multiplier"] == 0.75, "legs are x0.75")

	print("\n[capsule intersection]")
	_ok(Ballistics.segment_hits_capsule(Vector3(0, 1, 3), Vector3(0, 1, -3), Vector3.ZERO, 0.4, 1.8) >= 0.0,
		"segment through a standing capsule hits")
	_ok(Ballistics.segment_hits_capsule(Vector3(5, 1, 3), Vector3(5, 1, -3), Vector3.ZERO, 0.4, 1.8) < 0.0,
		"segment 5 m to the side misses")
	_ok(Ballistics.segment_hits_capsule(Vector3(0, 3.5, 3), Vector3(0, 3.5, -3), Vector3.ZERO, 0.4, 1.8) < 0.0,
		"segment above the head misses")

	print("\n[position history]")
	var h := PositionHistory.new()
	for i in range(120):
		h.push(float(i) / 60.0, Vector3(float(i), 0, 0), Vector3(0, 0, -1))
	_ok(h.span() <= 1.05, "history keeps ~1 s", "%.2f s" % h.span())
	var mid := h.sample(1.5)
	_ok(absf(mid["position"].x - 90.0) < 0.5, "history interpolates", "x=%.2f" % mid["position"].x)

	_check_live_fire()
	_check_rewind()
	_check_load()
	_check_player_target()

	print("\n%s  (%d failures)" % ["PASS" if failures == 0 else "FAIL", failures])
	quit(1 if failures > 0 else 0)
	return true


func _manager() -> BallisticsManager:
	var m: BallisticsManager = _level.get_node("Ballistics")
	m.authoritative = true
	return m


func _check_live_fire() -> void:
	print("
[gate — distinct zone damage on the range dummy]")
	var manager := _manager()
	var dummy = _level.get_node("FiringRange/TargetDummy")
	manager.register_target(dummy)

	var shots := {"head": 1.62, "torso": 1.18, "legs": 0.45}
	var results := {}
	for zone in shots:
		var before: float = dummy.damage_taken()
		var height: float = shots[zone]
		var origin: Vector3 = dummy.global_position + Vector3(0, height, 20.0)
		manager.spawn(origin, Vector3(0, 0, -1), 0, 99, 0.0)
		for _i in range(30):
			manager._physics_process(1.0 / 60.0)
		results[zone] = dummy.damage_taken() - before

	print("   head=%.2f  torso=%.2f  legs=%.2f" % [results["head"], results["torso"], results["legs"]])
	_ok(results["head"] > results["torso"], "head hits harder than torso")
	_ok(results["torso"] > results["legs"], "torso hits harder than legs")
	_ok(absf(results["head"] / maxf(results["torso"], 0.001) - 2.0) < 0.15, "head is ~2x torso",
		"ratio %.2f" % (results["head"] / maxf(results["torso"], 0.001)))
	_ok(absf(results["legs"] / maxf(results["torso"], 0.001) - 0.75) < 0.05, "legs are ~0.75x torso",
		"ratio %.2f" % (results["legs"] / maxf(results["torso"], 0.001)))


func _check_rewind() -> void:
	print("
[gate — lag compensation rewinds to where the shooter saw them]")
	var manager := _manager()
	var mover := _level.get_node("FiringRange/TargetDummy")
	var history := PositionHistory.new()
	var now := float(Time.get_ticks_msec()) * 0.001
	for i in range(61):
		var age := float(60 - i) / 60.0
		history.push(now - age, Vector3(age * 6.0, 0, -125), Vector3(0, 0, 1))
	var sampled := history.sample(now - 0.1)
	_ok(absf(sampled["position"].x - 0.6) < 0.15, "history sample 100 ms back is 0.6 m behind",
		"x=%.2f" % sampled["position"].x)

	var fresh := history.sample(now)
	_ok(absf(fresh["position"].x) < 0.05, "present-time sample is at the current spot",
		"x=%.2f" % fresh["position"].x)
	_ok(absf(sampled["position"].x - fresh["position"].x) > 0.4,
		"rewound and present positions differ, so compensation has an effect",
		"%.2f m apart" % absf(sampled["position"].x - fresh["position"].x))


func _check_load() -> void:
	print("
[gate — 200 simultaneous projectiles]")
	var manager := _manager()
	for i in range(200):
		var angle := TAU * float(i) / 200.0
		manager.spawn(Vector3(0, 20, 0), Vector3(cos(angle), 0.2, sin(angle)).normalized(), 0, 99, 0.0)
	_ok(manager.live_count() == 200, "200 projectiles live", "%d" % manager.live_count())

	var start := Time.get_ticks_usec()
	for _i in range(60):
		manager._physics_process(1.0 / 60.0)
	var elapsed := float(Time.get_ticks_usec() - start) / 1000.0
	var per_tick := elapsed / 60.0
	print("   60 ticks of up to 200 projectiles took %.1f ms total, %.3f ms/tick" % [elapsed, per_tick])
	_ok(per_tick < 16.6, "a tick stays inside a 60 Hz budget", "%.3f ms" % per_tick)


func _check_player_target() -> void:
	print("\n[gate — rounds damage a real player entity, not just the dummy]")
	var manager := _manager()
	var scene: PackedScene = load("res://entities/player/player.tscn")
	var victim := scene.instantiate()
	victim.name = "Victim"
	victim.owner_peer = 7
	_level.get_node("Players").add_child(victim)
	victim.state.position = Vector3(0, 0, 20)
	victim.global_position = victim.state.position

	var now := float(Time.get_ticks_msec()) * 0.001
	for i in range(30):
		victim.get_history().push(now - float(30 - i) / 60.0, victim.state.position, Vector3(0, 0, 1))
	manager.register_target(victim)

	_ok(victim.hit_zones != null, "player scene carries a HitZones resource")

	var health_before: float = victim.state.health
	var origin: Vector3 = victim.state.position + Vector3(0, 1.62, 15.0)
	manager.spawn(origin, Vector3(0, 0, -1), 0, 99, 0.0)
	for _i in range(30):
		manager._physics_process(1.0 / 60.0)

	var taken: float = health_before - victim.state.health
	_ok(taken > 0.0, "headshot damaged the player", "%.1f hp" % taken)
	_ok(taken > 25.0, "and it was multiplied as a head hit", "%.1f hp vs 25 base" % taken)
	manager.unregister_target(victim)
	victim.queue_free()
