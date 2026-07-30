# 05 — Tank

`entities/tank/tank.tscn` — root `VehicleBody3D`, groups `controllable`, `vehicle`, `tank`.

## Approach: wheels pretending to be treads

Godot's `VehicleBody3D` raycast-wheel model is used with **six `VehicleWheel3D`s** (three per side), all traction, none steering. Steering is **differential**: per-wheel `engine_force` differs left vs. right. `VehicleWheel3D` exposes `engine_force`, `brake`, and `steering` per wheel, so no custom raycast suspension is needed — this is the sim-leaning choice that stays tunable.

Wheels are invisible (no mesh); the hull mesh shows simple tread boxes. Visual tread scrolling is a shader/UV trick deferred to polish.

## Drive model

Inputs each physics tick (possessed only): `throttle ∈ [-1,1]` (W/S), `steer ∈ [-1,1]` (A/D), `brake` (Space).

```
left_force  = (throttle + steer * steer_authority) * max_engine_force
right_force = (throttle - steer * steer_authority) * max_engine_force
```

- Applied to each side's wheels (split across the 3 wheels).
- **Neutral steer** (throttle = 0, steer ≠ 0): forces become `±steer * pivot_force` → turn in place, the thing that makes it feel like a tank.
- Speed-sensitive steer: `steer_authority` lerps down with speed to prevent high-speed spin-outs.
- `brake` input sets wheel `brake` on all wheels; idle (no throttle) applies a small `idle_brake` so it doesn't roll off hills.
- Engine force fades to 0 as speed approaches `max_speed` (crude governor).

### Tunables

| Export | Default | Notes |
|---|---|---|
| `max_engine_force` | ~~6000~~ **14000 N** | Total per side at full throttle. 6000 could not climb the doc's own 20° criterion — see tuning note below |
| `pivot_force` | ~~4000~~ **10000 N** | Neutral-steer force per side |
| `max_yaw_rate` / `yaw_accel` | ~~1.0 · 3.0~~ **1.35 rad/s · 25 rad/s²** | Target yaw rate, and the acceleration cap on the torque used to reach it — see below |
| `yaw_inertia` | **16667 kg·m²** | **New.** Hull I(yy); converts the wanted angular acceleration into a torque |
| `steer_authority` | 0.6 → ~~0.25~~ **0.45** | Lerped from 0 to `max_speed`. The high end must stay under the low end or turns tighten with speed |
| `max_speed` | 14 m/s | ~50 km/h |
| `brake_force` / `idle_brake` | ~~60 / 8~~ ~~200 / 90~~ **900 / 350** | Godot brake units per wheel; raised again once the hull stopped dragging — see suspension note |
| `wheel_suspension_stiffness` | 40.0 | Firm; it's a tank |
| `suspension_damping_compression` / `_relaxation` | ~~0.6 / 0.8~~ **3.0 / 4.0** | Godot's defaults are tuned for its default stiffness of 5.88, not for 40 — see note |
| `wheel_suspension_travel` | 0.3 m | |
| `suspension_rest_length` | **0.55 m** | **New.** Sets ride height; 0.59 m of hull clearance puts the belly above low obstacles |
| `suspension_max_force_n` | **20000 N** | **New.** Per wheel. Godot's 6000 default cannot hold this tank up — see note below |
| `wheel_friction_slip` | ~~3.0~~ **2.0** | Lowered to cut lateral scrub in turns; recovers turn rate *and* speed together |
| `mass` | 4000 kg | Keep ratio to engine force sane |
| `center_of_mass` | ~~(0, −0.4, 0)~~ **(0, 0, 0)** | −0.4 sat 0.19 m above the contact patch and pitched the nose down in every turn; 0 still gives a ~70° tip angle |

Known risk: raycast vehicles get twitchy when heavy. If 4000 kg misbehaves, scale mass *and* forces down together (feel depends on their ratio) — note kept here so tuning doesn't chase ghosts.

## Turret & cannon

```
Tank
├── TurretYaw (Node3D)          # yaw only, follows chase-cam yaw at turret_speed
│   └── CannonPitch (Node3D)    # pitch clamp −8°…+20°
│       └── Muzzle (Marker3D)
```

Turret *chases* the camera aim direction at finite `turret_speed` (60°/s yaw, 30°/s pitch) rather than snapping — this is most of what makes a tank feel heavy. Crosshair shows both camera aim point and a second dim marker for where the barrel currently points; they converge when the turret catches up.

**Firing:** LMB fires a shell through the shared `BallisticsManager` (11) from `Muzzle` — 180 m/s, gravity + drag, big tracer streak, 80 direct damage + 4 m splash (server overlap query at impact). No RigidBody shell exists. `fire_cooldown = 2.5 s` with HUD reload pip. Applies a small impulse kick to the hull opposite the shot because it's free and feels great.

## Armor sectors

Per 11's directional-sector spec, incoming damage is multiplied by impact location in hull-local space: **front ×1.0 · side ×1.25 · rear ×2.0 · top ×1.5** (all exported). Sector boundaries: ±45° cones fore/aft for front/rear, the rest is side; hits above deck height count as top. Tank health is still a logged stub (01), so in v1 the multiplier is visible only in the hit log — but the rear-armor gameplay is fully specced for the day vehicle damage matters. The turret counts as top/side by the same local-space rule; no separate turret pool.

## Networked feel (10)

Hull physics is server-simulated and interpolated even for the driver (~RTT + buffer of control latency — acceptable for a 4-tonne vehicle, and part of what's being evaluated). **Turret/cannon aim is client-predicted** (kinematic, trivially replayable), so aiming stays crisp; the server clamps and re-simulates turret angles authoritatively. Tread audio/animation respond to input instantly as pure cosmetics. Shells are server-simulated ballistics (11) — slow enough that leading targets is the intended skill; the decaying compensation window barely applies at shell speeds.

## Camera

Two views, toggled with `toggle_camera` (V / R3), defaulting to chase.

**Gun sight (first person, M7).** A `DriverEye` marker on `TurretYaw/CannonPitch`, so the camera inherits turret traverse *and* gun elevation and looks straight down the barrel axis. This is the view that makes the 60°/s traverse legible — in chase the camera turns instantly and the turret trails it, whereas here the view itself moves at turret speed and the reticle stays centred. The eye sits inside the turret volume, so the hull culls away by the ordinary shell rule (09) and the only part of the tank left in frame is the cannon barrel below the sight line. Gun elevation limits (−8°…+20°) become the view's pitch limits, which is why it is a sight rather than a general-purpose driving view.

ChaseCam (see 04): spring length 8 m, pivot ~~2.5 m~~ **2.1 m** above hull, pitch clamp ~~−10°…+60°~~ **−8°…+20°** (the gun's own range). The arm only swings *up* — looking up pitches the camera in place rather than dropping it behind the hull. Mouse orbits freely; hull orientation does not drag the camera (turret-follows-camera scheme requires a free camera). The clamp is now tied to the gun rather than chosen for the camera — see the tuning note.

## HUD (possessed)

Speed (km/h), turret-vs-hull compass ghost, reload pip, predicted-impact marker (client steps 11's ballistics function ahead against terrain — cosmetic), "F — exit" hint.

## Acceptance criteria (M3)

- Climbs the 20° test ramp from standstill; does not flip on the 25° cross-slope.
- Neutral-steers in place; at full speed A/D produces a wide controlled arc, not a spin.
- Turret tracks camera smoothly; shells follow a visible arc and land on the predicted-impact marker (±1 m on flat ground).
- Stationary on a 15° slope with no input (idle brake holds).

## Tuning notes (M5)

Two numbers in the table above could not meet this doc's own acceptance criteria and were raised, measured rather than guessed:

- **`max_engine_force` 6000 → 14000 N.** A 4000 kg hull on a 20° grade needs `m·g·sin20° ≈ 13.4 kN` merely to hold station. Two sides at 6000 N gave 12 kN — short before any acceleration — so the tank slid *down* the test ramp. At 14000 it climbs +5.9 m from a standstill.
- **`idle_brake` 8 → 90** (and `brake_force` 60 → 200). At 8 the tank slid 7 m in 2 s on the ramp; at 90 it holds to 0.18 m.

**Steering is a rate, not a force — a deviation from the model above.** This doc specifies that turning emerges from differential `engine_force` with no steering wheels, and that neutral steer comes from opposing per-side forces. In Godot's `VehicleBody3D` that does not work: its raycast wheels rigidly resist yaw. Measured with all six wheels in ground contact and ±10 kN opposed per side, the hull reached **0.032 rad/s and stopped accelerating** — a stationary pivot never develops. `wheel_friction_slip` is not the lever: sweeping it from 3.0 to 0.15, a 20× change, moved grounded yaw by nothing at all (0.014 rad/s at every value). `apply_torque` is not the lever either: the same torque spins the hull to 1.46 rad/s while airborne, so the wheels are absorbing it, not the body refusing it.

What does work is driving `angular_velocity.y` toward a target rate: 0.887 rad/s held against a 0.9 target with zero translation. So the tank keeps the differential `engine_force` model for *drive* — it is what climbs, accelerates and governs — and yaw is driven kinematically at `max_yaw_rate`, scaled by the existing speed-sensitive `steer_authority` so full-speed turns stay wide arcs (0.25 rad/s at top speed) and stationary pivots are brisk (1.0 rad/s). The *feel* this doc asks for is preserved; the mechanism underneath is not the one it describes, because that mechanism does not exist in this engine.
- Post-M5: positive `engine_force` on a `VehicleWheel3D` drives the hull along its local **+Z**, which is backwards — Godot's forward is −Z. Throttle is negated when computing per-side force, so W drives the tank the way its barrel points. This is easy to miss because a free-orbit chase camera makes "forward" ambiguous by eye, and because a ramp test placed at 180° cancels the error exactly. There is now an explicit assertion that velocity agrees with the hull's forward axis.
- Post-M5: steering inverts with travel direction, because that is what a tracked vehicle does. A tank turns by making the **inside track slower**, and "slower" means smaller magnitude *in the direction of travel* — so slowing the left track swings the nose left going forward and right going backwards, exactly as a car does in reverse. The yaw target is multiplied by the sign of travel (velocity along the hull's forward axis, falling back to throttle sign below 0.5 m/s). Stationary pivots are exempt: with no travel direction, A always pivots left. Covered by `verify_steering`, which asserts the nose direction for all six input combinations rather than just that some rotation occurred.
- Post-M5: `deck_height` raised 1.1 → 1.5 m. It marks where the side sector becomes the top sector in hull-local space, and at 1.1 it sat at the hull's *midline* rather than its roof (the hull spans local y 0.2–1.6). The consequence showed up in a live session: 103 rifle hits logged front, rear and top, and **not one side hit** — an infantryman firing from 1.6 m eye height strikes the flank around y 1.0–1.5, all of which counted as top. At 1.5 the whole flank up to the roof reads side and only turret/roof hits read top.

- Post-M5: **the tank had been resting on its hull, not its wheels, since M5.** `VehicleWheel3D.suspension_max_force` defaults to **6000 N**; six wheels give 36 kN against a 39.2 kN tank, so the springs could never carry it and it settled with the hull collision box on the ground (hull origin y −0.21, belly at −0.01). That hid itself well — it drove, steered and climbed, because the belly was supplying grip the wheels were not. It only surfaced as "the tank stops dead at the 0.6 m airfield slab": the belly at world 0.30 and the wheel ray origins at 0.45 were *both* below the slab face, so nothing could see the top surface to climb it. Raising `suspension_max_force` to 20000 N and `wheel_rest_length` to 0.55 m lifts it onto its springs at a 0.59 m ride height — the belly now clears at 0.79 m and the wheel rays at 0.94 m, and it drives onto the slab and settles flat. Two knock-ons, both from losing the belly friction that was quietly helping: braking had to come up (`idle_brake` 90 → 350, `brake_force` 200 → 900, or coasting would have braked harder than the brake pedal), and the M5 ramp checks had to stop *dropping* the tank 6.4 m onto the slope — real suspension turns that into a bounce that swamps the measurement, so they now place it on the grade. Placed properly it climbs the 20° ramp +5.9 m in 5 s and idle-holds to 0.17 m.
- Post-M5: `wheel_friction_slip` is again not the lever it looks like — sweeping 3 → 12 moved ramp climb by 0.03 m and idle slide by 0.07 m. Worth recording twice: on this vehicle, grip problems have never once been grip.
- Post-M5: putting the tank on its springs exposed two settings that had never mattered while it dragged its belly. **Damping**: `damping_compression` / `damping_relaxation` were still Godot's defaults of 0.6 / 0.8, which are tuned for Godot's default `suspension_stiffness` of 5.88 — at 40 that is a damping ratio around 0.12, and the tank pogoed. Straight-line driving hid it completely (0.03° of pitch, zero heave); steering excited it. At 3.0 / 4.0 the pitch swing in a turn drops 15.5° → 5.0° and heave 0.44 m → 0.09 m, and more damping than that buys nothing (pitch is flat from 2.5 upward and heave slowly gets *worse*). Raising stiffness instead is a bad trade: at 100 the roll improves 9.1° → 6.8° but pitch doubles and heave triples.
- Post-M5: **`center_of_mass` (0, −0.4, 0) was the "leans forward" complaint.** At the new ride height that put the COM 0.19 m above the contact patch — a weeble — and every turn pitched the nose down about 9.5°. It is the COM, not the forced yaw rate: sweeping `max_yaw_rate` 0.70 → 2.00 moved mean turn pitch by less than a degree (−8.05 → −8.99), while sweeping the COM −0.4 → 0.0 → +0.4 moved it −9.51 → −1.51 → +9.69. At 0 the tank also rolls *less* (2.20° vs 2.96°), and the tip angle is still about 70°, far outside the 25° slopes this doc worries about. The original "lowered so it can't flip" reasoning was sound but overshot.
- Post-M5: `levels/sandbox/sandbox.tscn` was re-declaring the tank instance's `mass`, `center_of_mass_mode`, `center_of_mass` and `collision_layer`, shadowing `tank.tscn`. Editing the tank scene appeared to do nothing — the first COM fix produced byte-identical telemetry, which is what gave it away. The level now overrides only the placement transform. Worth checking the same trap for the heli at M6: physics identity belongs to the entity scene, placement belongs to the level.
- Post-M5: yaw is now applied about the **hull's own up axis** rather than world Y (`angular_velocity += up * (blended - spin)`). Mathematically identical while level, correct once pitched or rolled. Recorded honestly: this was a wrong guess at the bouncing and made no measurable difference to it — it is kept because world-Y yaw is simply wrong on a slope, not because it fixed the symptom.
- Post-M5: **yaw is now a torque, not a written `angular_velocity`.** Setting `angular_velocity` directly each tick bypasses the constraint solver: the six wheels' accumulated impulses end up inconsistent with the body state, the springs wind up and release, and the tank bucks. While it dragged its belly this was invisible, because the hull on the ground absorbed it. On springs it was violent — a full-lock reversal (back-left straight to forward-right) peaked at **21.9° pitch, 35.2° roll and 0.84 m of heave**, which is close to standing on its nose. Yaw is now `apply_torque(up * accel * yaw_inertia)` with `accel` the rate error clamped to `yaw_accel`, so the solver mediates it. The same reversal now peaks at **0.8° pitch, 0.4° roll, 0.02 m heave**, and a stationary pivot drifts **0.00 m/s** where the kinematic version slid 6.8.
- Post-M5: **this partly overturns the "steering is a rate, not a force" finding above, and the reason is worth keeping.** That measurement — `apply_torque` reaching 1.46 rad/s airborne but "absorbed" grounded — was taken while the tank was resting on its hull, so what absorbed the torque was the belly on the ground, not the wheels. On springs, torque reaches **1.18 rad/s** against a 1.35 target with full authority (it saturates above `yaw_accel` 25; 6 was far too little at 0.11 rad/s). The doc's *drive* model is still right and its *neutral-steer-from-opposing-forces* model is still wrong — differential `engine_force` still yaws the hull at 0.00 rad/s — but the conclusion "no torque can do it either" was an artifact of the suspension bug. **A performance measurement taken on a broken configuration only describes the breakage.**
- Post-M5: `verify_flip` covers all four full-lock reversals. It samples attitude *only while the tank is over flat ground*, checked by raycast — the first version failed one case out of four and the cause was the tank reaching the airfield slab mid-manoeuvre, not the reversal. Three of four combinations passing is exactly the shape of near-miss that has repeatedly let a real bug through here, so the fourth case earns its keep.
- Post-M5: **the camera could look 40° higher than the gun could shoot.** The cannon elevates to +20°; the camera clamp was +60°. Past +20° the reticle kept rising and the barrel physically could not follow, so it read further and further "pointed down" — and with an 8 m arm, +60° swung the camera 6.9 m below its pivot, i.e. underground behind the tank, which is the "I drop below/behind the tank" symptom. Compounding it, the pivot at 2.5 m sat 0.9 m above the turret axis, so parallax put the barrel below the reticle at close range. The camera clamp is now derived from the gun (−8°…+15°, inside the gun's −8°…+20°), the pivot dropped to 2.1 m (0.5 m of parallax) and the arm to 7 m so a full look-up leaves the camera 0.87 m above ground instead of below it. `verify_gunline` asserts all four relationships, because every one of them is a silent geometry constraint that nothing else would catch.
- Post-M5: turn authority at speed. The torque-driven yaw made turns noticeably stiffer — a held turn reached 0.27 rad/s where the old forced version delivered its 0.52 target. More torque does not fix it (`yaw_accel` 25 → 250 moved it 0.22 → 0.21): the *rate target* is the limit, not the torque. `steer_authority_high` 0.25 → 0.45 and `wheel_friction_slip` 3.0 → 2.0 bring it to ~0.36 rad/s, and both mean speed **and** turn rate improve together, because less lateral scrub means less speed bled in the turn. `steer_authority_high` must stay below `steer_authority_low` (0.6) or the tank turns harder at speed than at rest, inverting the wide-arc design this doc asks for — 0.65 measured 0.45 rad/s and was rejected for that reason, not for the number.
- Post-M5: **the barrel fix above was wrong, and the measurement that would have caught it is now the test.** Matching the camera clamp to the gun and lowering the pivot was necessary but not sufficient: the arm's rotation set the camera's *position as well as its orientation*, so looking up swung the camera down behind the tank and **the hull itself occluded the target**. Measured as the height of the sight line where it crosses the hull's rear face (roof about 2.69 m at the new ride height): original +60° clamp, blocked by 4.97 m; original at +20°, blocked by 0.73 m; the "fixed" 2.1 m pivot / 7 m arm / +15° clamp, **blocked by 0.83 m — slightly worse than what it replaced**. The arm now only swings up (`arm_pitch = min(pitch, 0)`) and the camera takes the remaining elevation as its own local rotation, so looking up rotates the view in place instead of dropping it: clears by 1.78 m. The lesson is the same one as the suspension: *tuning numbers on either side of the real constraint will look like progress and change nothing.* `verify_gunline` now asserts the sight-line clearance itself rather than the inputs to it.
- Post-M5: the hull was shrunk about 12% on request — **2.74 m tall → 2.41 m**, taking the height out *above* the belly, because the 0.79 m ground clearance is what clears the 0.6 m airfield slab and could not move. Hull collision 1.4 → 1.15 m (bottom pinned at local 0.2), hull visual 1.2 → 1.0 m, turret mount 1.6 → 1.35 m, turret box 0.9 → 0.75 m. Everything measured off the hull followed: `deck_height` 1.5 → 1.25, `hit_centre_y` and the hit box half-height 0.9 → 0.775, `camera_pivot_height` 2.1 → 1.85 to hold the 0.5 m gun-line parallax.
- Post-M5: two suites had assertions pinned to old geometry rather than derived from it — the chase-arm length, and the armour-sector probe that sampled a hardcoded 1.45 m "just under the hull roof" and started reading *top* once the roof came down. Both now derive from the scene (`verify_gunline` computes the roof from the mesh AABBs; `verify_m5` samples relative to `deck_height` and separately asserts the deck line sits just under the hull roof). A hardcoded expectation in a test is a landmine that goes off the next time the thing it describes legitimately changes.
- **M7: the first-person view hangs off `CannonPitch`, not the hull.** A hull-mounted driver's view would not follow the aim at all — the same seat operates the cannon, so the useful first-person station is the gun sight. Mounting the camera on the gun means the view inherits turret traverse and elevation for free, needs no orientation code, and puts the reticle dead centre because the camera's forward axis *is* the barrel axis (`verify_gunner_view` asserts dot > 0.999). It also means the sight inherits the gun's −8°…+20° elevation limits, which is why the chase view stays the default and the toggle exists.
- M7: the sight is deliberately the heavy view. In chase the camera turns instantly and the turret trails it; here the view itself moves at the turret's 60°/s. That is the same divergence this doc already describes between reticle and barrel, just moved into the camera where it can be felt rather than watched.
- M7: the gun sight carries a **hull indicator** — two track lines with a nose chevron, drawn around the reticle and rotated by the turret's yaw relative to the hull. Culling the hull for the first-person view took away the only cue for which way the tank was pointing, so steering blind was the immediate complaint. The chevron matters as much as the tracks: two parallel lines are symmetric under 180°, so without it forward and reverse look identical.
- M7: the indicator's rotation is `turret_angles().x` with no sign flip, because the camera rides the turret — the hull's forward direction in camera space is `(sin ty, 0, −cos ty)`, which projects to exactly Godot's 2D rotation of "up" by `ty`. `verify_gunner_view` checks the glyph's forward vector against the hull's real direction transformed into the camera basis, at five turret angles including past 90° and near 180°, rather than trusting that derivation.
