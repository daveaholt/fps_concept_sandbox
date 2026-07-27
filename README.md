# FPS Concept Sandbox

A single test map where an infantry player, a drivable tank, and a flyable helicopter coexist, with a Battlefield-style deploy screen for choosing where to spawn.

This is a **concept sandbox, not a game**. The goal is to prove out the systems and their seams — possession, camera handoff, vehicle physics, spawn flow, netcode — with placeholder art, so any of them can later be lifted into a real project.

**Engine:** Godot 4.7, Forward+ renderer · **Language:** GDScript

## Pillars

1. **One world, many bodies.** The player is a *controller* that can possess any controllable entity. There is no persistent "player object".
2. **Sim-leaning, tunable physics.** Every feel-critical number lives in an exported variable, never buried in code.
3. **The map is the spawn UI.** Deploying happens from a live top-down view of the actual world.
4. **Placeholder everything.** CSG/primitive meshes, flat-colour materials. No asset work until the systems are proven.
5. **Server-authoritative from day one.** The server is the game; clients send inputs and render state. Single-player is host mode with zero clients — networking is never absent, so there is no "add multiplayer later" seam.
6. **No hitscan.** Every fired thing is a simulated projectile with travel time, drop and drag.

## Running it

Game arguments go **after** the `--` separator; anything before it is for the engine.

| Mode | Command |
|---|---|
| Host (server + local player) | `godot --path .` |
| Dedicated server | `godot --headless --path . -- --server` |
| Client | `godot --path . -- --client --connect <ip>` |

Options: `--port <n>` (default 27015), `--net-log` (print replication traffic to stdout, so a two-instance test can be checked from two consoles).

Design range is 2–8 players over direct IP. There is no lobby, matchmaking or NAT punchthrough — use an IP or a VPN-LAN.

### On this machine

The Godot binary lives at `C:\Godot\Godot_v4.7-stable_win64.exe\Godot_v4.7-stable_win64_console.exe`. Use the `_console` build when you want stdout; the plain `.exe` swallows it.

## Controls

Full binding table lives in `docs/02_input.md`. Currently active:

**Free-fly observer camera** (placeholder until the infantry controller lands) — hold RMB to look, `WASD` to move, `R`/`F` up and down, `Shift` to boost, `Esc` to release the mouse.

## Project layout

```
project.godot
docs/            specs — the source of truth (see index below)
assets/          shared flat placeholder materials; real models later
autoload/        GameServer, GameClient, EventBus
levels/
  sandbox/           the graybox test map
  asset_viewer.tscn  model validation scene
entities/        player, tank, helicopter
systems/
  net/           CLI parsing and net helpers
  possession/    Controllable contract, seat logic
  spawning/      SpawnPoint, spawn flow
ui/
  deploy_map/    top-down spawn screen
  hud/           crosshair, prompts, vehicle instruments
```

## The map

Roughly 200×200 m of graybox: a 20° ramp and a 25° cross-slope for movement testing, walls and cover, a 15 m raised **Hilltop** pad with an access ramp, an **Airfield** pad with a helipad, and a **Main Base** building cluster. Three spawn points are marked with beacons.

Running north out of the perimeter gap is a **500 m firing range**: target boards at 100/200/300/400/500 m, cross-lane distance stripes, a painted grid backstop for reading bullet drop by eye, and a target dummy at 25 m painted in hit-zone colours (red head, yellow torso, blue limbs).

## Architecture in one paragraph

Exactly one node in the world is *possessed* at any moment; it receives input, owns the active camera, and is what the HUD describes. Possession is duck-typed against a three-method contract rather than inherited, because a `CharacterBody3D`, a `VehicleBody3D` and a `RigidBody3D` share no useful ancestor. The possession map and every validation live on the server. Clients send tick-stamped input commands — never positions, never hits, never damage — and render what comes back: their own infantry predicted and reconciled, everything else interpolated ~100 ms in the past.

Two rules that shape every file: **simulation code is pure and headless-safe** (no `Input` reads, no camera/UI/EventBus references anywhere in `entities/`), and **meshes live only under a `Visual` node** while collision shapes are hand-authored, so swapping placeholder art for a real model never changes handling.

## Documentation

The docs are the source of truth. Read the ones relevant to your task before writing code.

| Doc | Covers |
|---|---|
| `conventions.md` | Standing rules: architecture invariants, house style, verification |
| `00_overview.md` | Vision, pillars, repo layout, doc index |
| `01_architecture.md` | Scene composition, autoloads, signals, possession model |
| `02_input.md` | Full input map, per-context bindings |
| `03_player.md` | Infantry FPS controller |
| `04_vehicle_framework.md` | Enter/exit, seats, camera handoff |
| `05_tank.md` | Tread-drive VehicleBody3D spec |
| `06_helicopter.md` | Force-model RigidBody3D spec |
| `07_deploy_map.md` | Top-down spawn screen |
| `08_milestones.md` | Build order and acceptance gates |
| `09_assets.md` | Placeholder strategy, Visual-swap contract |
| `10_multiplayer.md` | Server authority, prediction, lag compensation |
| `11_ballistics.md` | Projectile physics, netcode, firing range |

## Milestones

Each milestone ends playable and is tagged in git. Full acceptance gates are in `docs/08_milestones.md`.

| | Milestone | Status |
|---|---|---|
| M0 | Project bones + net bootstrap | **Done** (`m0`) |
| M1 | Infantry simulation, host mode | Next |
| M2 | Replication core | |
| M3 | Prediction, reconciliation, ballistics | |
| M4 | Deploy map + death loop | |
| M5 | Vehicle framework + tank | |
| M6 | Helicopter | |
| M7 | Sandbox polish pass | |

### Current scaffolding

M0 shipped three throwaway pieces so there was something to look at and test before real entities exist. Delete them when their milestone lands:

- `entities/net_demo/` + `levels/sandbox/net_demo.gd` — the bouncing probe ball, replaced by the real snapshot pipeline at **M2**
- `levels/sandbox/dev_camera.gd` — free-fly observer, replaced by the possession camera at **M1**
- `levels/sandbox/dev_overlay.gd` — net status readout, replaced by the HUD at **M4**

## Verifying a change

```
godot --headless --path . --import
```

Must complete with zero errors and zero warnings before any milestone is called done. Networked gates are tested under the latency shim (100 ms / 20 ms jitter / 2 % loss), not just localhost.

## Conventions

- Tune via exported variables at runtime, then write the final values back into the relevant doc's tunables table when a milestone closes.
- Anything cut or changed from spec gets a one-line note in that doc's **Open questions** section — a cheap decision log.
- Placeholder art only. Nothing downloaded.
- Source files carry no comments; explanation belongs in `docs/` or here.

Full rules are in `docs/conventions.md`.
