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
	if _t < 20:
		return false
	_gs = root.get_node_or_null("/root/GameServer")
	_gs.is_active = true
	_tank = _level.get_node("Vehicles/Tank")
	_heli = _level.get_node("Vehicles/Helicopter")

	var shell: ProjectileParams = _gs.ballistics.params_for(_tank.shell_params_id)
	var rocket: ProjectileParams = _gs.ballistics.params_for(_heli.rocket_params_id)

	_ok("the shell is flagged explosive", shell.explosive)
	_ok("the rocket is flagged explosive", rocket.explosive)

	_check_small_arms_cannot_kill_armour()
	_hits("shell into tank front", shell, _tank, _tank.armour_front, _tank.max_health, 3)
	_hits("shell into tank side", shell, _tank, _tank.armour_side, _tank.max_health, 3)
	_hits("shell into tank rear", shell, _tank, _tank.armour_rear, _tank.max_health, 2)
	_hits("shell into tank top", shell, _tank, _tank.armour_top, _tank.max_health, 2)
	_ok("the rear is the only ground facing that dies in two",
		_tank.armour_side <= _tank.armour_front and _tank.armour_rear > _tank.armour_side,
		"front x%.2f, side x%.2f, rear x%.2f"
		% [_tank.armour_front, _tank.armour_side, _tank.armour_rear])
	_hits("rockets into a helicopter", rocket, _heli, _heli.explosive_vulnerability,
		_heli.max_health, 4)

	var shell_on_heli: float = shell.energy_damage(0.0) * _heli.explosive_vulnerability
	_ok("a shell still one-shots a helicopter", shell_on_heli >= _heli.max_health,
		"%.0f vs %.0f" % [shell_on_heli, _heli.max_health])

	var rocket_on_tank := int(ceil(_tank.max_health
		/ (rocket.energy_damage(rocket.muzzle_velocity) * _tank.armour_front)))
	_ok("rockets into a tank front are unchanged at 8", rocket_on_tank == 8,
		"%d rockets" % rocket_on_tank)

	var rifle: ProjectileParams = _gs.ballistics.params_for(0)
	var mg: ProjectileParams = _gs.ballistics.params_for(_heli.gun_params_id)
	var sector: Dictionary = _heli.resolve_sector(Vector3.ZERO, rifle)
	_ok("small arms do not get the explosive bonus on a helicopter",
		is_equal_approx(float(sector["multiplier"]), 1.0),
		"rifle multiplier x%.2f" % float(sector["multiplier"]))
	var mg_sector: Dictionary = _heli.resolve_sector(Vector3.ZERO, mg)
	_ok("the minigun does not get it either",
		is_equal_approx(float(mg_sector["multiplier"]), 1.0))
	var shell_sector: Dictionary = _heli.resolve_sector(Vector3.ZERO, shell)
	_ok("the shell does get it", float(shell_sector["multiplier"]) > 1.0,
		"x%.2f" % float(shell_sector["multiplier"]))

	print("duel math: %d failing" % _fail)
	quit(1 if _fail > 0 else 0)
	return true


func _hits(label: String, params: ProjectileParams, _target, multiplier: float,
		hull: float, want: int) -> void:
	var strongest: float = params.energy_damage(params.muzzle_velocity) * multiplier
	var weakest: float = params.energy_damage(0.0) * multiplier
	var survives_best := (want - 1) * strongest < hull
	var dies_worst := want * weakest >= hull
	_ok("%s takes %d" % [label, want], survives_best and dies_worst,
		"%d x %.0f = %.0f survives, %d x %.0f = %.0f kills (hull %.0f)"
		% [want - 1, strongest, (want - 1) * strongest, want, weakest,
			want * weakest, hull])


func _check_small_arms_cannot_kill_armour() -> void:
	var rifle: ProjectileParams = _gs.ballistics.params_for(0)
	var mg: ProjectileParams = _gs.ballistics.params_for(_tank.gun_params_id)
	var shell: ProjectileParams = _gs.ballistics.params_for(_tank.shell_params_id)

	var rear_point: Vector3 = _tank.global_position 		+ _tank.global_transform.basis.z * 3.0 + Vector3.UP * 0.5
	var rear_rifle: float = float(_tank.resolve_sector(rear_point, rifle)["multiplier"])
	var rear_shell: float = float(_tank.resolve_sector(rear_point, shell)["multiplier"])

	_ok("a shell still gets the full rear multiplier",
		is_equal_approx(rear_shell, _tank.armour_rear),
		"x%.2f" % rear_shell)
	_ok("a rifle round barely penetrates armour", rear_rifle < _tank.armour_rear * 0.2,
		"x%.3f against the rear, the softest facing" % rear_rifle)

	var per_round: float = rifle.energy_damage(rifle.muzzle_velocity) * rear_rifle
	var magazine: float = per_round * 30.0
	_ok("a full magazine into the rear does not destroy a tank",
		magazine < _tank.max_health,
		"%.0f of %.0f hull — it was 1500 before" % [magazine, _tank.max_health])
	_ok("but small arms are not literally useless", per_round > 0.0,
		"%.1f per round" % per_round)

	var mg_second: float = mg.energy_damage(mg.muzzle_velocity) * rear_rifle 		* _tank.gun_rate_per_second
	_ok("a second of minigun fire is a scratch, not a kill",
		mg_second < _tank.max_health * 0.15,
		"%.0f damage per second into the rear" % mg_second)

	var heli_rifle: float = float(_heli.resolve_sector(Vector3.ZERO,
		rifle)["multiplier"])
	_ok("a helicopter is still soft to small arms",
		is_equal_approx(heli_rifle, 1.0),
		"an airframe is not armour — %d rifle rounds still down one"
		% int(ceil(_heli.max_health / rifle.energy_damage(rifle.muzzle_velocity))))
