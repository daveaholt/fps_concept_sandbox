# 06 — Helicopter

`entities/helicopter/helicopter.tscn` — root `RigidBody3D`, groups `controllable`, `vehicle`, `helicopter`.

## Approach: forces, not fakery

The heli is a real rigid body flown by continuously applied forces/torques — sim-leaning but with three deliberate simplifications: no translational lift/vortex-ring aerodynamics, no torque-reaction yaw (pedals are direct authority), and lift always points along the rotor's local up. What remains is still an honest control problem (attitude ↔ acceleration coupling), which is the concept being tested.

## State: engine & spool

**Revised at M6: there is no engine button.** Entering the heli starts the rotor; exiting stops it. `rotor_rpm_norm ∈ [0,1]` moves toward target at `spool_rate` (~0.25/s → ~4 s spool-up). All rotor forces scale by `rotor_rpm_norm²` — below ~70% the heli cannot hover, which makes spool-up a real event. Rotor visual spins accordingly. Spool-up still gates flight, so getting in and immediately pulling collective does nothing for about four seconds — the *event* the original spec wanted is preserved; only the button is gone.

## Force model (per physics tick, applied in `_integrate_forces` or via `apply_*` in `_physics_process`)

**Lift:** `F = up_local * collective * max_lift * rpm²` where `collective ∈ [0,1]` from Space/Ctrl (rate-moved, not instant — `collective_rate = 0.8/s`). `max_lift ≈ 1.35 × m·g` so full collective at full RPM climbs briskly but not violently.

**Cyclic:** the **right stick** (W/S/A/D on keyboard) applies local pitch/roll torques, `cyclic_torque`. Attitude is the *only* way to translate — tilt to move, exactly the coupling we want to feel.

**Pedals:** the **left stick** X (Q/E on keyboard) applies local yaw torque `pedal_torque`.

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

CockpitCam default (nose seat marker); `toggle_camera` (V / R3) to ChaseCam (spring 10 m, higher damping than tank's so it lags — reads speed well). Both defined by the 04 rig shapes. **Revised at M6: no free-look.** The right stick is the cyclic now, so there is no spare axis to steer a view with; both cameras are slaved to the hull and you look around by yawing. If free-look is wanted later it needs a stick back, or a hold-to-look modifier.

## HUD (possessed)

Rotor RPM %, collective %, altitude (ray-derived AGL), speed, climb rate, "Land first" blip, "F — exit" hint. Artificial horizon deferred — auto_level makes it non-essential in v1.

## Acceptance criteria (M4)

- Spool, lift to stable hover, translate to the Hilltop, land on the pad, exit — the full loop — doable by a first-time pilot within ~3 attempts at default assists.
- `auto_level = 0` flight is possible for an expert (i.e., assists are assists, not physics band-aids).
- Landing at < 4 m/s descent on skids: no bounce-flip.
- Mid-air F correctly refuses; landed F exits beside the skid.

## Open questions

- M6: the 04 framework and the M5 replication path were reused **untouched**. `VehicleCommon` dropped in unchanged, `GameServer.register_vehicle` picked the heli up from the level's `Vehicles` node with no new code, and snapshots carry it through the existing vehicle path. Two keys ride along that `SnapshotBuffer._blend` does not know how to interpolate (`rr` rotor rpm, `co` collective); the blend copies unknown keys from the newer snapshot, so they step at 20 Hz instead of interpolating. For a spool gauge and a rotor-spin visual that is invisible, so the blend was deliberately left alone rather than extended.
- M6: `max_lift` is exported as a number (29100 N) rather than derived from `1.35 x m*g`, matching the tunables table above. If `mass` is ever changed, `max_lift` must be changed with it or the hover trim moves; `verify_m6` asserts the 1.35 ratio so that cannot drift silently.
- M6: **AGL had to be probed from above the hull, not from the origin.** The first version cast down from `global_position`, which sits at skid level. Landed on the 0.6 m airfield pad, the ray started *below* the pad's top face, missed it, and reported height above the terrain underneath (0.59 m instead of 0). Harmless there, but on the Hilltop plateau it would have read ~6 m and **refused the exit that 06's full-loop acceptance criterion depends on**. The probe now starts `ground_probe_lift` (1.5 m) above the origin. This is the same shape of bug as the infantry floor probe in 03, and the same fix: never cast a ground probe from a point that can be inside or below the ground.
- M6: `toggle_camera` is handled by the client input layer calling `toggle_camera()` on the possessed entity, not by an `Input` read inside the entity (01/03 forbid those in `entities/`) and not by a bit in `InputCommand` (camera choice is client-local and never needs to reach the server).
- M6: the networked flight verdict is still outstanding — the flagged 100 ms experiment has not been run yet, so nothing is claimed about it either way.
- M6: **the control scheme was changed by the repo owner after first flight, and 02 was changed with it.** The original spec put cyclic on the left stick, pedals on LB/RB, collective on the triggers and an engine toggle on Y/R. The revision moves cyclic to the right stick, yaw to the left stick, keeps collective on the triggers, and deletes the engine button entirely — freeing RB (fire), LB (zoom/secondary), A (switch seats) and Y (weapon toggle) for the M7 features that need them. The force model underneath did not change at all: `move` is still the cyclic and `axes` is still `(yaw, collective)`, so only the input layer moved.
- M6: the four heli channels are separate `heli_*` actions rather than rebindings of `move_*`/`look_*`. Rebinding the shared actions would have moved infantry and the tank onto the right stick too. The sampler switches to them only while the possessed entity is in the `helicopter` group. `verify_heli_controls` asserts each one against its intended pad axis, that each has a keyboard equivalent, and that every event is `device -1` — the last one because a device-specific binding is exactly how the F11 fullscreen bug got in at M1.
- M6: dropping the engine button also removed the one place `InputCommand.ENGINE` was consumed. The bit is left defined but unused.
