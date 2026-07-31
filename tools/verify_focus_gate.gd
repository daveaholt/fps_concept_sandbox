extends SceneTree

var failures := 0

class FakeSampler extends RefCounted:
	var focused := true
	func window_focused() -> bool:
		return focused

class NoMethod extends RefCounted:
	pass

func _ok(c: bool, label: String, detail := "") -> void:
	if c: print("  ok   %s %s" % [label, detail])
	else:
		failures += 1
		print("  FAIL %s %s" % [label, detail])

func _initialize() -> void:
	print("[02 - an unfocused window must not act on gamepad input]")
	print("   keyboard is focus-gated by the OS; joypads are polled process-wide and are not")

	var fake := FakeSampler.new()
	fake.focused = true
	_ok(InputFocus.may_act(fake), "a focused window may act on enter and exit")

	fake.focused = false
	_ok(not InputFocus.may_act(fake),
		"an unfocused one may not, so one gamepad press cannot act in two windows")

	_ok(InputFocus.may_act(null),
		"with no sampler it stays permissive rather than dead")
	_ok(InputFocus.may_act(NoMethod.new()),
		"and tolerates a sampler that cannot answer")

	print("\n%s  (%d failures)" % ["PASS" if failures == 0 else "FAIL", failures])
	quit(1 if failures > 0 else 0)
