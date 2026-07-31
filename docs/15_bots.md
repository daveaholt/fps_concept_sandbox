# 15 — AI Bots

Bots are **server-side entities with no peer**. The server generates an `InputCommand` for each one every tick and pushes it down the same pipeline a human's commands take, so movement, shooting, ammo, damage, tickets, nameplates and the HUD need no bot-specific branches. A bot is a player that happens to have its input written by code.

## Identity

A bot's peer id is `<= BotController.PEER_BASE` (−1000, descending). Real peer ids are positive, so nothing can be mistaken for the other and every `multiplayer.get_peers().has(peer)` guard already excludes bots for free — no RPC is ever aimed at one.

Bots take **roster slots** like anyone else, which is what makes teams, squads, tickets and the deploy map work without changes. They get the slot's callsign.

## Filling

`fill_with_bots()` runs at match start and assigns a bot to every empty slot, controlled by a host-only checkbox in the lobby. **This is a change to 13's "empty slots stay empty" rule**, and worth being precise about: the intent there was that you should not need sixteen humans to start a match. That still holds — bots are opt-out, and with them off the old behaviour is exactly what happens. The suite asserts both.

## Navigation

A `NavigationRegion3D` baked at level load from the graybox's own **static colliders** (`geometry_parsed_geometry_type = 1`, world mask), source geometry taken from the `navmesh_source` group so the region can sit beside `Terrain` rather than having to parent it.

Paths come from `NavigationServer3D.map_get_path()` directly rather than a `NavigationAgent3D` per bot — no node churn for sixteen agents, and the controller already owns the per-bot state a path needs. Bots repath every 0.8 s.

- The agent numbers are deliberately voxel-aligned: `cell_size` and `cell_height` 0.25, `agent_radius` 0.5, `agent_height` 1.75, `agent_max_climb` 0.75. Godot rounds each to voxel units and warns when it has to, and a 0.75 climb is what lets a bot step onto the 0.6 m airfield slab. Measured: 479 polygons, a 15.2 m climb onto the Hilltop plateau, so the ramp is genuinely being used rather than the path failing.

## Behaviour

`BotBrain` holds the decisions as **pure static functions** — facing, rate-limited turning, target leading, whether to fire, whether to close. `BotController` holds the per-bot state and does the work that needs the world: pathing, target choice, line of sight. The split is not decoration: a class that touches an autoload cannot be constructed in a `--script` harness, so the decisions would be untestable if they lived with the plumbing.

Current behaviour is deliberately simple: pick the nearest enemy, path to them, close to a 12 m standoff, turn at 260°/s, fire when within 55 m with line of sight and the aim inside 6°, reload when dry, respawn 4 s after dying. Shots lead a moving target using the round's flight time.

## Open questions

- **M7: bots spawn at a random enabled spawn point, not the default one.** The first version used `_default_spawn` for everyone, so fifteen bots landed on the same pad, were instantly inside each other's standoff, stopped moving and killed eleven of themselves in three and a half seconds. It looked like "bots do not move" until the corpse count explained it. There are no team-owned spawns by design (13), so scattering across all points is the closest thing to sensible.
- M7: bots respawn on a timer and spend a ticket each time, so a bot-filled match burns tickets fast. That is honest — sixteen players dying is sixteen tickets — but `START_TICKETS` at 25 was chosen for human-paced matches and probably wants revisiting alongside the 8v8 target.
- M7: bots do not use vehicles. `08` lists that as part of the ask and it is deliberately staged second — a bot that drives needs seat requests, a different command shape per seat, and a reason to prefer a vehicle over walking, none of which the infantry loop needs.
- M7: no squad coordination, no cover, no reloading behind it, no grenades — a bot walks at its target and shoots. Enough to make a 16-player match testable by one person, which was the point.
