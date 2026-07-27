# 04 — Vehicle Framework (enter / exit / seats / cameras)

Shared behavior for anything drivable, implemented once as `systems/possession/vehicle_base.gd` *composition helpers* + a per-vehicle script that implements the Controllable contract. (No deep inheritance: tank extends `VehicleBody3D`, heli extends `RigidBody3D`; both pull in the same helper node `VehicleCommon` as a child.)

## VehicleCommon child node provides

```
VehicleCommon (Node)
├── EntryZone (Area3D, layer: interact)   # generous hull-sized box
├── ExitPoint (Marker3D)                  # left side of hull, 1.5 m out
├── ExitPointAlt (Marker3D)               # right side, used if left blocked
└── SeatCameraRig                          # per-vehicle, see below
```

> **Networked (10):** enter/exit are client *requests*, server *grants*. The client-side ray/prompt below is advisory UI; the server independently re-validates range (≤ 4 m, generous vs. the client's 3 m ray to absorb latency skew), occupancy, and `can_exit()` before acting. Vehicle physics always simulates on the server; occupants' controls arrive as input commands.

## Enter flow

1. Player's interact ray (or overlap fallback) hits `EntryZone` → prompt.
2. `interact` → `GameClient.request_enter(vehicle)` → RPC → server validation.
3. Vehicle validates (not already occupied — future-proofing for multi-seat, single seat in v1).
4. Server grants — despawn infantry, bind peer to vehicle; on the owning client:
   - `player.unpossess()` → infantry body **despawned** (its transform is irrelevant afterward; exit position comes from the vehicle).
   - `vehicle.possess()` → vehicle camera goes current, vehicle input live, engine state per vehicle spec.
5. `EventBus.possession_changed(vehicle)` → HUD swaps to that vehicle's instrument panel.

## Exit flow

1. `exit_vehicle` (F) while possessed → `GameClient.request_exit()`; server checks `can_exit()` (tank: always; heli: only when landed-ish — |velocity| < 2 m/s and rotor contact / low altitude, see 06).
2. Pick exit point: `ExitPoint` unless a shape query says it's inside geometry, else `ExitPointAlt`, else directly on top of the hull (last resort — never refuse to exit in a sandbox; getting stuck is worse than a silly exit).
3. Vehicle `unpossess()` (input dead, camera released, engine per spec — tank idles off, heli keeps spooling *down*).
4. Server spawns a fresh infantry body at the exit transform (replicated via spawner); the owning client possesses it on arrival.

Exit inherits **no** vehicle momentum in v1 (jumping out of a moving heli plants you standing, mid-air, then normal gravity applies — acceptable and hilarious; revisit later).

## Camera rigs

Each vehicle owns its rig; two standard shapes reused across both:

- **ChaseCam** — `SpringArm3D` (with collision margin) + `Camera3D`, orbit driven by mouse; spring length and pivot height per vehicle. Default for the tank.
- **CockpitCam** — fixed `Camera3D` at a seat marker with mouse free-look inside clamped yaw/pitch cone. Default for the heli; `toggle_camera` (V) flips heli between the two. Tank stays third-person in v1 (turret aiming is mouse-driven; cockpit view adds nothing yet).

Rule: rigs *read* mouse only while possessed; rigs never modify vehicle physics state.

## HUD contract

On `possession_changed`, HUD asks the new controllable for `get_display_name()` and shows/hides instrument panels by vehicle group (`tank`, `helicopter`). Instrument specs live in each vehicle doc. HUD never polls the world otherwise; vehicles push values via EventBus-carried per-frame signal? No — polling *the possessed node only* once per frame from HUD is simpler and contained (single reference handed over in the signal). That single exception to "UI holds no world refs" is accepted and documented here.

## Acceptance criteria (M3 gate, tested with tank first)

- Enter → drive → exit → walk → re-enter loop is seamless, no camera pops or one-frame T-poses.
- Exiting against a wall uses the alternate/topside exit; player is never spawned inside collision.
- Despawned infantry: no stray capsule left in the world, no orphaned camera claiming `current`.
- Possession spam (E/F mashing) cannot double-possess or leave `possessed == null` while alive.
