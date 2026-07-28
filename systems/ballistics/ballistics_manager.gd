class_name BallisticsManager
extends Node3D

const MAX_PROJECTILES := 512
const WORLD_MASK := 1
const COMPENSATION_DECAY_SECONDS := 0.3

@export var params_paths: Array[String] = [
	"res://assets/ballistics/rifle_round.tres",
	"res://assets/ballistics/pistol_round.tres",
]

var authoritative: bool = false
var hits_logged: int = 0

var _params: Array[ProjectileParams] = []
var _live: Array[Dictionary] = []
var _gravity: float = 9.8
var _multimesh: MultiMesh
var _targets: Array = []


func _ready() -> void:
	_gravity = ProjectSettings.get_setting("physics/3d/default_gravity", 9.8)
	for path in params_paths:
		var res: ProjectileParams = load(path)
		if res != null:
			_params.append(res)
	_build_tracers()


func params_for(index: int) -> ProjectileParams:
	if _params.is_empty():
		return null
	return _params[clampi(index, 0, _params.size() - 1)]


func live_count() -> int:
	return _live.size()


func register_target(entity: Node) -> void:
	if not _targets.has(entity):
		_targets.append(entity)


func unregister_target(entity: Node) -> void:
	_targets.erase(entity)


func spawn(origin: Vector3, direction: Vector3, params_id: int, shooter_peer: int,
		view_delay: float) -> void:
	var params := params_for(params_id)
	if params == null or _live.size() >= MAX_PROJECTILES:
		return
	_live.append({
		"pos": origin,
		"vel": direction.normalized() * params.muzzle_velocity,
		"params_id": params_id,
		"shooter": shooter_peer,
		"time": 0.0,
		"view_delay": view_delay,
	})


func _physics_process(delta: float) -> void:
	if _live.is_empty():
		_update_tracers()
		return

	var survivors: Array[Dictionary] = []
	var now := _now()

	for p in _live:
		var params := params_for(p["params_id"])
		var from: Vector3 = p["pos"]
		var stepped := Ballistics.step(from, p["vel"], params, _gravity, delta)
		var to: Vector3 = stepped["pos"]

		p["time"] = float(p["time"]) + delta
		var impact := _trace(from, to, p, now) if authoritative else {}

		if not impact.is_empty():
			_on_impact(p, impact, params)
			continue

		p["pos"] = to
		p["vel"] = stepped["vel"]
		if float(p["time"]) < params.max_lifetime:
			survivors.append(p)

	_live = survivors
	_update_tracers()


func _now() -> float:
	return float(Time.get_ticks_msec()) * 0.001


func _rewind_offset(projectile: Dictionary) -> float:
	var flight: float = projectile["time"]
	var decay := clampf(1.0 - flight / COMPENSATION_DECAY_SECONDS, 0.0, 1.0)
	return float(projectile["view_delay"]) * decay


func _trace(from: Vector3, to: Vector3, projectile: Dictionary, now: float) -> Dictionary:
	var best_t := 2.0
	var best := {}

	var space := get_world_3d().direct_space_state
	var ray := PhysicsRayQueryParameters3D.create(from, to)
	ray.collision_mask = WORLD_MASK
	ray.exclude = _target_rids()
	var world_hit := space.intersect_ray(ray)
	if not world_hit.is_empty():
		var point: Vector3 = world_hit["position"]
		var denom := (to - from).length()
		best_t = 0.0 if denom <= 0.0 else (point - from).length() / denom
		best = {"point": point, "target": null, "zone": "world", "multiplier": 0.0}

	var sample_time := now - _rewind_offset(projectile)
	for target in _targets:
		if not is_instance_valid(target) or target.owner_peer == int(projectile["shooter"]):
			continue
		var hit := _trace_entity(from, to, target, sample_time)
		if hit.is_empty():
			continue
		if float(hit["t"]) < best_t:
			best_t = hit["t"]
			best = hit

	return best


func _target_rids() -> Array[RID]:
	var rids: Array[RID] = []
	for target in _targets:
		if is_instance_valid(target) and target is CollisionObject3D:
			rids.append((target as CollisionObject3D).get_rid())
	return rids


func _trace_entity(from: Vector3, to: Vector3, target: Node, sample_time: float) -> Dictionary:
	var history: PositionHistory = target.get_history()
	var snap := history.sample(sample_time)
	if snap.is_empty():
		return {}

	var base: Vector3 = snap["position"]
	var tuning: InfantryTuning = target.tuning
	var t := Ballistics.segment_hits_capsule(from, to, base, tuning.capsule_radius, tuning.capsule_height)
	if t < 0.0:
		return {}

	var zone := {"zone": "body", "multiplier": 1.0}
	var zones: HitZones = target.hit_zones
	if zones != null:
		var aim: Vector3 = snap["aim"]
		var forward := InfantrySim.flat_forward(aim)
		var yaw := atan2(-forward.x, -forward.z)
		var inverse := Transform3D(Basis(Vector3.UP, yaw), base).affine_inverse()
		zone = zones.resolve(inverse * from, inverse * to)

	return {
		"t": t,
		"point": from.lerp(to, t),
		"target": target,
		"zone": zone["zone"],
		"multiplier": zone["multiplier"],
	}


func _on_impact(projectile: Dictionary, impact: Dictionary, params: ProjectileParams) -> void:
	var target = impact.get("target")
	if target == null or not is_instance_valid(target):
		return

	var speed: float = (projectile["vel"] as Vector3).length()
	var damage: float = params.energy_damage(speed) * float(impact["multiplier"])
	hits_logged += 1
	print("[hit] %s zone=%s x%.2f dmg=%.1f speed=%.0fm/s flight=%.3fs rewind=%.3fs"
		% [target.name, impact["zone"], impact["multiplier"], damage, speed,
			projectile["time"], _rewind_offset(projectile)])
	target.apply_damage(damage)


func _build_tracers() -> void:
	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.06, 0.06, 1.0)
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(1.0, 0.85, 0.4)
	material.emission_enabled = true
	material.emission = Color(1.0, 0.8, 0.3)
	material.emission_energy_multiplier = 6.0
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mesh.material = material

	_multimesh = MultiMesh.new()
	_multimesh.transform_format = MultiMesh.TRANSFORM_3D
	_multimesh.mesh = mesh
	_multimesh.instance_count = MAX_PROJECTILES
	_multimesh.visible_instance_count = 0

	var holder := MultiMeshInstance3D.new()
	holder.name = "Tracers"
	holder.multimesh = _multimesh
	holder.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(holder)


func _update_tracers() -> void:
	if _multimesh == null:
		return
	var count := mini(_live.size(), MAX_PROJECTILES)
	_multimesh.visible_instance_count = count
	for i in range(count):
		var p := _live[i]
		var vel: Vector3 = p["vel"]
		var params := params_for(p["params_id"])
		var length := minf(params.tracer_length, vel.length() * 0.02)
		var direction := vel.normalized() if vel.length_squared() > 0.001 else Vector3.FORWARD
		var basis := Basis().looking_at(direction, Vector3.UP).scaled(Vector3(1, 1, maxf(length, 0.5)))
		_multimesh.set_instance_transform(i, Transform3D(basis, p["pos"]))
