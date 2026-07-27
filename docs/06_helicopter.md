# 06 — Helicopter

`entities/helicopter/helicopter.tscn` — root `RigidBody3D`, groups `controllable`, `vehicle`, `helicopter`.

## Approach: forces, not fakery

The heli is a real rigid body flown by continuously applied forces/torques — sim-leaning but with three deliberate simplifications: no translational lift/vortex-ring aerodynamics, no torque-reaction yaw (pedals are direct authority), and lift always points along the rotor's local up. What remains is still an honest control problem (attitude ↔ acceleration coupling), which is the concept being tested.

## State: engine & spool

`toggle_engine` (R) starts/stops the rotor. `rotor_rpm_norm ∈ [0,1]` moves toward target at `spool_rate` (~0.25/s → ~4 s spool-up). All rotor forces scale by `rotor_rpm_norm²` — below ~70% the heli cannot hover, which makes spool-up a real event. Rotor visual spins accordingly. Entering the heli does not auto-start the engine; exiting begins spool-down.

## Force model (per physics tick, applied in `_integrate_forces` or via `apply_*` in `_physics_process`)

**Lift:** `F = up_local * collective * max_lift * rpm²` where `collective ∈ [0,1]` from Space/Ctrl (rate-moved, not instant — `collective_rate = 0.8/s`). `max_lift ≈ 1.35 × m·g` so full collective at full RPM climbs briskly but not violently.

**Cyclic:** W/S/A/D apply local pitch/roll torques, `cyclic_torque`. Attitude is the *only* way to translate — tilt to move, exactly the coupling we want to feel.

**Pedals:** Q/E apply local yaw torque `pedal_torque`.

**Stability assist (the tunable heart of the spec):** raw torque control is unflyable for most humans. Two exported assists, both defaulting on:

- `attitude_damping` — angular velocity damping beyond Godot's default, so releasing cyclic stops rotation.
- `auto_level ∈ [0,1]` — torque nudging the rotor disc toward world-up when cyclic is centered. At 0.35 default the heli slowly rights itself; at 0 it's a full manual heli. This one knob spans arcade↔sim, which is the point of the sandbox.

Plus `linear_drag` (quadratic-ish via `linear_damp`) so top speed self-limits.

### Tunables

| Export | Default | Notes |
|---|---|---|
| `mass` | 2200 kg | |
| `max_lift` | 1.35 × m·g | ≈ 29 kN |
| `collective_rate` | 0.8 /s | |
| `spool_rate` | 0.25 /s | |
| `cyclic_torque` | 14000 N·m | Pitch & roll |
| `pedal_torque` | 9000 N·m | |
| `attitude_damping` | 3.0 | angular_damp equivalent |
| `auto_level` | 0.35 | 0 = manual, 1 = self-leveling drone |
| `linear_damp` | 0.15 | |

Tuning procedure (do in this order, it converges fast): hover trim (max_lift), then yaw feel, then cyclic authority, then auto_level last.

## Networked feel (10)

Server-simulated, interpolated for everyone including the pilot — the riskiest latency case in the project, flagged as such in 10's open questions. Mitigations: rotor visuals/audio and collective indicator respond to input instantly (cosmetic), assists (`auto_level`, `attitude_damping`) do the moment-to-moment stabilization server-side so the pilot issues *intentions* more than corrections. If 100 ms control latency still proves unflyable, 10 names the fallback experiment (client-authoritative attitude with server clamps). Treat that outcome as a finding, not a failure.

## Ground handling & exit

Skids are two long box collision shapes with decent friction. `can_exit()` (see 04): `linear_velocity.length() < 2.0` **and** altitude-above-ground < 3 m (downward ray). Otherwise F shows a HUD refusal blip ("Land first"). Rationale: mid-air exit with no-momentum infantry spawning (04) at 80 m up is a guaranteed death loop; cheaper to forbid than to handle.

## Cameras

CockpitCam default (nose seat marker, free-look cone ±120° yaw / ±60° pitch); `toggle_camera` (V) to ChaseCam (spring 10 m, higher damping than tank's so it lags — reads speed well). Both defined by the 04 rig shapes.

## HUD (possessed)

Rotor RPM %, collective %, altitude (ray-derived AGL), speed, climb rate, "Land first" blip, "F — exit" hint. Artificial horizon deferred — auto_level makes it non-essential in v1.

## Acceptance criteria (M4)

- Spool, lift to stable hover, translate to the Hilltop, land on the pad, exit — the full loop — doable by a first-time pilot within ~3 attempts at default assists.
- `auto_level = 0` flight is possible for an expert (i.e., assists are assists, not physics band-aids).
- Landing at < 4 m/s descent on skids: no bounce-flip.
- Mid-air F correctly refuses; landed F exits beside the skid.
