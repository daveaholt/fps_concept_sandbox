class_name Ballistics
extends RefCounted


static func step(pos: Vector3, vel: Vector3, params: ProjectileParams, gravity: float,
		delta: float) -> Dictionary:
	var drag := -params.drag_k * vel * vel.length()
	var accel := Vector3.DOWN * gravity * params.gravity_scale + drag
	var next_vel := vel + accel * delta
	return {"pos": pos + next_vel * delta, "vel": next_vel}


static func tracer_transform(head: Vector3, direction: Vector3, length: float) -> Transform3D:
	var dir := direction.normalized() if direction.length_squared() > 0.000001 else Vector3.FORWARD
	if absf(dir.dot(Vector3.UP)) > 0.999:
		dir = (dir + Vector3(0.001, 0.0, 0.0)).normalized()
	var aligned := Basis.looking_at(dir, Vector3.UP)
	var basis := Basis(aligned.x, aligned.y, aligned.z * maxf(length, 0.01))
	return Transform3D(basis, head - dir * length * 0.5)


static func segment_hits_sphere(from: Vector3, to: Vector3, centre: Vector3, radius: float) -> float:
	var d := to - from
	var m := from - centre
	var a := d.dot(d)
	if a < 0.000001:
		return -1.0
	var b := 2.0 * m.dot(d)
	var c := m.dot(m) - radius * radius
	var disc := b * b - 4.0 * a * c
	if disc < 0.0:
		return -1.0
	var root := sqrt(disc)
	var t0 := (-b - root) / (2.0 * a)
	var t1 := (-b + root) / (2.0 * a)
	if t0 >= 0.0 and t0 <= 1.0:
		return t0
	if t1 >= 0.0 and t1 <= 1.0:
		return t1
	if t0 < 0.0 and t1 > 1.0:
		return 0.0
	return -1.0


static func segment_hits_box(from: Vector3, to: Vector3, centre: Vector3, half: Vector3) -> float:
	var d := to - from
	var t_min := 0.0
	var t_max := 1.0
	for axis in 3:
		var origin := from[axis] - centre[axis]
		var dir := d[axis]
		if absf(dir) < 0.000001:
			if absf(origin) > half[axis]:
				return -1.0
			continue
		var inv := 1.0 / dir
		var t1 := (-half[axis] - origin) * inv
		var t2 := (half[axis] - origin) * inv
		if t1 > t2:
			var swap := t1
			t1 = t2
			t2 = swap
		t_min = maxf(t_min, t1)
		t_max = minf(t_max, t2)
		if t_min > t_max:
			return -1.0
	return t_min


static func segment_hits_capsule(from: Vector3, to: Vector3, base: Vector3, radius: float,
		height: float) -> float:
	var lower := base + Vector3.UP * radius
	var upper := base + Vector3.UP * maxf(height - radius, radius)
	var best := -1.0

	var d := to - from
	var m := from - lower
	var axis := upper - lower
	var axis_len_sq := axis.dot(axis)

	if axis_len_sq > 0.000001:
		var md := m.dot(axis)
		var nd := d.dot(axis)
		var dd := d.dot(d)
		var nn := m.dot(d)
		var mm := m.dot(m)
		var a := dd * axis_len_sq - nd * nd
		var k := mm - radius * radius
		var c := k * axis_len_sq - md * md
		if absf(a) > 0.000001:
			var b := axis_len_sq * nn - nd * md
			var disc := b * b - a * c
			if disc >= 0.0:
				var t := (-b - sqrt(disc)) / a
				if t >= 0.0 and t <= 1.0:
					var proj := md + t * nd
					if proj >= 0.0 and proj <= axis_len_sq:
						best = t

	for cap_centre in [lower, upper]:
		var t := segment_hits_sphere(from, to, cap_centre, radius)
		if t >= 0.0 and (best < 0.0 or t < best):
			best = t
	return best
