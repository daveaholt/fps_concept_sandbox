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
| `max_lift` | ~~1.35~~ **1.58 × m·g** (34000 N) | Climb 11.4 m/s at full collective; hover trims at 63% collective |
| `collective_rate` | ~~0.8 → 1.1 → 1.5~~ **1.9 /s** | 0.52 s from hover to a 3 m/s descent |
| `spool_rate` | 0.25 /s | |
| `cyclic_torque` | ~~14000~~ ~~11500~~ **9500 N·m** | Right stick: pitch & roll. 16 deg/s peak, 11.1° of tilt after 1 s |
| `pedal_torque` | ~~9000 → 7500 → 10000~~ **13000 N·m** | Left stick: yaw. 22 deg/s |
| `attitude_damping` | 3.0 | angular_damp equivalent |
| `auto_level` | 0.35 | 0 = manual, 1 = self-leveling drone |
| `tilt_limit_deg` / `_strength` | **45° / 4.0** | **New.** Restoring torque that engages only past 45°; inert in normal flight |
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

## Armament (M7)

Two weapons, one per seat, both projectiles through `BallisticsManager` per 11.

- **Pilot — rocket pods.** Fixed forward along the hull, aimed by pointing the aircraft, because the pilot has no free-look. Alternating left/right pods, `rocket_salvo` 4 at `rocket_interval` 0.35 s, then a `rocket_reload` of 3.2 s. Slow (95 m/s), gravity-affected, 5.5 m splash — it wants leading and it punishes a hover.
- **Gunner — chin minigun.** Turreted, slewed by the gunner's own aim within ±120° yaw and −35°/+20° pitch. 12 rounds/s at 780 m/s with no splash, limited by **heat** rather than ammo: `gun_heat_per_shot` 0.035, `gun_cool_rate` 0.45/s, so about 28 rounds of continuous fire before it cuts out.

Heat was chosen over an ammo count because it needs no reload UI and no resupply concept, and it self-corrects — a gunner who paces their bursts never runs dry. Ammo counts stay available if the sandbox ever grows resupply.

The tank's second seat carries the same turret with the same minigun round; the code is shared verbatim between both vehicles.

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
- M6 tuning: **two response-tuning passes were measured, flown and rejected. The shipped values are the originals.** Recorded so they are not re-tried.
  - *Pass 1* raised `pedal_torque` 9000 → 20000 (yaw 15 → 34 deg/s), `collective_rate` 0.8 → 1.8 (0.82 → 0.57 s to a 3 m/s descent) and `cyclic_torque` 14000 → 24000 (45° flight-path swing from over 5 s to 2.9 s, cruise 63 → 91 km/h). Every number improved. Verdict from the seat: pitch and yaw "way too sensitive", and the acceleration it bought was still not what was wanted.
  - *Pass 2* replaced raw cyclic torque with a bounded attitude command (±38°), which decoupled rotation rate from translation authority — peak pitch rate held at 34 deg/s while speed after 3 s rose 47 → 62 km/h with thrust. Verdict: "even worse".
  - The lesson is not about the numbers. **Every one of these was measured to be better on every axis I could measure, and all of them flew worse.** Response tuning on this vehicle is not reachable from a headless rig; it needs a pilot in the seat, and the measurements are only useful for explaining *why* something feels the way it does after the fact.
- M6: a real defect found during pass 2 and **still present in the shipped build**: `auto_level`'s restoring torque grows linearly with tilt, so it balances full cyclic at `1 / auto_level` radians — about **164°**. There is no tilt limit; holding full cyclic for 3 s settles at 110°–176° of tilt, i.e. inverted. At the shipped `cyclic_torque` of 14000 the tilt *rate* is low enough that ordinary stick inputs self-correct long before this shows up, which is why it has never been hit in play. It is a latent bug, not a theoretical one, and the fix (bounding the commanded tilt) is written and was reverted only because the feel it produced was rejected. If a tilt limit is added later, add it **without** changing the response numbers.
- M6 tuning: after the two rejected passes above, the shipped feel came from one small pass in the directions the pilot named — pitch and yaw *slightly* less responsive, throttle *slightly* more. `cyclic_torque` −18%, `pedal_torque` −17%, `collective_rate` +38%. Measured: pitch 19 deg/s peak and 13.5° of tilt after a second, yaw 13 deg/s, and 0.70 s from hover to a 3 m/s descent (was 0.82). Recorded mostly as method: three named nudges beat a measured redesign twice over on this vehicle.
- M6 tuning: `max_lift` raised 1.35 → 1.58 × m·g on the pilot's call for more thrust. Climb reaches 11.4 m/s in 3 s at full collective, hover trims at 63% collective instead of 74% (so there is real headroom either side of the hover position), and the rotor floor drops from 86% to 80% because it is `sqrt(m*g / max_lift)` and follows automatically. Note this is close to the 1.55 that pass 2 shipped and that flew badly — thrust was never the problem there, the bounded-attitude cyclic was.
- M6: two suite assertions had tuning values frozen into them and broke on this change — `max_lift` pinned to 1.35× within 400 N, and the hover floor pinned above 0.8. Both now assert the *relationship* instead: lift-to-weight within a sane band, and the floor equal to `sqrt(m*g / max_lift)`. Same trap as the tank's spring length and armour-sector probe: a test that hardcodes a number a human is expected to tune will fail the moment they tune it, and teaches nothing when it does.
- M6 tuning: second pilot-led pass, again one number per axis. Right stick calmer (`cyclic_torque` −17% → 16 deg/s peak, 11.1° of tilt after a second), left stick livelier (`pedal_torque` +33% → 17 deg/s yaw), collective quicker again (`collective_rate` +36% → 0.57 s from hover to a 3 m/s descent). Note yaw moved *down* last pass and *up* this one; the pilot's target was between the two, which is what iteration looks like and is not worth trying to shortcut with a measurement.
- M6: "responsive to changes in rotor speed" was read as the collective, not `spool_rate`. Rotor rpm only changes during spool-up and spool-down, so in flight the only thing a pilot can change is collective. `spool_rate` is still 0.25/s (~4 s), which 06 wants as a deliberate event. If the intent was actually a shorter spool, that is a one-number change and a spec deviation worth noting.
- M6 tuning: third pilot pass. Right stick declared correct at 9500 N·m and frozen; left stick and collective pushed one more step in the same direction (`pedal_torque` +30% → 22 deg/s yaw, `collective_rate` +27% → 0.52 s to a 3 m/s descent). Final numbers: pitch 16 deg/s, yaw 22 deg/s, collective 0.52 s, lift-to-weight 1.58.
- M6: **the no-tilt-limit defect is fixed, and this time without touching the feel.** It was found while building the latency rig: the automated pilot could not hold station at *any* delay, and the trace showed why — sustained full stick rolled the hull to 82°, then 100°, then 167°, and it finished inverted on the ground. So the defect is more reachable than the earlier note claimed: it needs a sustained hard input, not a freak case. The fix is a restoring torque that engages **only past 45°**, so it is arithmetically inert inside the envelope the pilot tuned. Verified: right stick 16 deg/s and 11.1° of tilt after a second, left stick 22 deg/s, collective 0.52 s — all **identical** to the values before the limit — while held full cyclic now peaks at 60° instead of 110°–176°. `verify_m6` asserts both the limit's existence and that 10 s of full cyclic never passes vertical.
- M6: this is the correct version of the change that was reverted for feel. The earlier attempt bundled a tilt bound *with* a redesigned cyclic model and new response numbers, so when it flew badly there was no way to tell which part was at fault. Separating them showed it was never the bound.
- **M6 gate — flown verdict: 100 ms interpolated helicopter control is usable.** The pilot's words: "feels ok … a useable first attempt", with the caveat that this is the kind of thing that could absorb weeks of tweaking. Taken with the stability measurement in 10 (RMS station-keeping degrades 9.1 → 11.0 m from 0 to 200 ms, no divergence), the flagged experiment closes: **the server-simulated, interpolated-for-everyone model stands, and the client-authoritative-attitude fallback is not required.** Recorded as a first-pass verdict, not a final one — the numbers in the tunables table above are a starting point somebody will want to revisit.
- M6 closed with the feel arrived at by pilot iteration, not by measurement: pitch 16 deg/s, yaw 22 deg/s, collective 0.52 s to a 3 m/s descent, lift-to-weight 1.58. The three passes that were measured-better and flown-worse are recorded above so the same ground is not covered twice.
- M7: the pilot has a reticle. It was explicitly suppressed (`_crosshair.modulate.a = 0.0`) on the theory that a helicopter cockpit does not want one, which left the only aiming aid a centre-screen text prompt that also blocked the view. The reticle is projected from `weapon_ray(0)` and dimmed to 40% while the rotor is below hover RPM, so it doubles as a "cannot fire usefully yet" cue.
- M7: the persistent "F to exit, C to switch seat" prompt is gone from screen centre. Vehicle controls now render as one line in the bottom HUD panel with device-correct labels; the centre prompt is reserved for the transient "Enter <vehicle>" hint, which is the only one that needs to be where the eye already is.
