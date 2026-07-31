# 01 — Architecture

## The central idea: possession

The riskiest seam in this prototype is switching control between infantry, tank, and helicopter without the camera, input, and physics stepping on each other. Everything is organized around one contract:

> At any moment, exactly one node in the world is **possessed**. It receives input, owns the active camera, and is what the HUD describes. Everything else simulates passively.

There is no persistent "player object." The infantry body is just another possessable entity — when you enter the tank, the infantry body is despawned (stowed), and when you exit, it is respawned at the vehicle's exit point. This avoids every "hide the player inside the tank" collision headache.

### The Controllable contract

Rather than inheritance (the tank is a `VehicleBody3D`, the player a `CharacterBody3D`, the heli a `RigidBody3D` — no useful common ancestor), possession is duck-typed against a small contract. Any possessable scene root must provide:

```gdscript
func possess() -> void        # take input focus; activate own camera
func unpossess() -> void      # release input focus; deactivate camera
func get_display_name() -> String
```

and must belong to the `controllable` group. Vehicles additionally implement the seat/exit contract in `04_vehicle_framework.md`.

Input is sampled client-side into a tick-stamped **input command** (see `10_multiplayer.md`) and consumed by the entity's simulation on the server; the entity itself never reads `Input` directly in sim code. Possession gates *whose* commands an entity accepts. This keeps each controller self-contained and copy-paste-able into other projects (pillar 1).

> **Multiplayer overlay.** This doc describes the logical model; `10_multiplayer.md` describes where each piece physically runs. Summary: the possession map and all validation live on the **server**; clients hold only "which entity is mine" plus camera/HUD attachment. Anything in `entities/` must run headless (no camera, no UI, `Visual` optional).

## Autoloads

Three autoloads, kept deliberately small:

**`GameServer`** — runs only on server/host. Owns the possession map (`peer_id → entity`), spawn flow, and all request validation.

```gdscript
func handle_spawn_request(peer: int, spawn_point: SpawnPoint) -> void
func handle_enter_request(peer: int, vehicle: Node) -> void
func handle_exit_request(peer: int) -> void
func entity_died(entity: Node) -> void    # despawn; notify owning peer
```

**`GameClient`** — runs on every playing client (including the host's local player). Owns connection state, my-possession tracking, camera/HUD attachment, deploy map open/close.

```gdscript
var my_entity: Node = null                # what I control, per server grant

func request_spawn(spawn_point) / request_enter(vehicle) / request_exit()
func request_deploy_map(open: bool) -> void
```

**`EventBus`** — **client-only** signal relay so UI never holds references into the world:

```gdscript
signal possession_changed(new_controllable: Node)   # fired from replicated grants
signal deploy_map_toggled(is_open: bool)
signal interaction_prompt(text: String)   # "" clears the prompt
```

Rule of thumb: world → UI communication goes through EventBus signals; UI → world goes through GameClient requests (which RPC to GameServer). Nothing in `entities/` may reference anything in `ui/` or EventBus — server code has neither.

## Scene composition

```
sandbox.tscn (Node3D)                     # main scene
├── WorldEnvironment + DirectionalLight3D
├── Terrain (StaticBody3D + CSG pieces)
├── SpawnPoints (Node3D)
│   ├── SpawnPoint "Main Base"            # infantry spawn
│   ├── SpawnPoint "Hilltop"
│   └── SpawnPoint "Airfield"
├── Vehicles (Node3D)
│   ├── Tank (instance)
│   └── Helicopter (instance)
└── UI (CanvasLayer)
    ├── HUD (crosshair, prompts, vehicle instruments)
    └── DeployMap (starts open)
```

Vehicles are placed in the level, not spawned — this is a sandbox; respawning wrecked vehicles is out of scope until M5.

## Camera policy

Every possessable entity owns its own `Camera3D` (or camera rig) inside its own scene. Possession = calling `camera.make_current()` (or `current = true`) on the newly possessed entity's camera — there is no global camera to fight over, and the deploy map's top-down camera lives in a `SubViewport` so it never competes with the world's active camera. Mouse mode: `MOUSE_MODE_CAPTURED` whenever something is possessed, `MOUSE_MODE_VISIBLE` whenever the deploy map is open.

## Pause & deploy-map semantics

The deploy map does **not** pause the world (it can't — the server keeps simulating for everyone) — it only steals local input and shows the cursor. While it is open, `GameClient.my_entity` may be null (start of session / after death) or non-null (player pressed M mid-life; closing returns control seamlessly). The map is just client UI.

## Death (stub)

Entities expose `health: float` and a **server-only** `func apply_damage(amount: float)` — clients never send damage numbers. For the prototype only the infantry body reacts: at `health <= 0` → `GameServer.entity_died()` → despawn body, owning client's deploy map opens (KIA variant). Vehicle damage is logged but ignored. This is deliberately the thinnest possible slice — enough to exercise the death → redeploy loop.

## Physics layers

| Layer | # | Contents |
|---|---|---|
| `world` | 1 | Terrain, static props |
| `infantry` | 2 | Player capsule |
| `vehicle` | 3 | Tank + heli bodies |
| `projectile` | 4 | Reserved — projectiles are raycast-stepped data, not bodies (see 11) |
| `interact` | 5 | Vehicle entry Area3Ds (scanned by player's interact ray) |

Projectile segment casts query world|infantry|vehicle. Interact areas collide with nothing — they exist only for the entry raycast/overlap query.

## Open questions

- Should possession history be a stack (exit tank → automatically re-enter... no) — flat is fine; exiting always spawns infantry. Confirmed flat.
- EventBus vs. direct GameManager signals: EventBus kept separate so UI code has exactly one import. Revisit if it stays this small.
- M0: Terrain is a `StaticBody3D` with hand-authored `BoxShape3D` colliders and primitive `BoxMesh` pieces under `Visual`, not CSG — keeps 09's "collision is authored, never generated from meshes" literally true for the graybox too.
- M0: `sandbox.tscn` has no `UI (CanvasLayer)` yet (HUD is M1, DeployMap M4). It carries a free-fly `DevCamera` and a `DevOverlay` CanvasLayer as scaffolding instead; both go when the real possession camera and HUD land.
- M7: the map now carries **two of each vehicle** — `Tank`/`TankB` 44 m apart on open ground, `Helicopter`/`HelicopterB` 40 m apart on the airfield pad — so tank-versus-tank and heli-versus-heli can be tested with two clients. The level registers every child of `Vehicles` in a loop, so adding them needed no code; the only real constraints are that names stay unique (`GameServer._find_vehicle` resolves by name over the wire) and that each rests level on its terrain. `verify_vehicle_placement` asserts both, plus that nothing drifts or falls after 200 physics ticks, because a vehicle placed slightly inside a slope looks fine in the editor and slides for the rest of the session.
- **M7: a rule that a client-side system needs is a pure function in its own class, not a method that reads autoloads.** Three times now a helper has been written against `GameClient` and turned out to be untestable, because autoload identifiers do not resolve at compile time in a `--script` harness and the whole class fails to construct: `InteractionScanner` (fixed by `InputFocus`), `Minimap` (fixed by passing markers in), and `Nameplates` (fixed by `Relations`). The failure is quiet in the worst way — the assertions simply never run and the suite reports zero failures, which is exactly what happened here until the missing PASS lines were noticed. If a decision is worth testing, it goes somewhere with no autoload references.
- M7: the map now carries five spawn points — three contested landmarks (Main Base, Hilltop, Airfield) and two team camps (West, East) that exist only to spawn on. Each camp has a tank and a helicopter beside it; the two camps are 140 m apart.
