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
3. Vehicle validates (**a seat is free** — multi-seat as of M7; see below).
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

## Seats (M7)

`single seat in v1` is over. Vehicles carry a `Seats` helper (`systems/possession/seats.gd`) holding one peer per seat, and **seat 0 is always the driver/pilot**. That choice is deliberate: `owner_peer` keeps its old meaning as "who is driving", so the twenty-odd places that read it stayed correct rather than being rewritten to ask about seats.

- Entering takes the **first free seat**, driver first. A full vehicle is refused; a partly full one is not.
- Exiting frees only that peer's seat. **A pilot leaving does not evict the gunner**, and the vehicle stays occupied.
- Commands queue **per seat**. Two occupants map to the same entity, so a single command stream would have the pilot and gunner fighting over one queue. `push_command(cmd, seat)` keeps them apart, and infantry keeps the one-argument form.
- The vehicle's team follows the **driver**, falling back to any remaining occupant when the driver leaves.

Current fits: helicopter 2 (pilot, gunner), tank 2 (driver, machine gunner).

### Open questions

- M7: `team_id()` first read `owner_peer == 0` to mean "empty". With seats that is wrong — a gunner alone in a helicopter has no driver, so the vehicle reported **unaligned** and its own team could shoot it. It now asks `seats.is_empty()`. Anything else phrased as "is someone driving" should be re-read as "is anyone aboard".

## Open questions

- M5: `VehicleCommon` is a **Node3D**, not the plain `Node` the tree above shows. It holds an `Area3D` and two `Marker3D`s, and a plain `Node` has no transform — it severs the 3D hierarchy, so those children sat at the world origin instead of on the hull. The symptom was an exit that placed the player at the marker's *local* offset (3 m from world zero) and an entry zone nowhere near the vehicle. Any helper node holding spatial children has to be spatial itself.
- M5: exit does not rewind the occupant's position through history; it uses the vehicle's current transform. Fine for the tank and consistent with 05's note that compensation barely applies at shell speeds.
- M5: client code that touches the possessed entity must be duck-typed, not written against infantry. `GameClient.is_predicting()` read `my_entity.role`, which only exists on the soldier — the moment a player entered the tank it threw once per physics tick, roughly 4500 times in a few minutes. It now asks `has_method("is_predicted")`. The reason this reached a play session is that no headless test had ever entered a vehicle; there is now a `--bot-drive` client that walks to the tank and requests entry, so the possession seam is covered by the automated networked run.
- M5: entering is requested by client-side UI code (the interaction scanner reading `interact`), not by a bit in the input command. A bot cannot enter by setting `InputCommand.INTERACT`; it has to call `GameClient.request_enter` the same way the scanner does. Worth knowing because it means the enter path is *not* exercised by anything that only synthesises input commands.
- M7: vehicles expose `weapon_ray(seat) -> [origin, direction, params_id]`, which is what the HUD reticle is drawn from. It returns the seat's actual muzzle and axis — the pilot's rockets leave along the hull's nose, not along the camera, so a fixed centre-screen crosshair would have been wrong by the whole chase-camera offset. Returning the params id lets the HUD apply the round's own drop rather than assuming a flat trajectory: over 150 m the rocket falls 4.28 m and the minigun 0.18 m.
