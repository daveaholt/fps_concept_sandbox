# 06 — Helicopter

`entities/helicopter/helicopter.tscn` — root `RigidBody3D`, groups `controllable`, `vehicle`, `helicopter`.

## Approach: forces, not fakery

The heli is a real rigid body flown by continuously applied forces/torques — sim-leaning but with three deliberate simplifications: no translational lift/vortex-ring aerodynamics, no torque-reaction yaw (pedals are direct authority), and lift always points along the rotor's local up. What remains is still an honest control problem (attitude ↔ acceleration coupling), which is the concept being tested.

## State: engine & spool

**Revised at M6: there is no engine button.** Entering the heli starts the rotor; exiting stops it. `rotor_rpm_norm ∈ [0,1]` moves toward target at `spool_rate` (~0.25/s → ~4 s spool-up). All rotor forces scale by `rotor_rpm_norm²` — below **86%** the heli cannot hover, which makes spool-up a real event. (This doc said ~70%; that was arithmetic, not measurement. Hover needs `m*g`, available lift is `max_lift * rpm²`, so the floor is `sqrt(m*g / max_lift) = sqrt(1/1.35) = 0.861`. The code derives it rather than storing the number.) Rotor visual spins accordingly. Spool-up still gates flight, so getting in and immediately pulling collective does nothing for about four seconds — the *event* the original spec wanted is preserved; only the button is gone.

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
| `collective_rate` | ~~0.8~~ **1.8 /s** | Tuned at M6; 0.8 took 0.82 s to reach a 3 m/s descent, 1.8 takes 0.57 s |
| `spool_rate` | 0.25 /s | |
| `cyclic_torque` | ~~14000~~ **24000 N·m** | Pitch & roll. Tuned at M6 — raises cruise *and* turn response together |
| `pedal_torque` | ~~9000~~ **20000 N·m** | 9000 gave only 15 deg/s; a 90° turn took six seconds |
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
- M6: **auto-starting the engine in `possess()` only worked on the listen-server host.** `possess()` is a client-side presentation call — camera, input binding — and the server never calls it: `GameServer._bind` sets `owner_peer` and RPCs `grant_possession` to the owning peer, which possesses its *own local copy*. So a remote pilot set `engine_on` on a node that does not run physics, while the authoritative heli sat with its rotor stopped. Engine state is now driven from `owner_peer` inside the server's `_physics_process`, where every other piece of vehicle state already lives. `verify_heli_engine` binds a peer **without ever calling `possess()`** and asserts the heli spools and lifts, which is the only shape of test that could have caught this.
- M6: this is the second instance of the 04 note about client code assuming infantry, from the other direction — here it was *entity* code assuming the client. The rule that falls out: **anything that changes simulated state belongs on the server tick keyed off replicated state, never in a possess/unpossess hook.** Worth applying to heli weapons and passenger seats in M7.
- M6: the HUD now shows rotor and collective percentages at all times rather than hiding them behind `can_hover()`. They were hidden exactly when they were most needed — while nothing was happening and the pilot wanted to know why.
- M6: cyclic pitch is inverted in the flight-stick sense — **push forward for nose down**. It shipped backwards, and the reason no test caught it is worth recording: `verify_m6` pushes `move.y` straight into the entity, so it validated the *force model* while never touching the input map. Direction bugs live in the mapping, not the physics. `verify_heli_controls` now asserts what each physical control commands ("stick forward -> nose DOWN", "left stick right -> yaw RIGHT") rather than only which axis it is bound to.
- M6 tuning: the sluggishness had two separate causes and the second one was not where it appeared to be. Yaw was genuinely weak — `pedal_torque` 9000 produced **15 deg/s**, so a 90° turn took six seconds; at 20000 it is 34 deg/s, reached in 0.18 s. Collective was rate-limited: 0.8/s meant **0.82 s** just to wind the lever down to a 3 m/s descent, now 0.57 s at 1.8/s.
- M6 tuning: but "turns feel slow at speed" was mostly the **flight path lagging the nose**, not the yaw rate — with the nose swinging 116° in the first second, the velocity vector had moved 1°. The obvious lever, `linear_damp`, is a bad trade: it buys turn response by bleeding momentum, and going 0.15 → 1.2 cut the 45° path swing from over 5 s to 3.7 s while halving cruise from 63 to 30 km/h. `cyclic_torque` is the right lever because it lets the pilot point more of the 29 kN where they are going: at 24000 the path swings 45° in **2.9 s** and cruise *rises* to **91 km/h**. Both numbers improve together, which is the tell that it was the correct knob.
- M6 tuning: `auto_level` needs no re-tune after the cyclic change — its torque is expressed as a fraction of `cyclic_torque`, so the assist scales with the authority it opposes. That was luck rather than design, and is worth keeping if either number moves again.
