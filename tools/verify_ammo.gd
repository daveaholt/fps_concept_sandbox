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
	var body := _level.get_node("Players").get_child(0) if \
		_level.get_node("Players").get_child_count() > 0 else null
	if body == null:
		body = load("res://entities/player/player.tscn").instantiate()
		_level.get_node("Players").add_child(body)
	_tuning = body.tuning
	_space = (body as Node3D).get_world_3d().direct_space_state

	_check_loadout()
	_check_firing_costs_ammo()
	_check_empty_blocks_fire()
	_check_reload()
	_check_reserve_runs_out()
	_check_switch_cancels_reload()
	_check_replay_safe()
	_check_survives_the_wire()

	print("ammo: %d failing" % _fail)
	quit(1 if _fail > 0 else 0)
	return true


func _fresh() -> InfantryState:
	var s := InfantryState.new()
	s.arm(_tuning)
	return s


func _step(s: InfantryState, buttons: int, steps: int, delta := 1.0 / 60.0) -> InfantryState:
	var state := s
	for i in steps:
		var cmd := InputCommand.make(i + 1, Vector2.ZERO, buttons, Vector3.FORWARD)
		state = InfantrySim.simulate(state, cmd, _tuning, _space, delta)
	return state


func _check_loadout() -> void:
	var s := _fresh()
	var weapon := _tuning.weapon_at(0)
	_ok("a fresh soldier starts with a full magazine",
		s.loaded(0) == weapon.magazine_size, "%d rounds" % s.loaded(0))
	_ok("and a reserve behind it", s.spare(0) == weapon.starting_reserve,
		"%d spare" % s.spare(0))
	_ok("every weapon is armed, not just the first", s.magazine.size()
		== _tuning.weapons.size(), "%d weapons" % s.magazine.size())


func _check_firing_costs_ammo() -> void:
	var s := _fresh()
	var before := s.loaded(0)
	s = _step(s, InputCommand.FIRE, 60)
	_ok("firing spends rounds", s.loaded(0) < before,
		"%d -> %d after a second of fire" % [before, s.loaded(0)])
	_ok("it spends exactly one round per shot",
		before - s.loaded(0) == s.shots_fired,
		"%d rounds for %d shots" % [before - s.loaded(0), s.shots_fired])
	_ok("the reserve is untouched until a reload", s.spare(0) == _tuning.weapon_at(0).starting_reserve)


func _check_empty_blocks_fire() -> void:
	var s := _fresh()
	s.magazine[0] = 1
	s.reserve[0] = 0
	s = _step(s, InputCommand.FIRE, 90)
	_ok("an empty magazine with no reserve stops the gun", s.shots_fired == 1,
		"%d shots from one round" % s.shots_fired)
	_ok("and does not start a reload it cannot finish", not s.reloading())


func _check_reload() -> void:
	var weapon := _tuning.weapon_at(0)
	var s := _fresh()
	s.magazine[0] = 10
	s = _step(s, InputCommand.RELOAD, 1)
	_ok("pressing reload starts one", s.reloading(), "%.2f s left" % s.reload_timer)
	_ok("you cannot fire mid-reload", _step(s.clone(), InputCommand.FIRE, 2).shots_fired == 0)

	var ticks := int(ceil(weapon.reload_time * 60.0)) + 2
	s = _step(s, 0, ticks)
	_ok("the reload completes", not s.reloading())
	_ok("the magazine is topped up", s.loaded(0) == weapon.magazine_size,
		"%d rounds" % s.loaded(0))
	_ok("the rounds came out of the reserve",
		s.spare(0) == weapon.starting_reserve - 20,
		"%d spare, expected %d" % [s.spare(0), weapon.starting_reserve - 20])

	var full := _fresh()
	full = _step(full, InputCommand.RELOAD, 1)
	_ok("reloading a full magazine does nothing", not full.reloading())

	var dry := _fresh()
	dry.magazine[0] = 0
	dry = _step(dry, InputCommand.FIRE, 30)
	_ok("firing on empty does not reload for you", not dry.reloading(),
		"the player asks for a reload, the gun never decides")
	_ok("and firing on empty stays empty", dry.loaded(0) == 0 and dry.shots_fired == 0)
	dry = _step(dry, InputCommand.RELOAD, 1)
	_ok("an explicit reload still works from empty", dry.reloading())

	var pistol_time: float = _tuning.weapon_at(1).reload_time
	var rifle_time: float = _tuning.weapon_at(0).reload_time
	_ok("every weapon defines its own reload duration",
		pistol_time > 0.0 and rifle_time > 0.0)
	_ok("the pistol reloads faster than the rifle", pistol_time < rifle_time,
		"pistol %.1f s vs rifle %.1f s" % [pistol_time, rifle_time])


func _check_reserve_runs_out() -> void:
	var weapon := _tuning.weapon_at(0)
	var s := _fresh()
	s.magazine[0] = 0
	s.reserve[0] = 7
	s = _step(s, InputCommand.RELOAD, int(ceil(weapon.reload_time * 60.0)) + 2)
	_ok("a partial reload takes what is left", s.loaded(0) == 7 and s.spare(0) == 0,
		"%d loaded, %d spare" % [s.loaded(0), s.spare(0)])


func _check_switch_cancels_reload() -> void:
	var s := _fresh()
	s.magazine[0] = 5
	s = _step(s, InputCommand.RELOAD, 1)
	_ok("mid-reload before the switch", s.reloading())
	s = _step(s, InputCommand.WEAPON_SECONDARY, 1)
	_ok("switching weapons cancels the reload", not s.reloading(),
		"otherwise the timer finishes into the wrong gun")
	_ok("and the first weapon keeps its partial magazine", s.loaded(0) == 5)


func _check_replay_safe() -> void:
	var start := _fresh()
	start.magazine[0] = 4
	var commands: Array = []
	for i in 200:
		var buttons := InputCommand.FIRE if i % 3 != 0 else 0
		if i == 40 or i == 120:
			buttons |= InputCommand.RELOAD
		commands.append(InputCommand.make(i + 1, Vector2.ZERO, buttons, Vector3.FORWARD))

	var first := start.clone()
	for cmd in commands:
		first = InfantrySim.simulate(first, cmd, _tuning, _space, 1.0 / 60.0)

	var second := start.clone()
	for cmd in commands:
		second = InfantrySim.simulate(second, cmd, _tuning, _space, 1.0 / 60.0)

	_ok("replaying the same commands gives the same ammo",
		first.magazine == second.magazine and first.reserve == second.reserve
		and is_equal_approx(first.reload_timer, second.reload_timer),
		"%s / %s vs %s / %s" % [first.magazine, first.reserve,
			second.magazine, second.reserve])
	_ok("reconciliation can tell two ammo states apart",
		not first.equals_within(_fresh(), 0.01),
		"else a mispredicted reload would never be corrected")


func _check_survives_the_wire() -> void:
	var s := _fresh()
	s.magazine[0] = 13
	s.reserve[0] = 41
	s.reload_timer = 0.7
	var round_trip := InfantryState.from_dict(s.to_dict())
	_ok("ammo survives serialisation", round_trip.loaded(0) == 13
		and round_trip.spare(0) == 41
		and is_equal_approx(round_trip.reload_timer, 0.7),
		"%d / %d, %.2f" % [round_trip.loaded(0), round_trip.spare(0),
			round_trip.reload_timer])

	var copy := s.clone()
	copy.magazine[0] = 99
	_ok("clone does not share the magazine array", s.loaded(0) == 13,
		"a shallow copy would corrupt the prediction buffer")
