# FPS Concept Sandbox — Overview

**Engine:** Godot 4.7 (Forward+ renderer) · **Language:** GDScript · **Status:** Design phase

## Vision

A single test map where an infantry player, a drivable tank, and a flyable helicopter coexist, with a Battlefield-style deploy screen for choosing where to spawn. This is a *concept sandbox*, not a game: the goal is to prove out the systems and their seams — possession, camera handoff, vehicle physics, spawn flow — with placeholder art, so any of them can later be lifted into a real project.

## Pillars

1. **One world, many bodies.** The player is not the camera and not the character — the player is a *controller* that can possess any controllable entity (infantry, tank, helicopter). Everything else falls out of getting this abstraction right.
2. **Sim-leaning, tunable physics.** Tank uses `VehicleBody3D` with per-wheel forces for tread-style differential steering. Helicopter is a force-driven `RigidBody3D` with collective/cyclic/pedal inputs and rotor spool-up. All feel-critical numbers live in exported variables, never buried in code.
3. **The map is the spawn UI.** Deploying is done from a live top-down view of the actual world (SubViewport + orthographic camera), with clickable markers at spawn points. Shown at session start and on death; toggleable with **M** while alive.
4. **Placeholder everything.** CSG/primitive meshes, flat-color materials. No asset work until systems are proven.
5. **Server-authoritative from day one.** The server is the game; clients send inputs and render state (see `10_multiplayer.md`). Single-player is just host mode with zero clients — there is no "add networking later" seam because networking is never absent.

## Non-goals (for this prototype)

Matchmaking/lobbies/NAT punchthrough (direct IP only), interest management, AI, damage/health models beyond a stub, sound design, real art, save systems, performance optimization. Weapons are minimal: a hitscan rifle for infantry and a shell projectile for the tank cannon exist only to make possession feel meaningful — they are not a combat system.

## Repo layout

```
fps_concept_sandbox/
├── project.godot
├── docs/                  # these specs
├── assets/                # materials now; real models later (see 09)
├── autoload/              # GameManager, EventBus
├── levels/
│   ├── sandbox/           # sandbox.tscn + terrain pieces
│   └── asset_viewer.tscn  # model validation scene (see 09)
├── entities/
│   ├── player/            # infantry controller
│   ├── tank/
│   └── helicopter/
├── systems/
│   ├── possession/        # Controllable contract, seat logic
│   └── spawning/          # SpawnPoint, spawn flow
└── ui/
    ├── deploy_map/        # top-down spawn screen
    └── hud/               # crosshair, vehicle prompts, vehicle HUD
```

## Document index

| Doc | Covers |
|---|---|
| `01_architecture.md` | Scene composition, autoloads, signals, possession model |
| `02_input.md` | Full input map, per-context bindings |
| `03_player.md` | Infantry FPS controller |
| `04_vehicle_framework.md` | Enter/exit, seats, camera handoff — shared by all vehicles |
| `05_tank.md` | Tread-drive VehicleBody3D spec |
| `06_helicopter.md` | Force-model RigidBody3D spec |
| `07_deploy_map.md` | Top-down spawn screen |
| `08_milestones.md` | Build order and acceptance gates |
| `09_assets.md` | Placeholder strategy, Visual-swap contract, import conventions |
| `10_multiplayer.md` | Server authority, prediction/reconciliation, lag compensation |
| `11_ballistics.md` | Projectile physics for all weapons — model, netcode, firing range |

## Open questions

- Third-person camera option for vehicles from day one, or first-person-only until M5? (Current spec: tank is third-person orbit by default, heli offers both — see vehicle docs.)
- Does the sandbox need a day/night or weather toggle for testing visibility? Deferred unless it becomes relevant to the heli.
- M0: layout gained `systems/net/` (CLI + net helpers) and `entities/net_demo/` (the M0 probe ball, deleted at M2). The `autoload/` comment above still reads "GameManager, EventBus" — 10 split that into GameServer/GameClient/EventBus.
