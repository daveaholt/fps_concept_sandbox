class_name VehicleDamage
extends RefCounted

enum State { HEALTHY, DAMAGED, CRITICAL, DESTROYED }

const DAMAGED_BELOW := 0.6
const CRITICAL_BELOW := 0.3

const MOBILITY := {
	State.HEALTHY: 1.0,
	State.DAMAGED: 0.85,
	State.CRITICAL: 0.6,
	State.DESTROYED: 0.0,
}

const TRAVERSE := {
	State.HEALTHY: 1.0,
	State.DAMAGED: 0.9,
	State.CRITICAL: 0.65,
	State.DESTROYED: 0.0,
}

const TINT := {
	State.HEALTHY: 1.0,
	State.DAMAGED: 0.78,
	State.CRITICAL: 0.5,
	State.DESTROYED: 0.22,
}

const LABEL := {
	State.HEALTHY: "",
	State.DAMAGED: "DAMAGED",
	State.CRITICAL: "CRITICAL",
	State.DESTROYED: "DESTROYED",
}


static func state_for(fraction: float) -> State:
	if fraction <= 0.0:
		return State.DESTROYED
	if fraction < CRITICAL_BELOW:
		return State.CRITICAL
	if fraction < DAMAGED_BELOW:
		return State.DAMAGED
	return State.HEALTHY


static func mobility(state: State) -> float:
	return MOBILITY.get(state, 1.0)


static func traverse(state: State) -> float:
	return TRAVERSE.get(state, 1.0)


static func tint(state: State) -> float:
	return TINT.get(state, 1.0)


static func label(state: State) -> String:
	return LABEL.get(state, "")
