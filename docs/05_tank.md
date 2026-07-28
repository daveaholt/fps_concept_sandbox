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
| `max_yaw_rate` / `yaw_accel` | 1.0 rad/s · 3.0 rad/s² | **New.** Yaw is driven as a rate, not produced by wheel forces — see below |
| `steer_authority` | 0.6 → 0.25 | Lerped from 0 to `max_speed` |
| `max_speed` | 14 m/s | ~50 km/h |
| `brake_force` / `idle_brake` | ~~60 / 8~~ **200 / 90** | Godot brake units per wheel; 8 could not hold a grade |
| `wheel_suspension_stiffness` | 40.0 | Firm; it's a tank |
| `wheel_suspension_travel` | 0.3 m | |
| `wheel_friction_slip` | 3.0 | High grip; treads shouldn't drift |
| `mass` | 4000 kg | Keep ratio to engine force sane |
| `center_of_mass` | (0, −0.4, 0) | Lowered; tanks must not flip on 25° slopes |

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

ChaseCam (see 04): spring length 8 m, pivot 2.5 m above hull, pitch clamp −10°…+60°. Mouse orbits freely; hull orientation does not drag the camera (turret-follows-camera scheme requires a free camera).

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
