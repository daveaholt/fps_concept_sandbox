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
| `fire` | LMB | RT | Cannon, driver seat only |
| `zoom` | RMB | LT | |
| `brake` | Space | LB | Reuses jump's key; separate action name |
| *turret* | Mouse | Right stick | Turret yaw + cannon pitch follow camera |
| `toggle_camera` | V | R3 | Chase ↔ gun sight (first person) |
| `switch_seat` | C | A | Driver ↔ machine gunner |
| `exit_vehicle` | F | B | |

Both tank seats use the infantry weapon controls — **RT** fires, **LT** zooms. The tank drives on the left stick and never touches the triggers, so there is nothing for them to collide with.

## Helicopter

Revised at M6 to a flight-game pad layout. The cyclic moved to the **right** stick, yaw to the **left** stick, and collective to the **triggers**, which frees the shoulder buttons and face buttons for weapons and seats.

| Action | Keyboard / mouse | Gamepad | Notes |
|---|---|---|---|
| `heli_collective_up` / `_down` | Space / Ctrl | RT / LT | Lift |
| `heli_pitch_down` / `_up` | W / S | Right stick Y | Cyclic pitch. **Stick forward and W are nose down**, flight-stick convention |
| `heli_roll_left` / `_right` | A / D | Right stick X | Cyclic roll |
| `heli_yaw_left` / `_right` | Q / E | Left stick X | Pedals |
| `vehicle_fire` | LMB | RB | Rocket pods, pilot seat only |
| `toggle_camera` | V | R3 | Cockpit ↔ chase cam |
| `switch_seat` | C | A | Pilot ↔ minigunner |
| `exit_vehicle` | F | B | Only meaningful when landed (see 06) |

The minigunner seat uses the infantry weapon controls: `fire` on **RT** / LMB, `zoom` on **LT** / RMB. Still unbound: **Y** weapon toggle. Left stick Y is unused in the heli. There is no engine button — see 06.

The heli needs four analog channels (pitch, roll, yaw, collective) and `InputCommand` carries exactly four (`move.x/y`, `axes.x/y`), so no new network field was needed: `move` is the cyclic and `axes` is `(yaw, collective)`. The sampler fills them from the `heli_*` actions **only while the possessed entity is in the `helicopter` group**, which is why these are separate actions rather than rebindings of `move_*` — rebinding those would have moved infantry onto the right stick too.

## Look handling

Mouse look is a **displacement**: each motion event turns into a yaw/pitch delta scaled by `mouse_sensitivity_deg_per_px`, so it is frame-rate independent for free.

Stick look is a **rate**: `look_*` action strengths become degrees per second, scaled by `delta`. It gets a response curve (`stick_look_exponent`, default squared) because a linear stick makes fine aim impossible while still feeling slow at full deflection. Both paths write the same yaw/pitch, which becomes the command's `aim` vector — the simulation cannot tell them apart.

Stick deadzone is 0.2 for sticks and 0.5 for triggers-as-buttons. The 0.5 default Godot ships would eat most of a stick's usable travel.

**Vertical look is inverted by default** (`invert_look_y`, exported on the sampler): pushing down raises the aim. The flag applies to mouse and stick together, since both write pitch through one function — split it into two exports if the two devices ever want different answers.

## Deploy map (mouse-driven)

LMB selects a spawn marker; **Deploy** button (or Enter / A) confirms; M / Esc closes the map *if* currently alive. **M7: either stick also moves the selection between markers**, so the screen is fully usable on a pad — see 07. Still no keyboard *arrow-key* navigation; the keyboard path is the mouse.

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
- Post-M3: input is gated on window focus, and an unfocused window sends a **neutral** command rather than no command. Godot polls joypads at the process level rather than delivering them through the focused window, so every running instance reads the same physical controller at once — with two instances open for multiplayer testing, one gamepad drove both. Sending nothing would have been worse than sending neutral: the server reuses the last command on starvation, so a player would keep running after their window lost focus. Bots and headless runs bypass the gate.
- **M7: the interaction scanner now gates enter/exit on window focus, like the sampler already did.** It polled `Input` directly with no focus check. Keyboard is focus-gated by the OS so this never showed, but **joypads are polled process-wide** — the same behaviour reported at M3 as "my controller controls both windows regardless of focus". The consequence was that one press of B exited the vehicle in *both* windows, which read as "exiting the heli exited both players". The decision lives in `InputFocus.may_act()`, a plain helper with no autoload reference, because `InteractionScanner` cannot be constructed in a `--script` harness — it references `GameClient`, and autoload identifiers do not resolve at compile time there.
- M7: worth checking any other place that reads `Input` outside the sampler. Two-window testing makes an ungated poll look like a gameplay bug rather than an input bug, and it will not reproduce on the keyboard.
- M7: `yaw_left` / `yaw_right` are **deleted**. They were the pre-M6 heli pedals, replaced by `heli_yaw_*`, and nothing had read them since. They were still holding LB and RB, which collided with the new `vehicle_fire` on RB and the tank brake moved to LB. A dead action that still owns a button is worse than no action at all.
- M7: `vehicle_fire` (RB, left mouse) fires what the **driver's** seat holds — tank cannon or heli rockets. It exists because `fire` sits on RT, which is the helicopter's collective: a pilot holding RT to climb would otherwise empty the rocket pods. The sampler picks the action from the occupied seat, not from "am I in a vehicle".
- M7: **gunner seats keep the infantry scheme — RT fires, LT zooms.** The first cut routed every seat to `vehicle_fire`, which put the gunner on RB. A gunner is an infantry role that happens to sit in a vehicle, and the collective clash that justified RB only applies to the pilot. `InputSampler.fire_action()` returns `vehicle_fire` for `Seats.DRIVER` and `fire` for everyone else, so the rule is one function rather than a condition repeated per vehicle.
- M7: added `zoom` (LT, right mouse). It drives `GunnerZoom`, a client-side node that narrows the active camera's FOV to 34°. It lives next to the sampler under `GameClient` rather than in the vehicle scripts, because those are sim code and must not read `Input` — and it stops writing `fov` entirely once back at the 75° default, so it cannot fight the ADS pass in the backlog.
- M7: **on-screen prompts are device-aware.** They were hardcoded keyboard strings ("F to exit, C to switch seat"), which is unusable advice on a pad — there is no C on an Xbox controller. `InputHints` tracks the last device that produced an event and resolves an action to a label off the `InputMap` itself, so a rebinding cannot desynchronise the hint from the binding. Stick motion under 0.5 does not count as a pad event, or drift alone would flip the hints.
- M7: `switch_seat` is A on the pad and **C** on the keyboard, not F — F is `exit_vehicle`, and binding both to one key meant switching seats also threw you out. The tank's pad brake moved A → LB to leave A free for seats, per the owner's control scheme.
- **M7: RB is now the helicopter pilot's button alone.** The rule had been "drivers fire on RB", which put the tank commander there too. The tank does not use the triggers for anything — it drives on the left stick — so there was no clash to avoid, and RT/LT is the scheme every other weapon in the game uses. `fire_action()` returns `vehicle_fire` only while `_is_piloting()`, and `can_zoom()` is every vehicle seat except that one. Both are read by the HUD as well, so a label cannot disagree with what the button does.
- **M7: the deploy screen leaked one controller into both windows — the third instance of the same bug.** `DeployMap._unhandled_input` handled `toggle_deploy_map` (Back) and `deploy_confirm` (A) with no focus check. Keyboard never showed it because the OS only delivers keys to the focused window, but joypads are read per-process, so both instances acted on one press. The stick navigation added alongside it *was* gated; the event handler was not, and the two were written minutes apart.
  There is also a second path that has nothing to do with our code: Godot's built-in `ui_accept` includes pad **A**, so any `Button` holding UI focus fires in every window at once. Every button on the deploy screen, the lobby and the main menu is now `FOCUS_NONE` — they are mouse-driven, and confirmation goes through our own gated handler.
- M7: the standing rule, now stated plainly: **any code that reads `Input` or handles an event outside `InputSampler` must call `InputFocus.may_act()` first, and any `Button` reachable while two windows are open must be `FOCUS_NONE`.** Three occurrences (M3 sampler, M7 interaction scanner, M7 deploy map) say this will keep happening otherwise.
- M7: `verify_focus_gate_ui` tests it the only way that works — a fake sampler reporting the window as unfocused, then asserting a synthesized pad press changes nothing and the same press with focus does. Earlier focus fixes were only asserted through a helper returning the right boolean, which is why this one shipped broken anyway.
