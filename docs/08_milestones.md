# 08 — Milestones & Build Order

Rewritten for server-authoritative multiplayer (10). Order principle unchanged — every milestone ends playable, riskiest unknowns first — but the network core now sits *before* vehicles, because possession, spawning, and vehicle control all ride on it. Expect the netcode milestones (M2–M3) to be the hardest of the project; that's by design, they're the concept being explored.

## M0 — Project bones + net bootstrap (1 session)

Project settings (Forward+, physics layers per 01, input map per 02), autoload stubs (`GameServer`, `GameClient`, `EventBus`), folder layout, shared placeholder materials + Asset Viewer (09). Test map graybox: ~200×200 m ground, 20° ramp, 25° cross-slope, walls/cover, Hilltop (raised pad ~15 m), Airfield pad, Main Base cluster, plus the 500 m firing-range strip with distance-marked targets (11). WorldEnvironment + sun. **Net bootstrap:** CLI args (`--server`, `--client --connect <ip>`, host mode), ENet peer setup, connect/disconnect logging, a server-driven bouncing ball replicated to clients via `MultiplayerSpawner` + naive transform RPC.

**Gate:** clean open in 4.7; two instances on one PC — client sees the server's ball move.

## M1 — Infantry simulation, host mode (1–2 sessions)

Player per 03 with movement as the pure `simulate(state, cmd, delta)` step function from day one, custom collide-and-slide included. In host mode the local loop already flows cmd → simulate → state (no prediction needed at 0 RTT). Both weapons (rifle + pistol) with slot switching in the sim state per 03, cosmetic fire effects only; dev damage key (K). Hard-coded spawn at Main Base.

**Gate:** 03 acceptance criteria in host mode; movement code demonstrably contains no `Input` or node references outside its state struct.

## M2 — Replication core (1–2 sessions)

Tick-stamped input command pipeline (redundant unreliable sends, server input buffer, ack), 20 Hz snapshots, client interpolation buffer (100 ms), join/leave with entity spawn/despawn, latency/jitter/loss simulation shim, second player visible and moving smoothly.

**Gate:** two clients + dedicated headless server; remote players smooth at simulated 100 ms / 20 ms jitter / 2 % loss; join/leave doesn't leak entities.

## M3 — Prediction, reconciliation, ballistics (2–3 sessions)

Client-side prediction + replay reconciliation for own infantry, visual error smoothing. `BallisticsManager` per 11 (pure step function, data-array projectiles, tracer rendering), position-history ring buffer, historical-stepping compensation with decay, both infantry weapons switched from cosmetic stubs to real rounds.

**Gate:** own movement feels instant at simulated 100 ms; artificial mispredictions (forced by the shim) correct without camera snaps; running into a wall predicted-vs-server agrees (no persistent drift); plus 11's acceptance criteria at the firing range (visible drop, close-range "hit where you saw them," long-range lead, 200-projectile spam with no hitch) including hit zones — head/torso/leg shots on the range dummy log distinct damage, verified under the latency shim so zone rewind is exercised.

## M4 — Deploy map + death loop (1 session)

Deploy screen per 07 as client UI over `request_spawn`; KIA variant; recon mode with M. Death loop via dev key across the network (client A "kills" client B's soldier → B redeploys).

**Gate:** 07 acceptance criteria with two clients; spawn validation rejects a forged spawn-while-alive request (test via debug key that sends an illegal request).

## M5 — Vehicle framework + tank (2–3 sessions; expect tuning)

VehicleCommon + networked enter/exit grants per 04, tank per 05: server-simulated `VehicleBody3D`, interpolated hull, client-predicted turret, shells through the M3 ballistics system (new params set + splash + impact marker only — no new netcode). Second client rides shotgun *visually only* (no passenger seat — they just watch the tank drive).

**Gate:** 04 + 05 acceptance criteria under simulated latency; enter/exit request spam across two clients can't double-grant; a client whose vehicle input is forged for an un-owned tank gets dropped + logged; rifle hits on tank front/side/rear/top log the correct sector multipliers.

## M6 — Helicopter (1–2 sessions; expect tuning)

Heli per 06 reusing the 04 framework and the vehicle replication path from M5 untouched — if it needs changes, that's a finding worth writing down. Includes the flagged experiment: is 100 ms interpolated heli control flyable? Record the verdict (and if needed, the client-attitude fallback) in 06/10 open questions.

**Gate:** 06 acceptance criteria in host mode; networked flight verdict written down either way.

## M7 — Sandbox polish pass (open-ended)

Backlog, any order: passenger seats · vehicle icons + *other players* on deploy map · exit-momentum inheritance · vehicle respawn on wreck · interest management experiment (the wallhack gap in 10) · snapshot encoding slimming if bandwidth measured ugly · tank cockpit cam · heli artificial horizon · tread shader · a jeep (tests how much 04/05 generalize) · sounds.

## Working agreements

- Tune via exported vars at runtime; write final values back into the docs' tunables tables when a milestone closes (docs are source of truth for feel numbers).
- Anything cut or changed from spec gets a one-line note in the relevant doc's Open questions — cheap decision log.
- Every networked gate is tested under the latency shim, not just localhost-perfect conditions.
- Each milestone = one git commit minimum, tagged `m0`…`m7`.

## Open questions

- M0: shipped three extras beyond the milestone text, all scaffolding with a stated expiry — a free-fly `DevCamera` (there is nothing possessable to look through until M1), a `DevOverlay` net-status readout (replaced by the HUD in M4), and a `--net-log` flag that prints replication traffic so the M0 gate can also be checked from two headless consoles.
- M0: the graybox was authored by a one-shot generator script that was **not** kept in-repo — `levels/sandbox/sandbox.tscn` is a normal editor-editable scene and is the artifact of record from here on.
- M1: `DevCamera` was deleted as planned. A remote client therefore has no view of its own until M2 gives it an entity — at M1 only the host has a body, which is what "host mode" in this milestone means.
- M2: the M0 probe ball and its naive per-tick transform RPC are deleted, replaced by the snapshot pipeline as planned. The player pose rides snapshots now.
- M2: added a `--bot` client (walks a fixed circle) and `--net-trace` / `--net-log` output. Without a synthetic input source the gate could not be exercised headlessly, and "smooth" needed to be measured rather than eyeballed.
