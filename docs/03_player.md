# 03 — Infantry Player

`entities/player/player.tscn` — root `CharacterBody3D`, in groups `controllable`, `infantry`.

## Scene tree

```
Player (CharacterBody3D)
├── CollisionShape3D (capsule, r 0.4, h 1.8)
├── Head (Node3D, y ≈ 1.6)              # yaw on Player, pitch on Head
│   ├── Camera3D
│   └── InteractRay (RayCast3D, len 3.0, mask: interact | vehicle)
├── RifleStub (hitscan from camera center)
└── HUD hooks via EventBus only
```

## Movement model

Standard Quake-descendant controller — no acceleration curves cleverness in v1, just distinct ground/air handling. **Structural requirement from 10:** all movement logic lives in a pure step function, `static func simulate(state, cmd, delta) -> state`, run identically by server (authoritative) and owning client (prediction). It performs its own collide-and-slide via `PhysicsServer3D` shape casts against static geometry rather than `move_and_slide()` (which can't replay arbitrary states); the `CharacterBody3D` root is effectively a transform holder + collision shape. Keep the model simple — every feature added here is a feature the replay path must reproduce exactly.

- Grounded: velocity moves toward `wish_dir * speed` at `accel`; instant-feeling but not snappy-instant.
- Air: same steering at `air_accel` (much lower); no air-strafe tricks.
- Gravity from project settings times `gravity_scale`; jump sets vertical velocity directly.
- `floor_max_angle` default (45°); ramps in the test map stay below this.

### Tunables

| Export | Default | Notes |
|---|---|---|
| `walk_speed` | 5.0 m/s | |
| `sprint_speed` | 8.5 m/s | Sprint only forward-ish (dot(wish, forward) > 0.5) |
| `accel` / `air_accel` | 60 / 10 m/s² | |
| `jump_velocity` | 4.8 m/s | ≈ 1.2 m jump apex |
| `mouse_sensitivity` | 0.12 °/px | Pitch clamped ±89° |
| `gravity_scale` | 1.0 | |

## Interaction

Every physics frame while possessed, `InteractRay` reports what it hits. If the collider (or an ancestor) is in group `vehicle_entry`, emit `EventBus.interaction_prompt("Enter %s [E]" % name)`; on `interact`, call `GameManager.possess(vehicle)` via the vehicle's `request_enter(from: Node)` (see 04). Prompt clears when the ray misses. Additionally, a fallback overlap check (small sphere query at the player position) catches the "standing right against the hull, looking slightly off" case — ray-only entry proved annoying in similar prototypes.

## Weapons (primary / secondary)

Two slots, always the same loadout in v1: **rifle** (primary) and **pistol** (secondary). Both fire ballistic projectiles through the shared `BallisticsManager` (11) — no hitscan; damage, drop, and latency compensation are 11's business. No ammo, no reload, no ADS, no pickups. The pistol exists to make weapon *switching* a real specced system, not for balance.

Weapon definitions are resources (`assets/weapons/*.tres`):

| Field | Rifle | Pistol |
|---|---|---|
| `ballistics_params` | rifle round (11) | pistol round (11) |
| `fire_mode` | full-auto | semi-auto (one shot per click) |
| `rpm` | 600 | 450 cap |
| `draw_time` | 0.5 s | 0.3 s (classic fast-swap) |

**Switching is simulation state, not UI state.** `weapon_index`, `switch_progress`, and `fire_cooldown` live in the infantry sim-state struct, driven by command bits, so switching is client-predicted and replay-reconciled like movement (10) and enforced server-side like everything else — you cannot fire during a switch, and the server agrees for the same reason the client does: same pure function. Bindings per 02: `1` primary, `2` secondary, scroll cycles.

**Feedback:** HUD weapon name + slot indicator (via the possessed-node poll, 04); switch shows a brief draw progress tick. No viewmodel arms in v1 (backlog) — tracers, HUD, and sound-stub are the feedback. Fire while `switch_progress < 1` is ignored, not queued.

## Visual (what other players see)

You are first-person and see nothing of yourself, but remote players see a **rigid placeholder soldier** under `Visual` (per 09): capsule torso, head sphere, and a prism "weapon proxy" held at aim height. No skeleton, no animation — legs don't walk, the body glides and yaws; accepted placeholder jank, and precisely why hit-zone rewind stays exact (11). The placeholder's proportions intentionally match the `HitZones` shapes (the head sphere *is* the head zone), so what you aim at is what registers. The weapon proxy swaps mesh with the active slot — weapon switching is visible to others for free — and pitches with the owner's replicated aim so you can read where a soldier is looking. Own-body hiding: the body meshes live on a render layer the owner's camera culls (`cull_mask`), so there's no per-node hide logic and spectator/chase cams (if ever added) work unchanged.

## Hit zones

Per 11's locational-damage spec, the soldier carries a `HitZones` resource: head sphere (×2.0) at the top of the capsule, torso box (×1.0), limb boxes (×0.75) hugging the capsule's sides/lower half. Rigid, unanimated, rewind-exact. Rifle body shot = 25, headshot = 50, leg = 18.75 — enough spread to verify at the firing range against a target-dummy capsule with painted zone bands.

## Death

`apply_damage` reduces `health` (100 default). At ≤ 0: `GameManager.player_died()`. No ragdoll — the body just despawns (`queue_free`) and the deploy map opens. There is nothing in the sandbox that deals damage to the player yet except tank splash (see 05); that's fine, it exercises the loop.

## Acceptance criteria (M1)

- Mouse look with clamped pitch; no roll drift after wild spins.
- Walk/sprint/jump around the test map including up ramps; no sliding on 20° slopes when standing still (`stop_on_slope` behavior verified).
- Prompt appears when looking at a vehicle within 3 m and E possesses it.
- Esc releases mouse; clicking recaptures.
- Weapon switch: 1/2/scroll swap with correct draw times; firing during a draw does nothing; rifle full-auto holds, pistol requires clicks; under simulated latency (M3) switch-then-immediately-fire predicts and reconciles without a phantom shot.

## Open questions

- M1: the interaction prompt is emitted by a client-side `InteractionScanner` in `systems/possession/`, not by the player entity — 01/10 forbid anything in `entities/` from touching EventBus, which supersedes this doc's `EventBus.interaction_prompt` line. The entity only exposes `get_interact_target()`; the scanner decides what to say. The `GameManager.possess(vehicle)` call likewise becomes a server grant (10).
- M1: `RifleStub` is gone. 11 supersedes hitscan, so M1 ships a cosmetic muzzle flash only and real projectiles arrive with `BallisticsManager` in M3. `HitZones` is deferred to M3 for the same reason; the placeholder body's proportions were still authored to match the zones.
- M1: movement gained two collision details the model needs but the spec did not name — the capsule is lifted by `floor_probe_lift` (0.1 m) before a grounded move and snapped back down afterwards, and a penetration probe pushes the capsule out of geometry it starts inside. The lift gives a free ~0.1 m step-up; the push-out is what stops a spawn placed inside a prop from falling through the world forever. Both are deterministic and replay-safe.
- M1: the vehicle half of the interaction acceptance criterion ("E possesses it") cannot be verified until M5. A `TestVehicle` Area3D in group `vehicle_entry` was added to the graybox so the prompt half is testable now.
- Post-M2: the floor snap is an **absolute** placement, not an incremental one. The original lift-then-shape-cast-snap drifted: `cast_motion` deliberately reports a conservative distance and always stops slightly short of the surface, so each grounded tick landed a fraction of a millimetre high, and because the next tick lifted from *that* result the error compounded — the player rose ~0.4 mm/tick until the snap could no longer reach the ground, dropped back, and repeated. Measured range 0.23 m with 61 direction reversals in 600 ticks; in first person it reads as the world bouncing. The probe now raycasts down for the exact contact point and places the capsule there, plus `radius * (1/cos(slope) - 1)` so a rounded capsule rests correctly on a grade. Nothing accumulates. Straight-line walking on flat ground hid this completely, which is why the M1 suite passed — the regression test walks a turning circle.
