# 02 — Input Map

All actions are defined in `project.godot` under a flat namespace; contexts share physical keys where it feels natural (W is always "go forward-ish"). Each controller only reads the actions in its own column, gated by `is_possessed`, so overlap is safe.

## Global (always active)

| Action | Default binding | Notes |
|---|---|---|
| `toggle_deploy_map` | M | Ignored while dead (map already open) |
| `interact` | E | Enter vehicle / context actions |
| `ui_cancel` | Esc | Release mouse (dev convenience) |

## Infantry

| Action | Binding | Notes |
|---|---|---|
| `move_forward` / `move_back` | W / S | |
| `move_left` / `move_right` | A / D | |
| `jump` | Space | |
| `sprint` | Shift (hold) | |
| `fire` | LMB | Current weapon (03); hold = auto for rifle |
| `weapon_primary` | 1 | Rifle |
| `weapon_secondary` | 2 | Pistol |
| `weapon_cycle` | Scroll up/down | Cycles slots |
| *look* | Mouse | Captured; sensitivity exported on player |

## Tank

| Action | Binding | Notes |
|---|---|---|
| `move_forward` / `move_back` | W / S | Tread throttle |
| `move_left` / `move_right` | A / D | Differential steer (in place when no throttle) |
| `fire` | LMB | Cannon (shared action with infantry — safe, different possessee) |
| `brake` | Space | Reuses jump's key; separate action name |
| *turret* | Mouse | Turret yaw + cannon pitch follow camera |
| `exit_vehicle` | F | |

## Helicopter

| Action | Binding | Notes |
|---|---|---|
| `collective_up` / `collective_down` | Space / Ctrl | Lift |
| `cyclic_forward` / `cyclic_back` | W / S | Pitch |
| `cyclic_left` / `cyclic_right` | A / D | Roll |
| `yaw_left` / `yaw_right` | Q / E | Pedals |
| `toggle_engine` | R | Spool up / down |
| `toggle_camera` | V | First-person ↔ chase cam |
| `exit_vehicle` | F | Only meaningful when landed (see 06) |

## Deploy map (mouse-driven)

LMB selects a spawn marker; **Deploy** button (or Enter) confirms; M / Esc closes the map *if* currently alive. No keyboard marker navigation in the prototype.

## Networked sampling

Under the server-authoritative model (10), these actions are only ever read on the **client**, where they are packed each tick into the input command (`move` vector, `buttons` bitmask, `axes`) and sent to the server. Sim code consumes commands, never `Input`. This doc therefore defines the *fields of the command struct* as much as the keybindings.

## Conventions

- Movement is read with `Input.get_vector("move_left", "move_right", "move_forward", "move_back")` for infantry/tank; the heli reads individual axes because collective and pedals aren't a natural vector.
- `exit_vehicle` (F) is deliberately a different key from `interact` (E) to avoid instant re-entry bounces. Cheap and effective.
- All bindings are defaults; no rebinding UI in the prototype.

## Open questions

- Mouse-look for heli cyclic instead of WASD (freeing WASD for nothing)? Current call: keys for cyclic, mouse for free-look in cockpit — revisit after first flight test (see 06 open questions).
- M0: `weapon_cycle` is defined as two actions, `weapon_cycle_up` / `weapon_cycle_down`, matching the bitmask field list in 10. `ui_cancel` is left on Godot's default Esc binding rather than redefined. Added `deploy_confirm` (Enter) for 07's Deploy button.
