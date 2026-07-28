# 11 — Ballistics

**Decision:** no hitscan anywhere. Every fired thing — rifle rounds and tank shells alike — is a simulated projectile with travel time, gravity drop, and air drag, run through one shared system. This supersedes 03's hitscan rifle and 05's RigidBody shell.

## The model (v1 realism tier)

Per projectile, per tick, semi-implicit Euler:

```
vel += (gravity * gravity_scale − drag_k * vel * vel.length()) * delta
segment cast: old_pos → old_pos + vel * delta      # continuous collision
pos = hit ? impact_point : old_pos + vel * delta
```

Quadratic drag (`drag_k` folds air density, drag coefficient, area, mass into one tunable) gives the two behaviors that make ballistics *feel* real: velocity decays with range, and drop steepens beyond the linear-fall intuition. Deliberately **excluded from v1** (backlog ladder, in order of payoff): wind, penetration through thin materials, ricochet at grazing angles, spin drift, Coriolis. Each slots into the same step function later without touching the networking.

Damage scales with remaining energy: `damage = base_damage * (vel_now² / muzzle_vel²)` clamped to a floor of 0.3 — long shots hit softer, for free.

## Implementation: data, not nodes

Projectiles are **not** scene nodes and **not** physics bodies. A `BallisticsManager` (server-side sim; client-side cosmetic mirror) holds a flat array of structs `{pos, vel, params_id, shooter_peer, spawn_tick, time}` and steps them all in one loop, colliding via `PhysicsDirectSpaceState3D.intersect_ray` segment casts (mask: world | infantry | vehicle). Visuals are a separate concern: a `MultiMesh` of tracer streaks fed from the array each frame. Hundreds of rounds cost microseconds; there is nothing to instance, replicate, or free per shot. (The tank shell *mesh* everyone sees is one of these tracers with a bigger streak — the 05 RigidBody shell is gone.)

The step function is **pure** — `static func step(pos, vel, params, delta) -> [pos, vel, hit?]` — same code on server (authoritative) and client (tracer prediction), same principle as 03's movement sim.

At 60 Hz a rifle round moves ~13 m per tick; the segment cast makes that airtight against tunneling. If integration accuracy at high speeds ever visibly diverges client-vs-server, add fixed substeps (×2/×4) inside the step function — flagged, not expected to be needed.

## Networking (supersedes 10's "Shooting under latency")

Fire is a button in the input command like everything else. On receipt the server spawns the projectile from the *server-side* muzzle transform using the command's `aim`. Then:

- **Client-side cosmetic tracer:** the shooter's client spawns a local tracer immediately (muzzle flash, streak) using the identical step function. It carries no authority — it exists so firing feels instant. Server and cosmetic tracer diverge by at most one reconciliation's worth of muzzle position; invisible in practice.
- **Historical stepping (lag compensation for projectiles):** M3's per-entity position-history ring buffer is reused. While a projectile flies, the server tests it not against *present* hitboxes but against history sampled at `projectile_time − shooter_interp_delay`, with that offset **decaying to zero over the first ~300 ms of flight**. Close-range shots therefore hit "where the shooter saw them" (full compensation, like hitscan had); long shots converge to present-time positions, so leading distant targets is real skill, not lag-fighting. This is the standard big-FPS compromise, and the decay window is an exported tunable — one more knob the sandbox exists to play with.
- **Remote observers** see tracers driven by lightweight spawn events (`spawn_tick, pos, vel, params_id` — one small reliable RPC per shot) and step them locally with the shared function; per-tick projectile state is never snapshotted. Impacts/kills are server events replicated normally.

Anti-cheat posture unchanged: clients send only the fire button + aim direction; muzzle position, trajectory, hits, and damage are all server-computed.

## Projectile parameter sets

`params_id` indexes a small resource table (`assets/ballistics/*.tres`):

| Param | Rifle round | Pistol round | Tank shell (HE-ish) | Notes |
|---|---|---|---|---|
| `muzzle_velocity` | 400 m/s | 280 m/s | 180 m/s | See scale note below — deliberately sub-realistic |
| `drag_k` | 0.006 | 0.010 | 0.002 | Tune at the firing range, write back here |
| `gravity_scale` | 1.0 | 1.0 | 1.0 | |
| `base_damage` | 25 | 20 | 80 direct + 4 m radius splash | Splash is server overlap query at impact |
| `max_lifetime` | 4 s | 3 s | 8 s | Then despawn (map edge safety) |
| `tracer_every` | 1 (all visible) | 1 | 1 | Sandbox: see everything |

Fire rate, fire mode, and draw times are **weapon** properties (03's `WeaponDef` resources), not ballistics params — this table only describes rounds in flight. The pistol round's higher drag makes it visibly lobby past ~100 m at the range, which is exactly the legibility we want from a secondary.

**Scale honesty:** on a ~200 m map, *actual* rifle ballistics (900 m/s) drop ~2 cm at 100 m — imperceptible, and the whole feature would be a no-op. Games solve this by slowing bullets (Battlefield uses roughly 400–700 m/s effective); we start at 400 m/s so drop and travel time are *legible* at sandbox distances, and treat muzzle velocity as a feel knob, not a datasheet value. If you later want datasheet realism, the fix is map scale, not the ballistics code.

## Hit registration, end to end

The authoritative answer to "did that shot land," consolidating the pieces above and 10:

1. Client sends fire bit + `aim` in the tick's input command; shows a zero-authority cosmetic tracer. **No client ever reports a hit** — hit claims don't exist on the wire.
2. Server validates the trigger against its own sim state (ownership, cooldown, not mid-draw) and spawns the round from the server-side muzzle.
3. Each tick: integrate, then segment-cast previous → new position (no tunneling at any speed).
4. The cast tests **historical hitboxes** from the ~1 s ring buffer, sampled at `projectile_time − shooter_interp_delay`, offset decaying to zero over the first ~300 ms of flight — close shots register where the shooter *saw* the target; long shots require true lead.
5. Damage (energy-scaled, splash if applicable) applies through the server-only `apply_damage` path; death flows through `GameServer.entity_died`.
6. Clients learn the outcome via a replicated impact event (effects) and snapshots (health/death). Cosmetic-tracer vs. authoritative-impact divergence bound: < 0.5 m at 300 m.

### Locational damage (hit zones)

Registration is two-phase: the segment cast finds the **body** (plain collision shapes, reconstructed at the rewound transform — that part is unchanged), then a refinement pass determines **where** on the body, picking a damage multiplier. Two mechanisms, chosen per entity type:

**Zone shapes (infantry).** A `HitZones` resource on the entity: labeled shapes in local space — `head` (sphere, ×2.0), `torso` (box, ×1.0), `limbs` (boxes, ×0.75) — re-tested against the same segment after a body hit; nearest zone entered wins, no zone hit falls back to ×1.0. Because the v1 soldier has **no animated skeleton** (remote players see a rigid placeholder body whose proportions match these zones — 03), zones are rigid children of the single buffered transform — the history ring buffer needs nothing new and rewound zones are exact. *The* known future cost is flagged here: an animated third-person body would require per-bone history (store a compact pose per tick) — real work, deferred until such a body exists.

**Directional sectors (vehicles).** No extra shapes: transform the impact point into hull-local space and bucket it by angle/height into `front ×1.0 · side ×1.25 · rear ×2.0 · top ×1.5` (tank values, exported; see 05). Rear-armor gameplay is a coordinate transform. Heli keeps uniform ×1.0 in v1 (vehicle damage is a logged stub anyway — the multiplier flows into the log so it's testable now and meaningful the day vehicle health matters).

Both phases run server-side inside step 4 — a client can no more claim a headshot than claim a hit. The debug hit log records zone/sector per impact, which is how the M3/M5 gates verify this without a damage UI.

## The firing range

The graybox (M0) gains a **range strip**: a flat 500 m lane off the map's north edge with distance-marked target boards at 100/200/300/400/500 m, a painted grid wall for observing drop visually, and a static target-dummy capsule (with `HitZones` and painted zone bands) at 25 m for locational-damage verification. This is where `drag_k`/velocity tuning happens and where the M3 gate is verified. (Map total footprint grows to fit; deploy-map ortho size follows.)

## HUD

Rifle: none in v1 — the tracer *is* the feedback; a mil-dot style crosshair is backlog. Tank: 05's crosshair gains a simple predicted-impact marker (client steps the shared function ~2 s ahead against terrain only — cheap, cosmetic, and honest since it uses the true step function).

## Acceptance criteria (folded into M3 / M5 gates)

- Range: visible drop at 200 m+, chronograph-style debug readout of velocity at each board, server hit log agrees with observed tracer impacts.
- Under 100 ms simulated latency: close-range (< 50 m) snapshots-of-strafing-target hits land "where you saw them"; 300 m shots require genuine lead.
- Client tracer vs. server impact point divergence < 0.5 m at 300 m (log both, assert in a debug overlay).
- 200 simultaneous projectiles (debug spam key) with no frame hitch on server or client.
- Tank predicted-impact marker matches actual shell impact within ~1 m on flat ground.

## Open questions

- Does the decaying-compensation window feel right, or should the sandbox expose *no* compensation as a comparison mode? (Trivially: set decay window to 0. Worth an A/B evening.)
- Shell splash through cover: v1 overlap query ignores occlusion (splash goes through walls). Cheap line-of-sight check from impact point is the obvious M7 fix; noted so it doesn't read as a bug.
- Heli weapons (rockets = ballistics params with thrust term?) — the step function accepts an accel term easily; backlog, but the door is open.
- M0: the 25 m dummy is graybox only — one capsule collider plus painted head/torso/limb bands in the zone colours (red ×2.0 / yellow ×1.0 / blue ×0.75). The `HitZones` resource and the two-phase refinement pass stay in M3 as spec'd; the bands exist so those zones get authored against a visible reference.
- M3: measured trajectories with this doc's tunables. Rifle (400 m/s, drag_k 0.006): 100 m drop 0.57 m at 210 m/s in 0.37 s; 200 m drop 3.64 m at 115 m/s in 1.02 s; 300 m drop 15.20 m at 64 m/s. Pistol (280 m/s, drag_k 0.010): 100 m drop 1.58 m at 98 m/s; 200 m drop 17.69 m. Drop and travel time are legible at sandbox distances exactly as intended, and the pistol lobs past 100 m as the table predicts — but past ~200 m both rounds shed most of their velocity (the rifle keeps 29% at 200 m), so long-range shooting is more mortar than rifle. Flagged rather than changed: the table says tune at the range and write values back, and that is a feel call to make by eye.
- M3: registered ballistics targets are excluded from the world segment cast. The range dummy is a StaticBody on the world layer, so the world ray consumed the hit before zone testing ever ran and every shot logged zero damage. Entity hits are resolved separately against rewound history, so targets must not also be hit as scenery.
- M3: hit testing is analytic rather than physics-based — segment against capsule for the body, then segment against the zone shapes in the entity's local space at the rewound transform. Reconstructing bodies at historical transforms via the physics server would be far more expensive and no more accurate for rigid, unanimated placeholders.
- M3: 200 simultaneous projectiles step and trace in 1.26 ms per tick against a 16.6 ms budget, so the data-array approach has roughly 13x headroom at the acceptance figure.
- Post-M3: tracers are positioned per render frame using `Engine.get_physics_interpolation_fraction()`, not per physics tick. A rifle round advances 6.75 m per 60 Hz tick, so on a 240 Hz display an uninterpolated 6 m streak teleports more than its own length between updates and reads as disconnected segments scattered through the air rather than a streak. The streak also trails behind the round now instead of being centred on it.
- Post-M3: the muzzle flash is culled from the owner's camera along with their body. It sits 0.55 m from the eye, offset 18 degrees right and 14 degrees down, so for the shooter it rendered as a large glowing blob wandering around the lower right of the screen. 03 already says the owner's feedback is the tracer and the flash exists for other players to see, so it belongs on the own-body layer.
- M5: vehicles are traced as an oriented box against their **current** transform, not a rewound one, and their sector multiplier comes from `resolve_sector` rather than a `HitZones` resource. Two consequences worth knowing: registering a target that cannot answer `get_history()` used to throw once per projectile per tick — with 200 rounds live that took a physics tick from 1.26 ms to 2188 ms, so target types must be duck-typed deliberately rather than assumed to be infantry.
- Post-M5: `Basis.scaled()` scales the basis **rows**, which stretches along *world* axes, not the basis's own. Building a tracer as `Basis.looking_at(dir).scaled(Vector3(1, 1, length))` therefore stretched every streak along world Z regardless of heading — correct-looking when firing roughly along Z, and lying flat across the view when firing along X. Scale the local axis instead by rebuilding the basis from its columns. The streak transform now lives in `Ballistics.tracer_transform()` as a pure function so it can be asserted across headings; verifying it through the MultiMesh is not possible, because `get_instance_transform` reads back zeros once the mesh is bound to a MultiMeshInstance3D in a `--script` run even with a real renderer.
- Post-M5: **the tank shell was effectively invisible, and the tracer code was the reason.** Drawn length was `min(authored, speed * 0.02)`. That cap only ever bites the *slowest* round, and the tank shell is the slowest thing in the game: authored 9 m, capped to 3.6 m (rifle 6 m and pistol 4 m were never touched, which is why nobody noticed). On top of that, `tracer_colour` was never read at all — `_build_tracers` hardcoded the rifle's yellow into a shared material — so a 3.6 m × 6 cm yellow sliver left the muzzle at 161 m/s and could not be picked out. Tracers now use the authored length and a new per-round `tracer_width` (0.06 default, 0.22 for the shell), applied as instance-transform scale. Rifle and pistol are unchanged: their lengths were never clipped, and the default width reproduces the original 0.06 m cross-section exactly.
- Post-M5: the shell had been verified as *existing* (it spawns, flies, and `visible_instance_count` is 1) well before it was verified as *legible*. "The projectile is there" and "the player can see the projectile" are different claims and needed different checks; `verify_cannon` now asserts the drawn length, width and colour rather than just the spawn.
- Post-M5: **the first attempt at the above made the tracer disappear entirely** — worse than the sliver it replaced. It swapped the shared material's fixed albedo for per-instance `MultiMesh` vertex colour (`use_colors` + `vertex_color_use_as_albedo`) so each round could carry its own `tracer_colour`. Every headless check still passed, because headless verifies geometry and counts and cannot verify that a pixel was lit. Reverted: the material and base mesh are byte-identical to the version known to render, and what survives is only instance-transform scale (length and thickness), which cannot affect whether something is drawn. **`tracer_colour` is still not read — all tracers remain the same yellow**; per-round colour needs a change only a human can validate on screen, so it is deferred rather than guessed at twice.
