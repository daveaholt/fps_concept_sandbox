# 13 — Teams, squads and the pre-game lobby

Added during M7. Nothing in the sandbox had a concept of sides before this; 07 had already deferred its squad-filtered player markers "until a team concept exists", and this is that concept.

## Model

Sixteen fixed slots, arranged as four squads of four. Squad identity **is** a colour; a team is a pair of squads.

| Team | Squads |
|---|---|
| 1 | **Red**, **Yellow** |
| 2 | **Blue**, **Green** |

`SQUAD_SIZE = 4` divides evenly into 8 a side, so squads are always full-capacity and never uneven — that is why 4 was chosen over 5. Nothing needs to handle a ragged squad.

A slot is identified by `(squad, index)` or equivalently by a flat `0..15`. Slots are the authority on membership: a player's team and squad are *derived* from the slot they hold, never stored separately. There is one place to change and one place to read.

## Match phases

```
LOBBY  ──Start──▶  PLAYING  ──a team runs out of tickets──▶  RESULT  ──▶  LOBBY
```

An earlier draft had two phases and no end condition, on the grounds that a sandbox has nothing to win. Teams changed that — once there are sides, "who won" becomes a question the game can answer, so matches now end.

**Tickets.** Each team starts with `START_TICKETS` respawns. Every death costs the dying player's team one. The first team to reach zero loses; the other wins. This is the Battlefield model and it is chosen because it makes every death cost something and gives the deploy screen weight, without needing objectives the sandbox does not have.

- Only **infantry deaths** spend tickets today. Vehicles carry health but have no destruction path yet — *vehicle respawn on wreck* is still an open M7 backlog item — so a destroyed tank costs nothing until that lands. Worth revisiting together.
- A death by an **unaligned** player (holding no slot, which should not happen once the lobby is enforced) spends nothing rather than crashing or guessing a side.
- `START_TICKETS` is a tuning number, not a design one. It is deliberately low for a sandbox where two people are testing; a real 8 v 8 wants considerably more.

**RESULT** is a brief announcement of the winner, then everyone returns to the lobby. **Slots are kept**, so a rematch is one press of Start. Tickets reset and every live body is despawned on the way back.

The deploy map is gated to PLAYING, so nobody can deploy into a finished match or out of the lobby.

## Slot assignment is a request, not a claim

Same shape as vehicle entry in 04, for the same reason: **the server is authoritative for everything** (10). The client asks; the server decides and broadcasts.

1. Client sends `request_slot(slot)`.
2. Server validates: phase is LOBBY (or see late join), slot exists, slot is unoccupied, requester is connected.
3. On success the server records it and broadcasts the whole lobby state. On failure it drops the request and logs — the log *is* the cheap alarm, exactly as with enter/exit.

The client never writes its own slot, and the lobby UI renders only what the server has confirmed. A rejected request should be visible as the slot simply not moving.

**Any occupied slot may press Start.** No party-leader concept. This is a friends sandbox, not a competitive queue, and leader plumbing (election, hand-off when they leave, what happens on disconnect) is a surprising amount of state to defend a feature nobody asked for.

## Late join, leaving, switching

- **Late join.** A peer connecting during PLAYING gets the slot picker and chooses, then deploys — it does not wait for a new match, because there are no matches to wait for. **A launch with a CLI mode flag is auto-assigned the first free slot instead**, which is what keeps the headless suite working; the client tells the server which it wants via `client_ready(auto_slot)`. Without that split, a human joining a running match was silently dropped into a random squad with no say, which is not what the lobby is for.
- **Leaving.** Disconnect frees the slot immediately.
- **Switching in the lobby.** Free — move to any unoccupied slot.
- **Switching during PLAYING.** Not in v1. It implies despawning a live body, possibly one inside a vehicle, and re-deploying it on the other side. Deferred rather than half-built.

## Bots fill the blanks — eventually

The Titanfall-2-style flow this is modelled on fills empty slots with AI on Start. **AI bots do not exist yet** (M7 backlog), so v1 starts with whatever humans are present and leaves empty slots empty: two players pressing Start get a 1 v 1 on a sixteen-slot board.

The seam is `fill_with_bots()`, called by the server on Start and currently a no-op. When bots land it fills the free slots and nothing else about this document changes. Not to be confused with the existing `--bot` / `--bot-drive` CLI puppets, which are test-harness fixtures with no AI.

## What a team actually changes

Deliberately narrow. Four things:

1. **Identity.** Team and squad colour are replicated per player and shown on the HUD.
2. **Deploy-map markers.** This unblocks 07's deferred item: markers are filtered to the viewer's own squad/team and never show the enemy. 07's warning stands unchanged — the moment players become legible on any map view without this filter, an accepted wallhack *gap* becomes a deliberate *feature*.
3. **Friendly fire is off.** Damage is skipped when shooter and target share a team.
4. **Spawning on a squadmate.** See below. This is the one place where a squad *means* something mechanically rather than cosmetically.

### Explicitly not changed: spawn point ownership

**Spawn points stay shared. There is no team ownership of spawns and no team-filtered spawn list.** All three points in the sandbox remain available to both sides. This keeps the map symmetric-by-default and avoids inventing a two-base layout for a sandbox whose geometry was never designed around one. Revisit only if the sandbox grows an objective.

## Spawning

The deploy map offers two kinds of destination:

- **The fixed spawn points**, shared by everyone, as today.
- **Any living squadmate**, who becomes a spawn location for the rest of their squad.

A squadmate is a valid destination when they are alive and either:

- **on foot** — you appear beside them, dispersed as below; or
- **in a vehicle that has a free passenger seat** — you appear **in the seat**, in flight or not.

Spawning into a seat is the *safest* of the three cases, not the riskiest: there is no world placement and no momentum handoff at all, because the occupant is bound to the vehicle rather than positioned near it. An earlier draft of this document ruled vehicles out on the grounds that dropping a soldier next to a moving tank or hovering helicopter is a physics problem. That reasoning was sound and the conclusion was wrong — it argued against placing someone *beside* a vehicle, which seat-spawning never does.

A squadmate whose vehicle is **full** is not a valid destination. Neither is a dead one.

**This half depends on passenger seats**, which do not exist yet (M7 backlog). Until they land, only the on-foot case is live. When they land, the helicopter gains a genuine role as a mobile squad spawn, which is a real gameplay lever and worth watching: combined with the deliberate absence of a combat-safety rule below, a helicopter loitering over a fight becomes a spawn beacon. That may be excellent or may need a rule; it is not knowable in advance.

If the tank ever gains a **second seat** — a machine gunner is the obvious candidate — it is spawnable on exactly the same terms when unoccupied. Nothing here is helicopter-specific; the rule is "a free passenger seat", whatever carries it.

There is deliberately **no combat-safety rule** in v1 — no "not recently damaged" timer, no enemy-proximity check. Spawning onto a squadmate mid-firefight is allowed and will sometimes be a mistake. Adding a rule is easy later; guessing at the right one now is not.

### Dispersal

Every spawn, fixed or squadmate, places the soldier at a **random offset within a radius** of the destination rather than on its exact coordinate.

This replaces the existing scheme, which is a deterministic ring: `angle = TAU * slot / MAX_PEERS` at a fixed radius, keyed to the current possession count, with the first deployer landing exactly on the point at zero offset. That was added at M2 to stop bodies stacking so replication could be eyeballed, and it has three problems at sixteen players — the index is the *live entity count* rather than a stable per-player slot so it reuses and collides after deaths, the first player is always exactly on the marker, and a fixed-radius ring is predictable enough to camp.

Rules for the random placement:

- Sample within the radius, then **verify the position is clear** using the same penetration probe M1 added after players spawned inside geometry and fell through the world. Resample on failure, then fall back to the exact point rather than refusing to spawn.
- **The randomness lives on the server only.** Spawn position is chosen once, at deploy, and replicated. It never enters `InfantrySim.simulate`, which must stay a pure deterministic step function or client prediction and reconciliation break. This is worth stating because "no randomness in the sim" is a hard rule and this is a legitimate exception *outside* it.

## Friendly fire

Damage flows through exactly three call sites today — a direct projectile hit and a splash hit in `BallisticsManager`, plus the dev-damage path in `GameServer`. Each needs the same guard.

The shooter's team is known at fire time on the server, so it rides with the projectile the way `shooter_peer` already does, rather than being looked up per hit. Targets answer `team_id()`.

- Same non-zero team → **no damage**, and no hit is logged as a hit.
- Team `0` means unaligned: range dummies, an empty vehicle, anything spawned outside a slot. Unaligned targets are damageable by everyone, which keeps the firing range working exactly as it does now.
- **A vehicle's team is its occupant's team**, and reverts to unaligned when empty. A tank nobody is driving is a target for both sides. This avoids the alternative — permanently team-owned vehicles — which would need a team to own them at level-authoring time, and the sandbox has one tank and one heli.

## Front end

```
[TITLE]  ──Host / Join──▶  [LOBBY]  ──Start──▶  deploy map ──▶  play
```

The main menu is Host, Join (with address entry) and Quit. The lobby is the slot board above.

**The CLI must bypass all of it.** Every automated gate in this project launches with `--host` / `--client` / `--bot` flags and drives the game headlessly; a title screen that has to be clicked through would break the entire verification suite at once. Flagged launches skip the menu, auto-occupy a free slot, and auto-start, landing exactly where they land today. This is not a convenience — it is the difference between the suite working and not.

## Acceptance criteria

- Two clients connect, take slots in different squads, and the board agrees on both screens plus the server.
- A slot already held cannot be taken by a second player; the request is rejected and logged, and the board does not move.
- Start with fewer than sixteen players works; empty slots are simply absent from the match.
- A player's team and squad survive the trip into the world: HUD shows the right colour, deploy-map markers show squadmates and never the enemy.
- A living squadmate on foot is offered as a spawn destination; a dead one is not.
- Once passenger seats exist: a squadmate in a vehicle with a free seat is offered, and choosing them puts the player *in the seat* rather than beside the vehicle, whether it is parked or in flight. A squadmate in a full vehicle is not offered.
- Sixteen deploys at one point produce sixteen distinct positions, none inside geometry, none stacked.
- Shooting a squadmate does nothing. Shooting an enemy, a range dummy, or an empty vehicle does what it does today.
- A peer joining mid-match takes a free slot and plays.
- Disconnecting frees the slot.
- **Every existing headless gate still passes unchanged**, because the CLI path never sees the menu.

## Open questions

- Squad-spawn is in v1, so squads mean something mechanically from the start. Anything further — squad voice, squad orders, shared squad objectives — is a separate feature and belongs on the backlog, not here.
- The dispersal radius is one number and wants tuning against sixteen players, not two. Too small and bodies still stack; too large and a squad spawns scattered across a hillside.

## Implementation notes

- **Part 1 (server model + friendly fire) is built.** `systems/teams/roster.gd` owns the sixteen slots and derives team and squad from them; `GameServer` holds the phase, the roster, and the `request_slot` / `request_start` RPCs, validating and logging rejections the same way enter/exit does. `fill_with_bots()` exists and does nothing, as specced.
- The friendly-fire rule lives on `Roster` as a static, **not** on `GameServer`. The first version put it on the autoload and had `BallisticsManager` call it, which broke every `--script` harness that compile-depends on ballistics: autoload identifiers do not resolve at compile time in a `--script` main loop, a trap this project has hit before. It also violated 01's rule that sim code does not reach for autoloads. `Roster` is a plain class, so ballistics depends on nothing global.
- For the same reason **a vehicle's team is a stored field set by the server on entry**, not derived by asking the autoload who the driver is. Set in `handle_enter_request`, cleared on both exit paths.
- **Infantry team is stamped inside `_spawn_infantry`, not at the call sites.** The first version set it only on the deploy path, which meant a player exiting a vehicle respawned unaligned and could be shot by their own squad. It is now one assignment in the one function every spawn path already goes through.
- Still to build: the main menu and lobby UI (part 2), and squad-spawn with randomised dispersal (part 3). The deploy map still shows every spawn point to everyone and no player markers at all, which is 07's pre-teams behaviour and remains correct until part 3.
- **Part 2 (main menu + lobby) is built.** `ui/menu/main_menu.gd` and `ui/lobby/lobby.gd` are overlays under the level's existing `UI` CanvasLayer, alongside the HUD and deploy map — not separate scenes. There is no scene transition and the world simply loads behind the menu, which avoids a whole class of transition bugs for a sandbox that only ever has one level.
- **The CLI bypass works by making the launch flag explicit rather than by special-casing the UI.** `NetCli.has_explicit_mode()` is true when `--host`, `--client` or `--server` is present. Flagged launches auto-host or auto-connect exactly as before and never build the menu; an unflagged launch now starts *nothing* and waits at the title. That last part is a behaviour change: a bare `godot --path .` used to auto-host, because `get_mode()` defaults to HOST. **Launch scripts and manual test instructions must pass `--host` now.**
- The bypass reuses the spec's own late-join rule rather than adding a parallel path: `client_ready_local` auto-assigns a free slot whenever the phase is already PLAYING, and a flagged launch starts in PLAYING. So the CLI route and a genuine late joiner take exactly the same code path, and there is no "test mode" branch to rot.
- The host's own client needs a **local** roster mirror. `receive_roster` is `call_remote`, so a listen server never receives its own broadcast, and without the mirror the host's phase would stay LOBBY and its deploy map would never open. `_broadcast_roster` now calls `GameClient.apply_roster` directly and *then* RPCs remotes — the same shape as `submit_local_commands` for input.
- The deploy map is gated on `phase == PLAYING`, and opens automatically on the transition out of LOBBY for anyone not already alive.
- The lobby doubles as the mid-match slot picker: it is visible whenever the phase is LOBBY **or** the local player holds no slot. The Start button hides once the match is running, since there is nothing left to start.
- The HUD carries a team and squad readout in the squad's colour, top-left, driven off `roster_changed`.
- **Tickets and the RESULT phase are built.** `START_TICKETS` is **25**, deliberately small so a match can be run to its end while testing with two people; a real 8 v 8 wants considerably more. `RESULT_SECONDS` is 8.
- Closing the deploy map on match end needed a **forced** close. `set_deploy_map(false)` refuses while the player is dead — correct, so nobody can dismiss the spawn screen and stand around as a corpse — but that guard also blocked the match-end close, leaving the deploy screen sitting over the result. `close_deploy_map()` bypasses the aliveness check and is used only for the phase transition.
- Tickets floor at zero rather than going negative, and `_spend_ticket` is inert outside PLAYING, so deaths landing in the same frame as the final one cannot drive the count below zero or re-trigger the end.
- **Deferred hosting broke damage, and it took a live report to find.** `register_level` sets `ballistics.authoritative = is_active` *at registration time*. Before part 2 that was always correct, because the server started in `_ready`, before the level loaded. With the menu the order inverts: the level registers while nothing is hosting, latches `false`, and `_step` then skips hit tracing entirely — so **nobody could damage anybody at all**, on either team. `_start` now sets the flag when hosting begins.
- The lesson is the ordering, not the flag: **anything `register_level` reads off server state is being read before the menu has started the server.** That was the only such read; a second one would fail the same silent way.
- It also shows the limit of the friendly-fire tests written in part 1. They exercised `_may_damage` directly and passed throughout, because the bug was upstream of the team check — no hit was ever generated to test. `verify_kill` now fires a real projectile at an enemy and at a squadmate and checks the health numbers, which is the only version of that test that could have caught this.
- The squad and ticket readouts live in the HUD's bottom panel beside weapon and health, not the top-left corner, where the dev overlay drew on top of them.
- **Part 3 (squad spawn, dispersal, squad markers) is built.** Eligibility lives on the server (`can_spawn_on`) and is re-checked when the request arrives, not only when the list is offered — the client's list is UI, the server's check is the rule.
- Dispersal samples `sqrt(randf()) * radius` so points spread evenly over the *disc* rather than clustering at the centre, then shape-casts the infantry capsule and resamples if it would land inside geometry, falling back to the exact point after twelve tries rather than refusing to deploy. Radius is 4.5 m.
- The client finds squadmates by node name (`Player_<peer>`) in the replicated players root, so the deploy map draws them without an extra round trip. **That doubles as 07's deferred squad-filtered markers**: the only player markers are your own squad, because they come from `roster.squadmates()` and nothing else. No code path exists that could draw an enemy, which is stronger than filtering a full list.
- Deferred as specced: spawning into a free vehicle seat. `can_spawn_on` already refuses a squadmate in a vehicle, so the rule is in place and only needs the seat concept to become useful.
- **Squad-spawn into a free seat is live** now that seats exist (04). Two client-side bugs had to be fixed for it to be usable, and both were invisible to the server-side tests:
  - The client located squadmates by looking for `Player_<peer>` in the players root. A squadmate who boards a vehicle has their infantry body **despawned**, so they simply vanished from the deploy map and could never be offered — which is exactly how it was reported from play. Seat occupancy now rides the vehicle snapshot (`st`), and the client falls back to scanning vehicles for the peer.
  - `get_node_or_null` returns nodes that are **queued for deletion but not yet freed**, so for a frame after boarding the client found the stale body and would have offered a spawn at a corpse. It now skips anything queued for deletion.
- Dispersal fallback is a small random offset (1.2 m), not the exact base point. Falling back to the base put two players in the same spot, which is the stacking the feature exists to prevent. Measured separately: the clearance probe passes **38–40 of 40** samples on open ground, so the fallback is genuinely rare rather than the normal path.
