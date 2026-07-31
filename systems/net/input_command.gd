class_name InputCommand
extends RefCounted

const JUMP := 1 << 0
const SPRINT := 1 << 1
const FIRE := 1 << 2
const INTERACT := 1 << 3
const EXIT := 1 << 4
const BRAKE := 1 << 5
const ENGINE := 1 << 6
const WEAPON_PRIMARY := 1 << 7
const WEAPON_SECONDARY := 1 << 8
const WEAPON_CYCLE_UP := 1 << 9
const WEAPON_CYCLE_DOWN := 1 << 10
const RELOAD := 1 << 11

var tick: int = 0
var move: Vector2 = Vector2.ZERO
var buttons: int = 0
var aim: Vector3 = Vector3.FORWARD
var axes: Vector2 = Vector2.ZERO


static func make(p_tick: int, p_move: Vector2, p_buttons: int, p_aim: Vector3, p_axes := Vector2.ZERO) -> InputCommand:
	var cmd := InputCommand.new()
	cmd.tick = p_tick
	cmd.move = p_move.limit_length(1.0)
	cmd.buttons = p_buttons
	cmd.aim = p_aim.normalized() if p_aim.length_squared() > 0.0 else Vector3.FORWARD
	cmd.axes = p_axes.limit_length(1.0)
	return cmd


func held(mask: int) -> bool:
	return (buttons & mask) != 0


func to_dict() -> Dictionary:
	return {"tick": tick, "move": move, "buttons": buttons, "aim": aim, "axes": axes}


static func from_dict(d: Dictionary) -> InputCommand:
	return make(d.get("tick", 0), d.get("move", Vector2.ZERO), d.get("buttons", 0),
		d.get("aim", Vector3.FORWARD), d.get("axes", Vector2.ZERO))


func clone() -> InputCommand:
	return make(tick, move, buttons, aim, axes)
