extends SceneTree

var failures := 0

func _ok(c: bool, label: String, detail := "") -> void:
	if c: print("  ok   %s %s" % [label, detail])
	else:
		failures += 1
		print("  FAIL %s %s" % [label, detail])


var _warm := 0
var _level: Node

func _initialize() -> void:
	_level = load("res://levels/sandbox/sandbox.tscn").instantiate()
	root.add_child(_level)


func _physics_process(_d: float) -> bool:
	_warm += 1
	if _warm < 5:
		return false
	var level: Node = _level
	var players: Node = level.get_node("Players")
	var scene: PackedScene = load("res://entities/player/player.tscn")

	var mine := scene.instantiate()
	mine.name = "Mine"
	players.add_child(mine)
	var theirs := scene.instantiate()
	theirs.name = "Theirs"
	players.add_child(theirs)

	print("[own-body culling — 09]")
	var cam: Camera3D = mine.get_node("Head/Camera3D")
	var own_bit := 1 << (2 - 1)
	_ok((cam.cull_mask & own_bit) == 0, "my camera culls the own-body layer",
		"cull_mask=%d" % cam.cull_mask)

	var mine_meshes = mine.get_node("Visual").find_children("*", "VisualInstance3D", true, false)
	var theirs_meshes = theirs.get_node("Visual").find_children("*", "VisualInstance3D", true, false)
	_ok(mine_meshes.size() >= 3, "player has visual meshes", "%d" % mine_meshes.size())

	for m in mine_meshes:
		_ok(m.layers == 1, "before possession %s is on the visible layer" % m.name, "layers=%d" % m.layers)

	mine.possess()
	var hidden := 0
	for m in mine_meshes:
		if (m.layers & own_bit) != 0:
			hidden += 1
	_ok(hidden == mine_meshes.size(), "after possession all my meshes moved to the culled layer",
		"%d/%d" % [hidden, mine_meshes.size()])

	var still_visible := 0
	for m in theirs_meshes:
		if (m.layers & cam.cull_mask) != 0:
			still_visible += 1
	_ok(still_visible == theirs_meshes.size(),
		"the other player's meshes are still rendered by my camera",
		"%d/%d" % [still_visible, theirs_meshes.size()])

	mine.unpossess()
	var restored := 0
	for m in mine_meshes:
		if m.layers == 1:
			restored += 1
	_ok(restored == mine_meshes.size(), "unpossessing restores my body to visible",
		"%d/%d" % [restored, mine_meshes.size()])

	print("\n%s  (%d failures)" % ["PASS" if failures == 0 else "FAIL", failures])
	quit(1 if failures > 0 else 0)
	return true
