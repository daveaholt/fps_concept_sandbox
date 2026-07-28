# 02 — Input Map

All actions are defined in `project.godot` under a flat namespace; contexts share physical keys where it feels natural (W is always "go forward-ish"). Each controller only reads the actions in its own column, gated by `is_possessed`, so overlap is safe.

Every gameplay action carries **both** a keyboard/mouse binding and an Xbox-layout gamepad binding, so either input device drives the game with no mode switch — they are simply two event lists on the same action, and the sampler never asks which one is in use.

## Global (always active)

| Action | Keyboard / mouse | Gamepad | Notes |
|---|---|---|---|
| `toggle_deploy_map` | M | Back | Ignored while dead (map already open) |
| `interact` | E | X | Enter vehicle / context actions |
| `ui_cancel` | Esc | — | Release mouse (dev convenience) |
| `toggle_fullscreen` | F11 | — | Borderless fullscreen; not persisted between runs |

## Infantry

| Action | Keyboard / mouse | Gamepad | Notes |
|---|---|---|---|
| `move_forward` / `move_back` | W / S | Left stick Y | Analog magnitude is throttle |
| `move_left` / `move_right` | A / D | Left stick X | |
| `jump` | Space | A | |
| `sprint` | Shift (hold) | L3 | |
| `fire` | LMB | RT | Current weapon (03); hold = auto for rifle |
| `weapon_primary` | 1 | D-pad up | Rifle |
| `weapon_secondary` | 2 | D-pad down | Pistol |
| `weapon_cycle_up` / `weapon_cycle_down` | Scroll up / down | Y / D-pad left | Y is the conventional "swap" |
| `look_up` … `look_right` | *(mouse)* | Right stick | See look handling below |

## Tank

| Action | Keyboard / mouse | Gamepad | Notes |
|---|---|---|---|
| `move_forward` / `move_back` | W / S | Left stick Y | Tread throttle |
| `move_left` / `move_right` | A / D | Left stick X | Differential steer (in place when no throttle) |
| `fire` | LMB | RT | Cannon (shared action with infantry — safe, different possessee) |
| `brake` | Space | A | Reuses jump's key; separate action name |
| *turret* | Mouse | Right stick | Turret yaw + cannon pitch follow camera |
| `exit_vehicle` | F | B | |

## Helicopter

| Action | Keyboard / mouse | Gamepad | Notes |
|---|---|---|---|
| `collective_up` / `collective_down` | Space / Ctrl | RT / LT | Lift |
| `cyclic_forward` / `cyclic_back` | W / S | Left stick Y | Pitch |
| `cyclic_left` / `cyclic_right` | A / D | Left stick X | Roll |
| `yaw_left` / `yaw_right` | Q / E | LB / RB | Pedals |
| `toggle_engine` | R | Y | Spool up / down |
| `toggle_camera` | V | R3 | First-person ↔ chase cam |
| `exit_vehicle` | F | B | Only meaningful when landed (see 06) |

## Look handling

Mouse look is a **displacement**: each motion event turns into a yaw/pitch delta scaled by `mouse_sensitivity_deg_per_px`, so it is frame-rate independent for free.

Stick look is a **rate**: `look_*` action strengths become degrees per second, scaled by `delta`. It gets a response curve (`stick_look_exponent`, default squared) because a linear stick makes fine aim impossible while still feeling slow at full deflection. Both paths write the same yaw/pitch, which becomes the command's `aim` vector — the simulation cannot tell them apart.

Stick deadzone is 0.2 for sticks and 0.5 for triggers-as-buttons. The 0.5 default Godot ships would eat most of a stick's usable travel.

**Vertical look is inverted by default** (`invert_look_y`, exported on the sampler): pushing down raises the aim. The flag applies to mouse and stick together, since both write pitch through one function — split it into two exports if the two devices ever want different answers.

## Deploy map (mouse-driven)

LMB selects a spawn marker; **Deploy** button (or Enter / A) confirms; M / Esc closes the map *if* currently alive. No keyboard marker navigation in the prototype.

## Networked sampling

Under the server-authoritative model (10), these actions are only ever read on the **client**, where they are packed each tick into the input command (`move` vector, `buttons` bitmask, `axes`) and sent to the server. Sim code consumes commands, never `Input`. This doc therefore defines the *fields of the command struct* as much as the keybindings.

## Conventions

- Movement is read with `Input.get_vector("move_left", "move_right", "move_forward", "move_back")` for infantry/tank; the heli reads individual axes because collective and pedals aren't a natural vector.
- `exit_vehicle` (F) is deliberately a different key from `interact` (E) to avoid instant re-entry bounces. Cheap and effective.
- All bindings are defaults; no rebinding UI in the prototype.

## Open questions

- Mouse-look for heli cyclic instead of WASD (freeing WASD for nothing)? Current call: keys for cyclic, mouse for free-look in cockpit — revisit after first flight test (see 06 open questions).
- M0: `weapon_cycle` is defined as two actions, `weapon_cycle_up` / `weapon_cycle_down`, matching the bitmask field list in 10. `ui_cancel` is left on Godot's default Esc binding rather than redefined. Added `deploy_confirm` (Enter) for 07's Deploy button.
- M1: the dev damage key (K, per 08) is read as a raw physical key by the client-side sampler rather than added as an action, so the gameplay input map stays exactly what this doc specifies.
- Post-M1: added `toggle_fullscreen` (F11) and four `look_*` actions, and gave every gameplay action an Xbox-layout gamepad binding. The `look_*` actions are gamepad-only — mouse look stays event-driven rather than polled, so it needs no action.
- Post-M1: no rebinding UI still, but the gamepad layer means the "no rebinding" cost is now higher for a controller player, since stick inversion is a common preference. An `invert_look_y` toggle is the cheap first concession if it comes up.
- Post-M1: action events must carry `device = -1` ("any device"). Events built in code default to a concrete device id, which silently produces an action that matches nothing (F11) or only the first controller (the gamepad bindings). Anything that generates bindings has to normalise this.
- Post-M1: `invert_look_y` landed and defaults to **true**. Noted because it inverts the convention most FPS players expect, so it is a deliberate project default rather than an oversight.
- Post-M1: `toggle_fullscreen` does nothing when the game runs **embedded in the editor** — Godot refuses any non-Windowed mode for an embedded window ("Embedded window only supports Windowed mode"). This is environment, not code: it works standalone. `WindowMode.set_fullscreen()` returns false and warns with the fix rather than failing silently. Turn embedding off via Editor Settings > Run > Window Placement > Game Embed Mode.
