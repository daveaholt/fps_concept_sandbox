extends SceneTree

const SAMPLER_PATH := "res://systems/net/input_sampler.gd"

var failures := 0


func _initialize() -> void:
	var sampler = load(SAMPLER_PATH).new()

	print("[default]")
	_ok(sampler.invert_look_y, "vertical look is inverted by default")

	print("\n[inverted — pushing down raises the aim]")
	sampler.invert_look_y = true
	sampler.pitch = 0.0
	sampler._add_look(0.0, -0.3)
	_ok(sampler.pitch > 0.0, "input that used to look down now looks up", "pitch=%.3f" % sampler.pitch)
	_ok(sampler.aim_vector().y > 0.0, "aim vector points up", "aim.y=%.3f" % sampler.aim_vector().y)

	sampler.pitch = 0.0
	sampler._add_look(0.0, 0.3)
	_ok(sampler.pitch < 0.0, "and the opposite input looks down", "pitch=%.3f" % sampler.pitch)

	print("\n[not inverted — original behaviour preserved]")
	sampler.invert_look_y = false
	sampler.pitch = 0.0
	sampler._add_look(0.0, -0.3)
	_ok(sampler.pitch < 0.0, "pushing down lowers pitch", "pitch=%.3f" % sampler.pitch)
	_ok(sampler.aim_vector().y < 0.0, "aim vector points down", "aim.y=%.3f" % sampler.aim_vector().y)

	print("\n[yaw is unaffected either way]")
	for inverted in [true, false]:
		sampler.invert_look_y = inverted
		sampler.yaw = 0.0
		sampler._add_look(-0.4, 0.0)
		_ok(sampler.yaw < 0.0, "yaw sign with invert_look_y=%s" % inverted, "yaw=%.3f" % sampler.yaw)

	print("\n[pitch clamp still holds when inverted]")
	sampler.invert_look_y = true
	sampler.pitch = 0.0
	for _i in range(200):
		sampler._add_look(0.0, -0.5)
	_ok(sampler.pitch <= deg_to_rad(89.0) + 0.001, "clamped at +89 deg",
		"%.1f deg" % rad_to_deg(sampler.pitch))
	for _i in range(400):
		sampler._add_look(0.0, 0.5)
	_ok(sampler.pitch >= -deg_to_rad(89.0) - 0.001, "clamped at -89 deg",
		"%.1f deg" % rad_to_deg(sampler.pitch))

	sampler.free()
	print("\n%s  (%d failures)" % ["PASS" if failures == 0 else "FAIL", failures])
	quit(1 if failures > 0 else 0)


func _ok(condition: bool, label: String, detail := "") -> void:
	if condition:
		print("  ok   %s %s" % [label, detail])
	else:
		failures += 1
		print("  FAIL %s %s" % [label, detail])
