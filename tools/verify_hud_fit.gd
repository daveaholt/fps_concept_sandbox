extends SceneTree

var failures := 0
var _level: Node
var _t := 0


func _ok(c: bool, label: String, detail := "") -> void:
	if c:
		print("  ok   %s %s" % [label, detail])
	else:
		failures += 1
		print("  FAIL %s %s" % [label, detail])


func _initialize() -> void:
	_level = load("res://levels/sandbox/sandbox.tscn").instantiate()
	root.add_child(_level)
	print("[HUD - both corners must stay on screen as readouts are added]")
	print("   measured against a 1280x720 window, not the tiny headless default")


func _physics_process(_d: float) -> bool:
	_t += 1
	if _t == 1:
		root.size = Vector2i(1280, 720)
		return false
	if _t < 20:
		return false

	var hud = _level.get_node_or_null("UI/HUD")
	var screen := root.get_visible_rect()

	for corner in ["Situation", "Self"]:
		var panel: Control = hud.get_node_or_null(corner)
		_ok(panel != null, "%s corner exists" % corner)
		if panel == null:
			continue

		_ok(panel.grow_vertical == Control.GROW_DIRECTION_BEGIN,
			"%s grows upward, so new readouts push inward not off the edge" % corner)

		var needed := panel.get_combined_minimum_size()
		var rect := panel.get_global_rect()
		print("   %s needs %.0f x %.0f px and sits at %s"
			% [corner, needed.x, needed.y, rect])
		_ok(rect.end.y <= screen.size.y + 1.0, "  %s bottom edge on screen" % corner,
			"%.0f <= %.0f" % [rect.end.y, screen.size.y])
		_ok(rect.position.y >= 0.0, "  %s top edge on screen" % corner,
			"%.0f" % rect.position.y)
		_ok(rect.position.x >= 0.0, "  %s left edge on screen" % corner,
			"%.0f" % rect.position.x)
		_ok(rect.end.x <= screen.size.x + 1.0, "  %s right edge on screen" % corner,
			"%.0f <= %.0f" % [rect.end.x, screen.size.x])
		_ok(rect.size.y + 1.0 >= needed.y,
			"  %s is at least as tall as its contents need" % corner,
			"%.0f for %.0f" % [rect.size.y, needed.y])

	var left: Control = hud.get_node_or_null("Situation")
	var right: Control = hud.get_node_or_null("Self")
	if left != null and right != null:
		_ok(not left.get_global_rect().intersects(right.get_global_rect()),
			"the two corners do not overlap",
			"which is the whole reason they are separate")

	print("\n%s  (%d failures)" % ["PASS" if failures == 0 else "FAIL", failures])
	quit(1 if failures > 0 else 0)
	return true
