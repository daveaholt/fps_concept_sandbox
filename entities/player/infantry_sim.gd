class_name InfantrySim
extends RefCounted

static var _query_cache: Dictionary = {}
static var _penetration_cache: Dictionary = {}


static func simulate(state: InfantryState, cmd: InputCommand, tuning: InfantryTuning,
		space: PhysicsDirectSpaceState3D, delta: float) -> InfantryState:
	var s := state.clone()
	s.position = _resolve_penetration(s.position, tuning, space)

	var forward := flat_forward(cmd.aim)
	var right := forward.cross(Vector3.UP).normalized()

	var wish := right * cmd.move.x + forward * cmd.move.y
	wish.y = 0.0
	var throttle := minf(wish.length(), 1.0)
	var wish_dir := wish.normalized() if throttle > 0.001 else Vector3.ZERO

	var speed := tuning.walk_speed
	if cmd.held(InputCommand.SPRINT) and wish_dir.dot(forward) > tuning.sprint_forward_dot:
		speed = tuning.sprint_speed

	var target := wish_dir * speed * throttle
	var accel := tuning.accel if s.on_floor else tuning.air_accel
	var horizontal := Vector3(s.velocity.x, 0.0, s.velocity.z).move_toward(target, accel * delta)
	s.velocity.x = horizontal.x
	s.velocity.z = horizontal.z

	if s.on_floor:
		if cmd.held(InputCommand.JUMP):
			s.velocity.y = tuning.jump_velocity
			s.on_floor = false
		else:
			s.velocity.y = 0.0
	else:
		s.velocity.y -= tuning.gravity_accel() * delta

	var move_from := s.position
	if s.on_floor:
		move_from += Vector3.UP * tuning.floor_probe_lift

	var moved := _collide_and_slide(move_from, s.velocity * delta, tuning, space)
	s.position = moved.position
	for normal in moved.normals:
		s.velocity = s.velocity.slide(normal)

	var floor_probe := _probe_floor(s.position, tuning, space)
	s.on_floor = floor_probe.on_floor and s.velocity.y <= 0.001
	s.floor_normal = floor_probe.normal
	if s.on_floor:
		s.position = floor_probe.position
		s.velocity.y = 0.0

	_step_weapons(s, cmd, tuning, delta)
	s.prev_buttons = cmd.buttons
	return s


static func flat_forward(aim: Vector3) -> Vector3:
	var flat := Vector3(aim.x, 0.0, aim.z)
	if flat.length_squared() < 0.000001:
		return Vector3.FORWARD
	return flat.normalized()


static func eye_position(state: InfantryState, tuning: InfantryTuning, eye_height: float) -> Vector3:
	return state.position + Vector3.UP * minf(eye_height, tuning.capsule_height)


static func _step_weapons(s: InfantryState, cmd: InputCommand, tuning: InfantryTuning, delta: float) -> void:
	var pressed := cmd.buttons & ~s.prev_buttons
	var count := maxi(tuning.weapons.size(), 1)
	var desired := s.weapon_index

	if (pressed & InputCommand.WEAPON_PRIMARY) != 0:
		desired = 0
	elif (pressed & InputCommand.WEAPON_SECONDARY) != 0:
		desired = 1
	elif (pressed & InputCommand.WEAPON_CYCLE_UP) != 0:
		desired = s.weapon_index + 1
	elif (pressed & InputCommand.WEAPON_CYCLE_DOWN) != 0:
		desired = s.weapon_index - 1

	desired = posmod(desired, count)
	if desired != s.weapon_index:
		s.weapon_index = desired
		s.switch_progress = 0.0
		s.reload_timer = 0.0

	if s.magazine.size() != tuning.weapons.size():
		s.arm(tuning)

	var weapon := tuning.weapon_at(s.weapon_index)
	if s.switch_progress < 1.0:
		var draw := weapon.draw_time if weapon != null else 0.0
		s.switch_progress = 1.0 if draw <= 0.0 else minf(1.0, s.switch_progress + delta / draw)

	s.fire_cooldown = maxf(0.0, s.fire_cooldown - delta)

	if weapon == null:
		return

	if s.reload_timer > 0.0:
		s.reload_timer = maxf(0.0, s.reload_timer - delta)
		if s.reload_timer <= 0.0:
			_finish_reload(s, weapon)
		return

	if s.switch_progress < 1.0:
		return

	var wants_shot := false
	if weapon.fire_mode == WeaponDef.FireMode.FULL_AUTO:
		wants_shot = cmd.held(InputCommand.FIRE)
	else:
		wants_shot = (pressed & InputCommand.FIRE) != 0

	var empty := s.loaded(s.weapon_index) <= 0
	if (pressed & InputCommand.RELOAD) != 0 or (wants_shot and empty):
		_begin_reload(s, weapon)
		return

	if s.fire_cooldown > 0.0 or empty or not wants_shot:
		return

	s.magazine[s.weapon_index] -= 1
	s.shots_fired += 1
	s.fire_cooldown = weapon.seconds_per_shot()


static func _begin_reload(s: InfantryState, weapon: WeaponDef) -> void:
	if s.loaded(s.weapon_index) >= weapon.magazine_size:
		return
	if s.spare(s.weapon_index) <= 0:
		return
	s.reload_timer = maxf(weapon.reload_time, 0.0001)


static func _finish_reload(s: InfantryState, weapon: WeaponDef) -> void:
	var index := s.weapon_index
	var wanted: int = weapon.magazine_size - s.loaded(index)
	var moved: int = mini(wanted, s.spare(index))
	if moved <= 0:
		return
	s.magazine[index] += moved
	s.reserve[index] -= moved


static func _collide_and_slide(from: Vector3, motion: Vector3, tuning: InfantryTuning,
		space: PhysicsDirectSpaceState3D) -> Dictionary:
	var params := _query_for(tuning)
	var current := from
	var remaining := motion
	var normals: Array[Vector3] = []

	for _slide in range(tuning.max_slides):
		if remaining.length_squared() < 0.0000001:
			break

		var start := current
		params.transform = Transform3D(Basis(), _shape_origin(start, tuning))
		params.motion = remaining
		var fractions := space.cast_motion(params)
		if fractions.size() < 2:
			current = start + remaining
			remaining = Vector3.ZERO
			break

		var safe := fractions[0]
		var unsafe := fractions[1]
		current = start + remaining * safe
		if safe >= 1.0:
			remaining = Vector3.ZERO
			break

		params.transform = Transform3D(Basis(), _shape_origin(start + remaining * unsafe, tuning))
		params.motion = Vector3.ZERO
		var rest := space.get_rest_info(params)
		if rest.is_empty():
			remaining = Vector3.ZERO
			break

		var normal: Vector3 = rest.get("normal", Vector3.UP)
		normals.append(normal)
		remaining = (remaining * (1.0 - safe)).slide(normal)

	return {"position": current, "normals": normals}


static func _probe_floor(from: Vector3, tuning: InfantryTuning, space: PhysicsDirectSpaceState3D) -> Dictionary:
	var airborne := {"on_floor": false, "normal": Vector3.UP, "position": from}

	var ray := PhysicsRayQueryParameters3D.create(
		from + Vector3.UP * tuning.floor_probe_lift,
		from + Vector3.DOWN * tuning.floor_snap_distance)
	ray.collision_mask = tuning.collision_mask
	var hit := space.intersect_ray(ray)
	if hit.is_empty():
		return airborne

	var normal: Vector3 = hit.get("normal", Vector3.UP)
	if rad_to_deg(normal.angle_to(Vector3.UP)) > tuning.floor_max_angle_deg:
		return {"on_floor": false, "normal": normal, "position": from}

	var contact: Vector3 = hit["position"]
	var cosine := maxf(normal.dot(Vector3.UP), 0.001)
	var rest_height := tuning.capsule_radius * (1.0 / cosine - 1.0)
	return {
		"on_floor": true,
		"normal": normal,
		"position": Vector3(from.x, contact.y + rest_height, from.z),
	}


static func _resolve_penetration(from: Vector3, tuning: InfantryTuning,
		space: PhysicsDirectSpaceState3D) -> Vector3:
	var probe := _penetration_query_for(tuning)
	var contact := _query_for(tuning)
	var out := from

	for _attempt in range(tuning.max_depenetration_steps):
		probe.transform = Transform3D(Basis(), _shape_origin(out, tuning))
		if space.intersect_shape(probe, 1).is_empty():
			break
		contact.transform = Transform3D(Basis(), _shape_origin(out, tuning))
		contact.motion = Vector3.ZERO
		var rest := space.get_rest_info(contact)
		var normal: Vector3 = rest.get("normal", Vector3.UP) if not rest.is_empty() else Vector3.UP
		out += normal * tuning.depenetration_step

	return out


static func _shape_origin(feet: Vector3, tuning: InfantryTuning) -> Vector3:
	return feet + Vector3.UP * tuning.capsule_height * 0.5


static func _penetration_query_for(tuning: InfantryTuning) -> PhysicsShapeQueryParameters3D:
	var key := tuning.get_instance_id()
	var cached: Dictionary = _penetration_cache.get(key, {})
	if cached.get("radius", -1.0) != tuning.capsule_radius \
			or cached.get("height", -1.0) != tuning.capsule_height \
			or cached.get("mask", -1) != tuning.collision_mask \
			or cached.get("inset", -1.0) != tuning.penetration_inset:
		var shape := CapsuleShape3D.new()
		shape.radius = maxf(0.05, tuning.capsule_radius - tuning.penetration_inset)
		shape.height = maxf(0.2, tuning.capsule_height - tuning.penetration_inset * 2.0)
		var params := PhysicsShapeQueryParameters3D.new()
		params.shape = shape
		params.collision_mask = tuning.collision_mask
		params.margin = 0.0
		cached = {
			"radius": tuning.capsule_radius, "height": tuning.capsule_height,
			"mask": tuning.collision_mask, "inset": tuning.penetration_inset,
			"params": params,
		}
		_penetration_cache[key] = cached
	return cached["params"]


static func _query_for(tuning: InfantryTuning) -> PhysicsShapeQueryParameters3D:
	var key := tuning.get_instance_id()
	var cached: Dictionary = _query_cache.get(key, {})
	if cached.get("radius", -1.0) != tuning.capsule_radius \
			or cached.get("height", -1.0) != tuning.capsule_height \
			or cached.get("mask", -1) != tuning.collision_mask \
			or cached.get("margin", -1.0) != tuning.skin_width:
		var shape := CapsuleShape3D.new()
		shape.radius = tuning.capsule_radius
		shape.height = tuning.capsule_height
		var params := PhysicsShapeQueryParameters3D.new()
		params.shape = shape
		params.collision_mask = tuning.collision_mask
		params.margin = tuning.skin_width
		cached = {
			"radius": tuning.capsule_radius, "height": tuning.capsule_height,
			"mask": tuning.collision_mask, "margin": tuning.skin_width,
			"params": params,
		}
		_query_cache[key] = cached
	return cached["params"]
