class_name HitZones
extends Resource

const KIND_SPHERE := 0
const KIND_BOX := 1

@export var zone_names: PackedStringArray = PackedStringArray()
@export var kinds: PackedInt32Array = PackedInt32Array()
@export var centres: PackedVector3Array = PackedVector3Array()
@export var extents: PackedVector3Array = PackedVector3Array()
@export var multipliers: PackedFloat32Array = PackedFloat32Array()
@export var fallback_multiplier: float = 1.0


func count() -> int:
	return zone_names.size()


func resolve(local_from: Vector3, local_to: Vector3) -> Dictionary:
	var best_t := 2.0
	var best := -1

	for i in range(zone_names.size()):
		var t := -1.0
		if kinds[i] == KIND_SPHERE:
			t = Ballistics.segment_hits_sphere(local_from, local_to, centres[i], extents[i].x)
		else:
			t = Ballistics.segment_hits_box(local_from, local_to, centres[i], extents[i])
		if t >= 0.0 and t < best_t:
			best_t = t
			best = i

	if best < 0:
		return {"zone": "body", "multiplier": fallback_multiplier}
	return {"zone": zone_names[best], "multiplier": multipliers[best]}
