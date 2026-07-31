extends SceneTree

var failures := 0


func _ok(c: bool, label: String, detail := "") -> void:
	if c: print("  ok   %s %s" % [label, detail])
	else:
		failures += 1
		print("  FAIL %s %s" % [label, detail])


func _initialize() -> void:
	print("[11 — tracer streak lies along its flight path, whatever the heading]")
	var headings := [
		Vector3(0, 0, -1), Vector3(0, 0, 1), Vector3(1, 0, 0), Vector3(-1, 0, 0),
		Vector3(0.7, 0.2, 0.7).normalized(), Vector3(-0.5, -0.3, 0.8).normalized(),
		Vector3(0, 1, 0), Vector3(0, -1, 0),
	]
	for dir in headings:
		var length := 6.0
		var head := Vector3(10, 20, 30)
		var xf := Ballistics.tracer_transform(head, dir, length)
		var axis: Vector3 = xf.basis.z
		var alignment: float = absf(axis.normalized().dot(dir))
		_ok(alignment > 0.99, "aligned with %v" % dir, "|dot|=%.4f len=%.2f" % [alignment, axis.length()])
		_ok(absf(axis.length() - length) < 0.01, "streak is %.0f m long for %v" % [length, dir],
			"%.2f m" % axis.length())

		var tail: Vector3 = xf * Vector3(0, 0, 0.5)
		var nose: Vector3 = xf * Vector3(0, 0, -0.5)
		var span := (nose - tail)
		_ok(absf(span.normalized().dot(dir)) > 0.99, "the drawn span runs along the heading %v" % dir,
			"span %.2f m" % span.length())

	print("
%s  (%d failures)" % ["PASS" if failures == 0 else "FAIL", failures])
	quit(1 if failures > 0 else 0)
