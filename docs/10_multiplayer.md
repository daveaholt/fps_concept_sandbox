# 10 — Multiplayer: Server-Authoritative Architecture

**Design targets (decided):** dedicated headless server as the real deployment, with an in-game *host mode* (server + local player in one process) for fast iteration · internet play with friends, so **100 ms RTT is the design latency** · client-side prediction for infantry from the first networked milestone.

## The one rule

> **The server is the game. Clients are input devices with a nice view.**

Clients never tell the server *where they are* or *what they hit* — only *what they're pressing*. The server simulates everything, then tells everyone what happened. Every anti-cheat property this architecture has follows from that rule, and every item in this doc is either (a) making that rule true, or (b) hiding the latency it creates.

## Topology & process model

- Godot high-level multiplayer over **ENet** (`ENetMultiplayerPeer`, UDP). Server = peer 1 = authority for everything.
- **Dedicated:** the same project exported headless (`--headless`, dedicated-server export template strips visuals). Launch: `godot --headless -- --server --port 27015`.
- **Host mode:** `--server` + a local client in-process. Identical server code path; the local "connection" just has ~0 RTT. This keeps dev iteration at F5-speed without forking any logic.
- **Client:** main menu → enter IP → connect. No lobby/matchmaking/NAT punchthrough in scope; friends use IP or a VPN-LAN (Tailscale-style). Port-forwarding is a README problem, not a code problem.
- 2–8 players design range. No interest management (everyone gets everything) — fine at this scale, listed honestly in the anti-cheat gaps below.

## Time model

| Thing | Rate | Notes |
|---|---|---|
| Server sim tick | 60 Hz (physics tick) | All gameplay logic on `_physics_process` |
| Client input send | 60 Hz | One command per tick, unreliable, redundant (see below) |
| Server snapshot broadcast | 20 Hz | Every 3rd tick; delta-less full-ish snapshots at sandbox scale |
| Client interpolation delay | 100 ms | Remote entities rendered ~2 snapshots in the past |

Ticks are numbered. Client clock-syncs on join (simple ping-based offset, re-measured occasionally) and runs its predicted tick slightly *ahead* of server time so its inputs arrive just in time — the classic setup.

## The input command (the only gameplay data clients send)

```gdscript
# One per tick, per client:
{ tick: int,
  move: Vector2,        # WASD state
  buttons: int,         # bitmask: jump, sprint, fire, interact, exit, brake, engine,
                        #   weapon_primary, weapon_secondary, weapon_cycle_up/down…
  aim: Vector3,         # camera basis forward (for firing / turret / cyclic)
  axes: Vector2 }       # context axes: collective/pedals when in heli
```

Sent **unreliable** with the last ~4 commands bundled in every packet (redundancy beats resend at 60 Hz — a lost packet is healed by the next one). Server keeps a small per-peer input buffer, consumes one command per tick, reuses the last command on starvation (client lagging), and acks `last_processed_tick` in every snapshot. Note this is exactly the 02 input map serialized — 02's actions become the bitmask/axes fields, sampled client-side only.

## Movement: predict, reconcile, interpolate

**Local infantry (client-side prediction).** The infantry move logic from 03 is refactored into a **pure step function** — `static func simulate(state, cmd, delta) -> state` — that touches no nodes except through the state struct. Client and server run *the same function*:

1. Client ticks: sample cmd → `simulate()` locally → render immediately (zero perceived latency) → store `(tick, cmd, predicted_state)` in a pending ring buffer → send.
2. Snapshot arrives with authoritative state at `last_processed_tick`: client compares against its stored prediction for that tick.
3. Mismatch beyond epsilon → **reconcile**: snap internal state to server's, replay all pending commands since, then *visually* smooth the correction over ~100 ms (internal state snaps, the mesh eases — never rubber-band the camera hard).

`CharacterBody3D.move_and_slide()` isn't callable as a pure function against arbitrary state, so the step function does its own collide-and-slide via `PhysicsServer3D`/shape casts against static geometry. This is the single biggest technical cost of prediction in Godot and it's accepted — it's also why 03's movement model stays deliberately simple. Prediction v1 ignores dynamic obstacles (moving vehicles) — mispredictions near a moving tank reconcile-correct, which is visible and acceptable.

**Remote entities (interpolation).** Everything not locally predicted — other players, both vehicles always, projectiles — renders from the snapshot buffer, interpolating between the two snapshots straddling `render_time = now − 100 ms`. Extrapolate max one snapshot on gaps, then hold.

**Vehicles are server-simulated, not client-predicted.** `VehicleBody3D`/`RigidBody3D` physics can't be re-simulated from an arbitrary state for replay (no engine support for rewinding one body). So the occupant's controls go to the server like any input, and even the driver sees their own vehicle interpolated ~RTT+buffer in the past. Mitigations that keep it feeling okay: instant *cosmetic* feedback (rotor pitch, engine audio, tread animation respond to input immediately), turret/cannon aim **is** client-predicted (it's kinematic — trivially replayable), and heavy vehicles are naturally latency-tolerant — a tank that responds 120 ms late still reads as "heavy," a rifle that does reads as broken. Priorities are correct: predict the soldier, interpolate the tank.

## Shooting under latency

All weapons are simulated projectiles — full spec in `11_ballistics.md`; summary of the networking contract here:

- Fire is just a button in the input command; the server spawns every projectile from its own muzzle transform using the command's `aim`. Clients show an immediate cosmetic tracer stepped with the same pure ballistics function.
- The per-entity **position-history ring buffer (~1 s)** built in this doc's M3 scope is the substrate for projectile lag compensation: the server steps projectiles against *historical* hitboxes offset by the shooter's view delay, with the offset decaying to zero over the first ~300 ms of flight. Net effect: close shots land "where you saw them," long shots require honest lead.
- Remote observers get one small spawn RPC per shot and step tracers locally; per-tick projectile state is never snapshotted.

## Possession & spawning over the network

01's possession model survives with one change of owner: **the possession map lives on the server** (`peer_id → entity`). Clients *request*; server validates and *grants*:

- `request_spawn(spawn_point)` — deploy map (07) becomes a client UI that RPCs this; server checks the point exists/enabled and the peer is dead/undeployed, then spawns a server-side infantry entity bound to that peer and replicates it. Spawn is never client-computed.
- `request_enter(vehicle)` — server re-checks range (≤ 4 m server-side, generous vs. the 3 m client ray to absorb latency skew), occupancy, and aliveness. Grant → despawn that peer's infantry, bind vehicle input to peer. The client-side prompt (03) is now purely advisory UI.
- `request_exit` — server runs 04's exit-point logic and spawns infantry there. Heli's `can_exit()` (06) is evaluated **server-side**.
- Client-side `possess()/unpossess()` (01) shrinks to: attach/detach *my camera, my input sampling, my HUD* when the server tells me a grant changed (`EventBus.possession_changed` now fired by replicated state).

All RPCs validate sender: only the bound peer's commands drive an entity; a command for an entity you don't own is dropped and logged (that log *is* the cheap cheater alarm).

## Connection gating (embedded client key)

Joining requires proving you hold the client build, via challenge–response with a key embedded at export time:

1. On ENet connect, the server sends the peer a random 32-byte nonce and starts a **2 s auth timer**.
2. The client replies `HMAC-SHA256(key, nonce)` (Godot's `HMACContext`). Server verifies against its own key.
3. Wrong answer, no answer in time, or *any other RPC before auth* → immediate disconnect + log. Authenticated peers proceed to the normal join flow.

The key lives in `secrets/auth_key.txt` — **gitignored, never committed** — read at startup by both client and dedicated-server builds (export includes the file; a missing key is a startup error, not a silent open server). Key rotation = new builds for everyone; acceptable at friends-scale.

Property bought: possession of the distributed client = permission to join; scanners and strangers bounce. Honest limits: a key inside a distributed binary is extractable by a determined holder of that binary (fine — those are exactly the invited people), and unauthenticated packets still reach the process before rejection, so hosting keeps a firewall layer in front for anything beyond nuisance level (see 12).

## What the server validates (anti-cheat checklist)

Positions (server-computed, always) · movement speed (implicit — server runs the sim; client cmd `move` vector is clamped to length 1) · fire cooldowns & turret clamps (server state) · hit results (server traces only) · enter/exit/spawn legality (above) · damage (server-only code path; clients never send damage numbers — `apply_damage` becomes server-side API).

**Known gaps, accepted for the sandbox:** no interest management (a wallhack can read the full snapshot — fixing this is real engineering, backlog), no aimbot heuristics, no packet encryption (join is gated by the embedded-key handshake above, but post-auth traffic is plaintext), `aim` vector trusted as-is (clamped to unit length only). These are noted because knowing *where* the line is drawn is part of the concept being explored.

## Impact on the codebase (what "baked in from the start" concretely means)

1. **Headless-safe entities.** Every entity must run with no camera, no HUD, no `Visual` requirement (09's Visual split now does double duty — the dedicated server can skip visual subtrees entirely). No entity code may touch `ui/`; EventBus becomes **client-only** — server-side events use direct GameManager calls/signals.
2. **GameManager splits** into `GameServer` (sim: possession map, spawn flow, validation — runs on server/host only) and `GameClient` (my peer's view: camera attach, deploy map state, connection UI). Both are thin autoloads; 01 is amended.
3. **Infantry movement is a pure step function** from day one (03 amended) — even in single-player host mode, input flows cmd → simulate → state. Single-player is just host mode with zero clients, so there is no "add networking later" seam: it's always there.
4. **Replication plumbing:** custom, minimal. Godot's `MultiplayerSynchronizer` is deliberately *not* used for predicted/interpolated movement (we need tick-stamped snapshots and an interp buffer it doesn't provide); `MultiplayerSpawner` **is** used for entity lifetime (spawn/despawn replication), and plain `@rpc` for requests/commands/snapshots. Rule: state flows via snapshots, events via RPC, lifetime via spawner.

## Testing rig

Host mode + `--client --connect 127.0.0.1` second instance, launched via an editor run-config script. A debug autoload can inject artificial latency/jitter/loss on the client's peer (ENet supports simulated latency; else a small send-queue shim) — **every networked milestone's acceptance criteria are tested at simulated 100 ms / 20 ms jitter / 2 % loss**, not just localhost-perfect conditions.

## Open questions

- Snapshot encoding: start as dictionaries → `var_to_bytes` (readable, fat); switch to packed arrays only if bandwidth actually hurts at 8 players. Measure first.
- Server tick 60 Hz might be lowered to 30 Hz if headless CPU becomes a concern with both vehicles active — decide from measurement, snapshot rate stays 20 Hz either way.
- Heli under 100 ms interpolated control may simply feel bad despite mitigations — if so, the fallback experiment is client-authoritative heli *attitude* with server clamps (a deliberate, documented crack in the one rule, confined to one vehicle). Flagged as an M-heli finding to write up either way.
- M1: the pure step function is `simulate(state, cmd, tuning, space, delta)`, not the 3-argument sketch above. The extra arguments are the tunables resource and a `PhysicsDirectSpaceState3D` for the collide-and-slide; both are immutable inputs, so the replay/reconciliation property this doc depends on is unchanged.
- M1: the player pose is replicated by the same naive per-tick RPC as the M0 probe ball. That is M0-tier scaffolding standing in until this doc's real snapshot pipeline lands in M2 — it is not the intended design.
- M2: the latency shim is application-level, not an ENet feature — the client delays its own outgoing command bundles and its processing of incoming snapshots, half the configured RTT each way. `--latency` is round-trip (so `--latency 100` is 50 ms each way), with `--jitter` and `--loss` alongside. This shims both directions with one knob and works headlessly, which the gate needs.
- M2: clients are spawned on an explicit `client_ready` RPC sent once the level is loaded, not on `peer_connected`. Spawning on connect races the client's scene load and the entity can be missed by MultiplayerSpawner.
- M2: no clock sync yet. The client derives its render clock from the highest snapshot tick it has seen and runs `INTERP_DELAY_MS` behind it, trimming its rate by at most 10% to track drift and hard-resyncing past 30 ticks. The "run slightly ahead of server time" scheme this doc describes is only needed once prediction lands, so it is deferred to M3.
- M2: `get_peer_id()` caches the last connected id. `multiplayer.get_unique_id()` errors once the ENet peer exists but is no longer connected, which produced ~90 spurious errors per client shutdown and would have masked real ones.
- Post-M2: a ~10.5 hour two-instance soak held 20.0 snapshots/s with zero reorders, resyncs, drops, errors or entity leaks across 753k snapshots and 2.26M acked commands. No drift in the interpolation clock over that span.
- M3: lag compensation uses the ENet round-trip statistic for the shooter's peer plus the fixed interpolation delay as the view delay, decaying to zero over the first 300 ms of flight per 11.
- M5: the snapshot blend is key-driven rather than shaped like infantry state. It previously indexed `a` (aim) on every entity, which threw ~970 times per client the moment tanks entered the stream carrying a quaternion instead. Position lerps, quaternions slerp, turret angles use `lerp_angle`, and anything absent is simply carried from the newer snapshot.
