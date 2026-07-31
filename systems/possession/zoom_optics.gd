class_name ZoomOptics
extends RefCounted

const BASE_FOV := 75.0
const VEHICLE_FOV := 34.0
const MIN_SENSITIVITY := 0.15


static func sensitivity_for(fov: float) -> float:
	return clampf(fov / BASE_FOV, MIN_SENSITIVITY, 1.0)


static func magnification(fov: float) -> float:
	return BASE_FOV / maxf(fov, 0.001)
