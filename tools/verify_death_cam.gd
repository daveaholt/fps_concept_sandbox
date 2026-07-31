extends SceneTree

var _level: Node
var _t := 0
var _fail := 0
var _gs
var _gc
var _tank
var _body: Node3D
var _death_point := Vector3.ZERO
var _phase := 0


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
		_kill_the_player()
		return false
	if _phase == 1 and _t < 40:
		return false
	if _phase == 1:
		_check_during_hold()
		_phase = 2
		return false
	if _phase == 2 and _t < 260:
		return false
	if _phase == 2:
		_check_after_hold()
		print("death cam: %d failing" % _fail)
		quit(1 if _fail > 0 else 0)
		return true
	return false


func _setup() -> void:
	_gs = root.get_node_or_null("/root/GameServer")
	_gc = root.get_node_or_null("/root/GameClient")
	_gs.is_active = true
	_gs.ballistics.authoritative = true
	_gs.roster.clear()
	_gs.handle_slot_request(1, 0)
	_gs.phase = _gs.Phase.PLAYING
	_gc.phase = _gs.Phase.PLAYING
	_tank = _level.get_node("Vehicles/Tank")

	var cam := DeathCam.new()
	cam.name = "DeathCam"
	_gc.add_child(cam)
	_gc.death_cam = cam

	_ok("the hold reuses the delay that was already specced",
		_gs.DEATH_CAM_SECONDS > 1.0 and _gs.DEATH_CAM_SECONDS < 5.0,
		"%.1f s" % _gs.DEATH_CAM_SECONDS)


func _kill_the_player() -> void:
	_body = load("res://entities/player/player.tscn").instantiate()
	_level.get_node("Players").add_child(_body)
	_body.owner_peer = 1
	_body.global_position = Vector3(10.0, 1.0, 10.0)
	_death_point = _body.global_position
	_gs._bind(1, _body)
	_gs.ballistics.register_target(_body)

	_gs._kill_occupant(1)
	_phase = 1


func _check_during_hold() -> void:
	_ok("the body is still in the world during the hold",
		is_instance_valid(_body) and not _body.is_queued_for_deletion(),
		"there has to be something to look at")
	_ok("a camera is placed at the death site",
		_gc.death_cam != null and _gc.death_cam.is_active())
	if _gc.death_cam != null and _gc.death_cam.is_active():
		_ok("it looks at where the player died",
			_gc.death_cam.focus_point().distance_to(_death_point) < 0.5,
			"%.2f m off" % _gc.death_cam.focus_point().distance_to(_death_point))
	_ok("the deploy screen has not opened yet", not _gc.deploy_map_open,
		"this is the abrupt cut the hold exists to remove")

	var banner: Control = _level.find_child("DeathBanner", true, false)
	_ok("a death banner exists in the level UI", banner != null)
	if banner != null:
		banner._process(0.0)
		_ok("the banner is up during the hold", banner.visible,
			"otherwise the orbit has no explanation on screen")
		var headline: Label = banner.get_node_or_null("Headline")
		_ok("it says what happened", headline != null
			and headline.text == "KILLED IN ACTION",
			headline.text if headline != null else "no label")
	_ok("the body is no longer a ballistics target",
		not _gs.ballistics._targets.has(_body), "a corpse cannot be shot again")


func _check_after_hold() -> void:
	_ok("the deploy screen opens once the hold ends", _gc.deploy_map_open,
		"after %.1f s" % _gs.DEATH_CAM_SECONDS)
	_ok("the death camera released", _gc.death_cam == null
		or not _gc.death_cam.is_active())
	var banner: Control = _level.find_child("DeathBanner", true, false)
	if banner != null:
		banner._process(0.0)
		_ok("the banner clears when the deploy screen takes over", not banner.visible,
			"the deploy screen carries its own KIA header")
	_ok("the body is cleaned up", not is_instance_valid(_body)
		or _body.is_queued_for_deletion(), "corpses must not accumulate")

	_tank.enter_wreck()
	_ok("a fresh wreck is still visible", _tank.visible,
		"the hull has to survive long enough to be seen")
	_ok("a wreck reports itself as shown", _tank.wreck_shown)
	_ok("wreck visibility is replicated", _tank.get_net_state().has("ws"),
		"else only the host sees the wreckage")
	_tank.hide_wreck()
	_ok("the wreck disappears once the hold is over", not _tank.visible)
	_tank.revive()
