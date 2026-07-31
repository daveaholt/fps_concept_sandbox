extends SceneTree

const PAD := Vector3(45, 0.65, -40)
const HOVER := 60.0
const SETTLE := 120
const MEASURE := 900

var _level: Node
var _h: RigidBody3D
var _t := 0
var _case := 0
var _ticks := 0
var _view: Array[Dictionary] = []
var _err_sq := 0.0
var _samples := 0
var _worst := 0.0
var _lost := false
var _results: Array[Dictionary] = []
var _cases: Array[Dictionary] = []

func _initialize() -> void:
	_level = load("res://levels/sandbox/sandbox.tscn").instantiate()
	root.add_child(_level)
	_h = _level.get_node("Vehicles/Helicopter")
	for assist in [0.35, 0.0]:
		for delay in [0, 3, 6, 9, 12]:
			_cases.append({"assist": assist, "delay": delay})
	print("[06/10 - is 100 ms interpolated helicopter control flyable?]")
	print("  A fixed automated pilot holds a hover against repeated gusts, seeing only the")
	print("  state a client would see: delayed by the interpolation buffer plus the command's")
	print("  trip to the server. Same gains at every delay, so any degradation is the delay.")
	print("  This measures whether the control loop stays STABLE. Whether it feels good is a")
	print("  question only a pilot can answer.")

func _goal() -> Vector3:
	return PAD + Vector3.UP * HOVER

func _setup(assist: float) -> void:
	_h.auto_level = assist
	_h.freeze = true
	_h.global_transform = Transform3D(Basis(), _goal() + Vector3(5.0, -3.0, 4.0))
	_h.linear_velocity = Vector3.ZERO
	_h.angular_velocity = Vector3.ZERO
	_h.freeze = false
	_h.owner_peer = 1
	_h.engine_on = true
	_h.rotor_rpm_norm = 1.0
	_h.collective = _h.mass * 9.8 / _h.max_lift
	_view.clear()
	_err_sq = 0.0
	_samples = 0
	_worst = 0.0
	_lost = false

func _gust(tick: int) -> void:
	var phase := float(tick) * 0.035
	var swirl := Vector3(sin(phase) + 0.4 * sin(phase * 2.7),
		0.35 * sin(phase * 1.9), cos(phase * 0.8) + 0.4 * cos(phase * 2.3))
	_h.apply_central_force(swirl * 1400.0)

func _observed(delay: int) -> Dictionary:
	_view.append({"pos": _h.global_position, "vel": _h.linear_velocity})
	while _view.size() > 64:
		_view.pop_front()
	return _view[maxi(_view.size() - 1 - delay, 0)]

func _pilot(view: Dictionary) -> void:
	var pos: Vector3 = view["pos"]
	var vel: Vector3 = view["vel"]
	var goal := _goal()
	var lift := clampf(0.12 * (goal.y - pos.y) + 0.30 * -vel.y, -1.0, 1.0)
	var pitch := clampf(0.12 * (pos.z - goal.z) + 0.30 * vel.z, -1.0, 1.0)
	var roll := clampf(-(0.12 * (pos.x - goal.x) + 0.30 * vel.x), -1.0, 1.0)
	_h.push_command(InputCommand.make(0, Vector2(roll, pitch), 0,
		Vector3(0, 0, -1), Vector2(0.0, lift)))

func _physics_process(_d: float) -> bool:
	_t += 1
	if _t < 5:
		return false
	if _case >= _cases.size():
		_report()
		quit(0)
		return true

	var this_case: Dictionary = _cases[_case]
	_ticks += 1
	if _ticks == 1:
		_setup(float(this_case["assist"]))
		return false

	_gust(_ticks)
	_pilot(_observed(int(this_case["delay"])))

	if _ticks > SETTLE:
		var offset := _h.global_position - _goal()
		var err := offset.length()
		_err_sq += err * err
		_worst = maxf(_worst, err)
		_samples += 1
		if err > 60.0 or _h.global_position.y < 8.0:
			_lost = true

	if _lost or _ticks > SETTLE + MEASURE:
		_results.append({
			"assist": this_case["assist"], "delay": this_case["delay"],
			"rms": sqrt(_err_sq / maxf(float(_samples), 1.0)),
			"worst": _worst, "lost": _lost,
		})
		_case += 1
		_ticks = 0
	return false

func _report() -> void:
	for assist in [0.35, 0.0]:
		print("")
		print("auto_level %.2f%s" % [assist,
			"  (shipped default)" if assist > 0.0 else "  (assists off, 06's manual case)"])
		print("   loop delay     RMS hover error   worst excursion   outcome")
		var base := 0.0
		for r in _results:
			if not is_equal_approx(float(r["assist"]), assist):
				continue
			if int(r["delay"]) == 0:
				base = float(r["rms"])
			var ms := int(r["delay"]) * 1000 / 60
			var rel := "" if base <= 0.0 else "  (%.1fx of zero-delay)" % (float(r["rms"]) / base)
			print("   %3d ms (%2d t)  %10.1f m %14.1f m    %s%s"
				% [ms, int(r["delay"]), float(r["rms"]), float(r["worst"]),
				"LOST IT" if bool(r["lost"]) else "held", rel])
