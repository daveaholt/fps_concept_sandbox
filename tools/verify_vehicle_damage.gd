extends SceneTree

var _level: Node
var _t := 0
var _fail := 0
var _gs
var _tank
var _heli
var _confirms: Array = []


func _ok(label: String, cond: bool, detail: String = "") -> void:
	if not cond:
		_fail += 1
	print("%s %s%s" % ["PASS" if cond else "FAIL", label, "  " + detail if detail != "" else ""])


func _initialize() -> void:
	_level = load("res://levels/sandbox/sandbox.tscn").instantiate()
	root.add_child(_level)


func _physics_process(delta: float) -> bool:
	_t += 1
	if _t == 20:
		_setup()
		_check_states()
		_check_degradation()
		_check_hit_confirm()
		_check_destruction()
		_check_empty_hull()
		_check_blast()
		_check_visible_feedback()
		_check_shell_lethality()
		return false
	if _t > 20 and _t < 40:
		return false
	if _t == 40:
		_check_respawn_pending()
		print("vehicle damage: %d failing" % _fail)
		quit(1 if _fail > 0 else 0)
		return true
	return false


func _setup() -> void:
	_gs = root.get_node_or_null("/root/GameServer")
	_tank = _level.get_node("Vehicles/Tank")
	_heli = _level.get_node("Vehicles/Helicopter")
	_gs.is_active = true
	_gs.ballistics.authoritative = true
	_gs.roster.clear()
	_gs.handle_slot_request(11, 0)
	_gs.handle_slot_request(22, 8)
	_gs.phase = _gs.Phase.PLAYING
	_gs.ballistics.hit_confirmed.connect(func(peer, dmg, killed, label):
		_confirms.append({"peer": peer, "damage": dmg, "killed": killed,
			"label": label}))


func _check_states() -> void:
	_ok("a fresh tank is healthy",
		_tank.damage_state() == VehicleDamage.State.HEALTHY)

	_tank.apply_damage(_tank.max_health * 0.5)
	_ok("half health reads DAMAGED", _tank.damage_state() == VehicleDamage.State.DAMAGED,
		"%.0f%%" % (_tank.health_fraction() * 100.0))

	_tank.apply_damage(_tank.max_health * 0.3)
	_ok("a fifth of health reads CRITICAL",
		_tank.damage_state() == VehicleDamage.State.CRITICAL,
		"%.0f%%" % (_tank.health_fraction() * 100.0))

	_ok("hull health is replicated", _tank.get_net_state().has("hp"),
		"else a client cannot see damage at all")
	_ok("wreck flag is replicated", _tank.get_net_state().has("wk"))
	_ok("the shell tints with damage", _tank.common().tinted_material_count() > 0,
		"%d materials" % _tank.common().tinted_material_count())


func _check_degradation() -> void:
	_ok("a critical tank has degraded mobility", _tank.mobility() < 1.0,
		"x%.2f" % _tank.mobility())
	_ok("a critical tank traverses slower", _tank.traverse_rate() < 1.0,
		"x%.2f" % _tank.traverse_rate())
	_ok("a healthy heli has full mobility", is_equal_approx(_heli.mobility(), 1.0))


func _check_hit_confirm() -> void:
	_confirms.clear()
	var hits_before: int = _gs.ballistics.hits_logged
	var from: Vector3 = _heli.global_position + Vector3(0.0, 14.0, 0.0)
	_gs.ballistics.spawn(from, Vector3.DOWN, 3, 11, 0.0, 1)
	for _i in 40:
		_gs.ballistics._physics_process(1.0 / 60.0)
	_ok("the round actually landed", _gs.ballistics.hits_logged > hits_before,
		"heli hull %.0f" % _heli.health)
	_ok("a hit on a vehicle reports back to the shooter", not _confirms.is_empty(),
		"%d confirmations" % _confirms.size())
	if not _confirms.is_empty():
		_ok("the confirmation names the shooter", int(_confirms[0]["peer"]) == 11,
			"peer %d" % int(_confirms[0]["peer"]))
		_ok("a survivable hit is not flagged as a kill", not _confirms[0]["killed"],
			"a minigun round should not end a helicopter")


func _check_destruction() -> void:
	_confirms.clear()
	_tank.take_seat(11)
	_gs._bind(11, _tank)
	var tickets_before: int = int(_gs.tickets.get(1, 0))

	_tank.apply_damage(_tank.max_health)
	_ok("a tank at zero health is destroyed",
		_tank.damage_state() == VehicleDamage.State.DESTROYED)
	_ok("the wreck reports itself dead", not _tank.is_alive())
	_ok("the crew died with it", _tank.seats.is_empty())
	_ok("crew loss spent a ticket", int(_gs.tickets.get(1, 0)) < tickets_before,
		"%d -> %d" % [tickets_before, int(_gs.tickets.get(1, 0))])
	_ok("a wreck cannot be boarded", not _tank.has_free_seat())
	_ok("a wreck cannot move", is_zero_approx(_tank.mobility()))

	var before: float = _tank.health
	_tank.apply_damage(50.0)
	_ok("damage on a wreck is ignored", is_equal_approx(_tank.health, before))


func _check_respawn_pending() -> void:
	_ok("the wreck is queued to return", _gs._wrecks.size() > 0,
		"%d pending" % _gs._wrecks.size())
	if _gs._wrecks.is_empty():
		return
	var seconds: float = float(_gs._wrecks[0]["seconds"])
	_ok("the respawn timer is counting down", seconds < _gs.VEHICLE_RESPAWN_SECONDS,
		"%.2f s left of %.0f" % [seconds, _gs.VEHICLE_RESPAWN_SECONDS])

	_tank.revive()
	_ok("a revived tank is healthy again",
		_tank.damage_state() == VehicleDamage.State.HEALTHY and _tank.is_alive())
	_ok("a revived tank can be boarded", _tank.has_free_seat())
	_ok("a revived tank moves again", is_equal_approx(_tank.mobility(), 1.0))


func _check_empty_hull() -> void:
	_heli.revive()
	_ok("the helicopter starts empty", _heli.seats.is_empty())
	var before: int = int(_gs.tickets.get(1, 0)) + int(_gs.tickets.get(2, 0))
	_heli.apply_damage(_heli.max_health)
	_ok("an abandoned hull can still be destroyed", not _heli.is_alive())
	var after: int = int(_gs.tickets.get(1, 0)) + int(_gs.tickets.get(2, 0))
	_ok("destroying an empty vehicle costs nobody a ticket", after == before,
		"%d tickets before, %d after" % [before, after])


func _check_blast() -> void:
	for pair in [[_tank, "tank"], [_heli, "heli"]]:
		var vehicle = pair[0]
		var name: String = pair[1]
		var entry: float = vehicle.common().entry_radius()
		_ok("%s blast radius tracks its entry volume" % name,
			is_equal_approx(vehicle.blast_radius(), entry) and entry > 1.0,
			"%.1f m" % entry)

	_tank.revive()
	var victim: Node3D = load("res://entities/player/player.tscn").instantiate()
	_level.add_child(victim)
	var near := Vector3(_tank.blast_radius() * 0.4, 0.0, 0.0)
	victim.global_position = _tank.global_position + near
	victim.team = 2
	_gs.ballistics.register_target(victim)

	var far_off: Node3D = load("res://entities/player/player.tscn").instantiate()
	_level.add_child(far_off)
	far_off.global_position = _tank.global_position + Vector3(40.0, 0.0, 0.0)
	far_off.team = 2
	_gs.ballistics.register_target(far_off)

	var caught: int = _gs.ballistics.damage_in_radius(_tank.global_position,
		_tank.blast_radius(), _tank.blast_damage(), _tank, {"team": 1, "shooter": 11},
		"test")
	_ok("a wreck blast catches infantry standing beside it", caught > 0,
		"%d caught" % caught)
	_ok("infantry inside half the blast radius are killed", not victim.is_alive(),
		"health %.0f" % victim.state.health)
	_ok("infantry well clear are untouched", far_off.is_alive()
		and is_equal_approx(far_off.state.health, 100.0),
		"health %.0f" % far_off.state.health)

	var friendly: Node3D = load("res://entities/player/player.tscn").instantiate()
	_level.add_child(friendly)

	friendly.global_position = _tank.global_position + near
	friendly.team = 1
	_gs.ballistics.register_target(friendly)
	_gs.ballistics.damage_in_radius(_tank.global_position, _tank.blast_radius(),
		_tank.blast_damage(), _tank, {"team": 1, "shooter": 11}, "test")
	_ok("a wreck blast respects friendly fire", is_equal_approx(friendly.state.health,
		100.0), "health %.0f" % friendly.state.health)


func _check_visible_feedback() -> void:
	_tank.revive()
	_ok("a healthy vehicle is visible", _tank.visible)
	_ok("a healthy vehicle does not smoke", not _tank.common().smoking())

	_tank.apply_damage(_tank.max_health * 0.5)
	_ok("a damaged vehicle smokes", _tank.common().smoking(),
		"state %d" % _tank.damage_state())

	_tank.apply_damage(_tank.max_health * 0.3)
	_ok("a critical vehicle still smokes", _tank.common().smoking())

	_confirms.clear()
	var hits_before: int = _gs.ballistics.hits_logged
	var from: Vector3 = _tank.global_position + Vector3(0.0, 9.0, 0.0)
	_gs.ballistics.spawn(from, Vector3.DOWN, 2, 22, 0.0, 2)
	for _i in 40:
		_gs.ballistics._physics_process(1.0 / 60.0)
	_ok("the killing round landed", _gs.ballistics.hits_logged > hits_before)
	_ok("the wreck is still on show for the death cam", _tank.visible
		and _tank.wreck_shown, "it despawns after the hold — see verify_death_cam")
	_tank.hide_wreck()
	_ok("the wreck vanishes once the hold is over", not _tank.visible)
	_ok("a despawned wreck stops smoking", not _tank.common().smoking())
	_ok("a despawned wreck cannot be collided with", _tank.collision_layer == 0)

	var labels: Array = []
	for entry in _confirms:
		if String(entry["label"]) != "":
			labels.append(String(entry["label"]))
	_ok("the killer is told what they destroyed", labels.has("TANK DESTROYED"),
		"labels %s" % str(labels))

	_tank.revive()
	_ok("the tank comes back visible", _tank.visible)
	_ok("the tank comes back collidable", _tank.collision_layer != 0)
	_ok("the tank comes back clean", not _tank.common().smoking())
	_ok("the respawn wait is ten seconds",
		is_equal_approx(_gs.VEHICLE_RESPAWN_SECONDS, 10.0),
		"%.0f s" % _gs.VEHICLE_RESPAWN_SECONDS)


func _check_shell_lethality() -> void:
	_tank.revive()
	_heli.revive()
	var shell: ProjectileParams = _gs.ballistics.params_for(_tank.shell_params_id)
	var on_heli: float = shell.energy_damage(0.0) * _heli.explosive_vulnerability
	_ok("a shell one-shots a helicopter at any range", on_heli >= _heli.max_health,
		"%.0f effective vs %.0f hull — exact counts live in verify_duel_math"
		% [on_heli, _heli.max_health])
	_ok("a shell kills infantry outright", shell.energy_damage(0.0) >= 100.0,
		"%.0f" % shell.energy_damage(0.0))

	var before: int = _gs.ballistics.hits_logged
	var from: Vector3 = _heli.global_position + Vector3(0.0, 12.0, 0.0)
	_gs.ballistics.spawn(from, Vector3.DOWN, _tank.shell_params_id, 11, 0.0, 1)
	for _i in 60:
		_gs.ballistics._physics_process(1.0 / 60.0)
	_ok("the test shell connected", _gs.ballistics.hits_logged > before)
	_ok("one shell destroys a helicopter in play", not _heli.is_alive(),
		"hull %.0f" % _heli.health)
