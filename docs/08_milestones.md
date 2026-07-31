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

## MH — Hosted friend test (added with 12; runs any time after M6, before inviting friends)

**Deferred past M7 by the repo owner: the VM is a running cost and there is no point paying it before there is something worth inviting people to.** Nothing in M7 depends on MH, and MH depends only on M6 being closed, so the order is free.

Implement the embedded-key auth handshake per 10 (nonce challenge, HMAC reply, 2 s drop, gitignored `secrets/auth_key.txt` baked into exports) and stand up the Azure server per 12 (VM, NSG, systemd unit, DNS label, auto-shutdown, deploy script).

**Gate:** a friend connects from the internet via the DNS hostname and plays; a client with a wrong/missing key (debug flag) is dropped within 2 s and logged; the server survives a session and `az vm deallocate` ends billing.

## M7 — Sandbox polish pass (open-ended)

Done: passenger seats (**unlocked squad-spawn into a free seat — see 13**) · helicopter armament (chin minigun + rocket pods, gunner-operated) · vehicle icons + *squad/team* players on deploy map · per-seat gunner camera and projected weapon reticle · **tank cockpit cam — the "first person tank" ask, closed** · vehicle damage states, destruction and respawn · hit confirmation.

Backlog, any order: exit-momentum inheritance · interest management experiment (the wallhack gap in 10) · snapshot encoding slimming if bandwidth measured ugly · heli artificial horizon · tread shader · a jeep (tests how much 04/05 generalize) · sounds · first-person viewmodel with tracers leaving the weapon rather than the eyeline.

### Added after M6

Requested by the repo owner. Listed separately from the line above because each one has a dependency or a spec consequence worth knowing before it is picked up.

- **Infantry squat / crouch.** Not specced anywhere today — 03 has no stance concept. The catch is that it lands inside `InfantrySim.simulate`, the pure step function the server and the predicting client both run, so it has to be deterministic and replay-safe or reconciliation breaks. It also changes the capsule height, which moves the hit-zone geometry in 11 and everything the lag-compensation history replays against. Cheap to *feel*, not cheap to get right.
- **ADS / zoom for all weapons.** No action is bound for it at all yet. Touches 02 (a binding on every device — LB was earmarked in the M6 heli scheme), 03 (infantry weapon handling), and both vehicles. Decide early whether zoom is a pure camera FOV change or also alters spread/recoil, because the second makes it part of the sim rather than the view.
- ~~**Vehicle damage states.**~~ **Done.** Landed together with destruction and respawn, because the three are the same feature: a health bar with no zero is not a damage state, and a wreck that never returns empties the sandbox after two kills.
- **Vehicle impact damage.** Collision and hard-landing damage. Interacts with 06's landing criterion (< 4 m/s on skids, no bounce-flip) — that number becomes the boundary between a landing and a crash — and with ramming in 05.
- **Minimap.** **Inherits 07's squad/team rule verbatim.** 07 already warns that the moment players become legible on *any* map view, it turns the wallhack that 10 lists as an accepted gap into a deliberate feature. There is still no team or squad concept in the sandbox, so a minimap either ships with no player markers at all, or waits for teams. Do not ship an all-players version intending to filter it later.
- ~~**Squad / team management**~~ — **done**, specced and recorded in `13_teams.md`. Delivered: roster and slots, friendly fire off, main menu and pre-game lobby, tickets and match end, squad spawn, randomised dispersal, and the squad-filtered deploy markers 07 had deferred since M4. Spawning into a free vehicle seat is the one specced piece still waiting, on passenger seats.
- **16-player target (8 v 8).** Raised after M6, doubling 10's 2–8 design range. `MAX_PEERS` is 8 today. Egress roughly quadruples, which is enough to want measuring but not enough to force interest management on its own — see 10's open questions.
- **AI bots.** Gameplay AI: navigation, target selection, using vehicles. Distinct from the existing `--bot` / `--bot-drive` / `--bot-wall` flags, which are test-harness puppets that walk a fixed circle or drive at the tank. Bots are also what make the 16-player target *testable* — without them an 8 v 8 check needs 16 humans, and every gate in this project so far has been verified by one person plus a headless rig.
- **HUD layout pass.** There is no HUD spec anywhere — 04 defines the *contract* (the HUD polls the possessed node once a frame and asks it for values) but nothing describes the layout, and it has been grown one label at a time by whoever needed a readout. It now carries squad, tickets, weapon, health, a draw bar, a prompt and a result banner, in a hand-positioned bottom panel. Worth one deliberate pass: what belongs on screen, where, and which readouts are per-vehicle. Cheap, and it stops the next addition pushing something off the edge.
- **Deploy screen on a controller.** The spawn map is mouse-only: markers are picked by clicking them, so a controller player can open the screen and then cannot deploy from it. Needs a moveable target reticle driven by the right stick, snapping or nearest-match selection onto markers, and `deploy_confirm` already exists on Enter / A. 02 has recorded "no keyboard marker navigation in the prototype" since M0 and 07's flow section assumes a mouse throughout, so both need revising rather than just adding a binding. Worth doing before any friend test — it is the one screen where a pad player is stuck, and the deploy screen is the first thing anyone sees.
- **Flares / countermeasures.** Presupposes a guided threat, and nothing in the sandbox locks on to anything — every weapon is an unguided projectile per 11. Either a lock-on AA weapon comes first and flares defeat it, or flares are decoration. Worth deciding which before building either.

## Working agreements

- Tune via exported vars at runtime; write final values back into the docs' tunables tables when a milestone closes (docs are source of truth for feel numbers).
- Anything cut or changed from spec gets a one-line note in the relevant doc's Open questions — cheap decision log.
- Every networked gate is tested under the latency shim, not just localhost-perfect conditions.
- Each milestone = one git commit minimum, tagged `m0`…`m7` (plus `mh`).

## Open questions

- M0: shipped three extras beyond the milestone text, all scaffolding with a stated expiry — a free-fly `DevCamera` (there is nothing possessable to look through until M1), a `DevOverlay` net-status readout (replaced by the HUD in M4), and a `--net-log` flag that prints replication traffic so the M0 gate can also be checked from two headless consoles.
- M0: the graybox was authored by a one-shot generator script that was **not** kept in-repo — `levels/sandbox/sandbox.tscn` is a normal editor-editable scene and is the artifact of record from here on.
- M1: `DevCamera` was deleted as planned. A remote client therefore has no view of its own until M2 gives it an entity — at M1 only the host has a body, which is what "host mode" in this milestone means.
- M2: the M0 probe ball and its naive per-tick transform RPC are deleted, replaced by the snapshot pipeline as planned. The player pose rides snapshots now.
- M2: added a `--bot` client (walks a fixed circle) and `--net-trace` / `--net-log` output. Without a synthetic input source the gate could not be exercised headlessly, and "smooth" needed to be measured rather than eyeballed.
- Post-M2: `physics_interpolation` is on and `physics_jitter_fix` is 0 (the two fight). Sim runs at 60 Hz while displays run far higher — 240 Hz on the current dev machine — so without interpolation each simulated position is held for several frames and then jumps. This was also the first (wrong) guess at the bounce above; it is worth having regardless, but it was not the cause.
- Post-M2: deploys fan out around the spawn point rather than stacking every player on the exact same coordinate. Cosmetic, but two soldiers standing inside each other makes the replication gates impossible to eyeball.
- Post-M2: anything calling `multiplayer.get_unique_id()` / `is_server()` per frame errors once the peer exists but is disconnected. Entity role is fixed for an entity's lifetime, so it is now cached at `_ready`.
- MH added retroactively (with 12): the auth handshake was briefly specced into M2's scope, but M2 had already shipped — connection gating is its own pre-hosting milestone instead.
