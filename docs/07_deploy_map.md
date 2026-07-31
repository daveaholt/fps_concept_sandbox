# 07 — Deploy Map (spawn screen)

`ui/deploy_map/deploy_map.tscn` — full-screen `Control` on the UI CanvasLayer. Open at session start, on death, and via M while alive. The world keeps simulating underneath (see 01 pause semantics).

## Rendering: live top-down view

A `SubViewport` renders the actual world from an orthographic `Camera3D` looking straight down:

```
DeployMap (Control, full rect)
├── SubViewportContainer (stretch)
│   └── SubViewport (own_world = false, shares main World3D)
│       └── TopDownCamera (Camera3D, orthographic, y = 150, rotated −90° pitch)
├── MarkerLayer (Control)          # spawn buttons, positioned each frame
├── DeployButton + selected-spawn label
└── Header ("DEPLOY" / "KILLED IN ACTION" variant text)
```

- Ortho `size` frames the whole playable area with margin; fixed in v1 (no pan/zoom — the map is one screen).
- The SubViewport gets a low update rate while closed (`UPDATE_DISABLED`) and `UPDATE_ALWAYS` while open — free perf.
- A dim/desaturate ColorRect over the viewport keeps UI markers readable; markers are UI, not 3D sprites, so they never scale with ortho size oddly.

## Marker projection

Each `SpawnPoint` in the level registers with the map (group scan on open). Every frame while open, for each spawn point: `marker.position = topdown_camera.unproject_position(spawn_point.global_position)` scaled from SubViewport coords to screen coords. Because camera and points are static in v1 this could be done once, but per-frame projection is cheap and stays correct if spawns ever move (e.g., future: spawn at vehicle).

Vehicles also register icons (tank/heli glyphs) via the same projection path, read-only — seeing "the heli is at the airfield" on the map is core sandbox joy and costs one extra loop.

## SpawnPoint node

`systems/spawning/spawn_point.gd` — `Marker3D` with exports: `display_name: String`, `enabled: bool`. Placed by hand in the level (Main Base, Hilltop, Airfield per 01). Spawn transform = marker transform; spawn yaw = marker yaw (aim them at something interesting).

## Flow

1. Map opens (`EventBus.deploy_map_toggled(true)`): mouse visible, markers build.
2. Choose a marker → selected (highlight ring, bracket reticle, name in footer). Either device works:
   - **Mouse:** click a marker. Clicking straight on **Deploy**, or double-clicking a marker, confirms.
   - **Controller:** either stick nudges the selection to the nearest marker in that direction; `deploy_confirm` (Enter / A) confirms. Selection is discrete — the stick picks between markers rather than driving a free cursor, because the map holds a handful of targets and pixel-hunting with a stick is miserable.
3. Confirm → `GameClient.request_spawn(spawn_point)` → RPC → server validates (point enabled, peer actually dead/undeployed — see 10) and spawns; the map closes when the replicated grant arrives:
   - If alive (M-opened): teleport? **No** — deploy while alive is disabled; Deploy button greyed out, map is recon-only. Death or session start are the only spawn moments. (Teleport-while-alive invites bug reports that aren't concepts.)
   - If dead/unspawned: server spawns infantry at the point, owning client closes map, captures mouse.
4. M/Esc closes map only when alive (recon mode); when dead the only way out is deploying.

## Acceptance criteria (M2 — built right after player, before vehicles)

- Session opens on map; deploying at each of 3 points spawns facing the marker's yaw.
- M while alive: recon map with live view (tank visibly settles, heli icon present), Deploy greyed, M/Esc returns cleanly with mouse recaptured.
- Die (dev damage key on M1 build) → map opens in KIA variant → redeploy works.
- Markers sit on their world points within a few px at 1080p and after a window resize.

## Open questions

- Ortho top-down of a map with a tall hill will parallax markers slightly (projection is exact, but the *terrain under* the marker reads offset if the point is elevated). Likely fine at ortho; check at Hilltop.
- KIA variant: add respawn delay timer (BF-style)? Trivial to add, zero concept value — deferred.
- M4: the ortho view frames the 200x200 play area (size 230), not the whole footprint including the 500 m firing range. 11 suggested the ortho size should follow the range strip, but including it would shrink the play area to a sliver and make the spawn screen useless. All spawn points are inside the play area, so the range is deliberately off-map here.
- M4: no vehicle icons yet — there are no vehicles until M5. The projection loop is written against the spawn-point group and takes vehicles the same way when they exist.
- M4: bots auto-deploy at the first enabled spawn point half a second after the map opens. Without it every headless test would sit on the deploy screen forever, since nothing clicks Deploy.
- M4: `client_ready` no longer deploys. A peer that has loaded the level is marked ready and waits for an explicit `request_spawn`, which is what makes the "peer is dead/undeployed" validation meaningful rather than a formality.
- **Corrected after M4:** player markers on the deploy map must be **squad/team only**, never all players. Showing every live player position on a spawn screen hands out enemy positions for free — it turns the wallhack that 10 lists as an accepted *gap* into a deliberate *feature*, which is a different thing entirely. The M7 backlog item is amended to match. There is no team or squad concept in the sandbox yet, so this stays deferred until one exists rather than shipping an all-players version and filtering it later.
- The live view does render soldier bodies, but at the map's scale they are not legible and no action is needed today: the ortho camera covers 230 m over ~720 px, about 3.1 px per metre, so a 0.8 m soldier is roughly **2 px** under a 55% dim overlay — and a spawn marker button spans ±24 m of world space, covering anyone standing near it. Verified by capture with a second player deployed and moving: nothing visible. This matters only as a warning: the moment someone makes players legible on this map — bigger icons, brighter bodies, a zoom — it becomes the all-players reveal ruled out above, and needs the squad/team filter first.
- **M7: unblocked by 13.** A team and squad concept now exists, so the squad/team-filtered player markers deferred above can be built. 13 also adds a second kind of destination to this screen — a living squadmate on foot is a spawn location for the rest of their squad — and replaces the deterministic fan-out ring with a randomised offset inside a radius. Spawn *points* remain shared by both teams; there is no team-filtered spawn list.
- **M7: the squad-filtered player markers deferred above are built** (see 13). Squadmates appear on the map as spawn destinations, drawn from `roster.squadmates()`. Worth noting *how* the rule is enforced: there is no all-players list being filtered, so no code path exists that could render an enemy marker. The warning above still applies to anything added later — a minimap, bigger icons, a zoom — which must draw from the same squad-scoped source rather than from the world.
- **M7: markers say what you are spawning onto, and whether you can.** Each squadmate marker carries an icon and label for what they are in — ▲ on foot, ■ TANK, ✕ HELI — because "spawn on Player 3" means something very different if Player 3 is flying. Availability is now shown rather than hidden: a squadmate whose vehicle is full stays on the map, **greyed and unselectable with `(full)`**, instead of silently disappearing. Disabled spawn points grey the same way. The previous behaviour — dropping unavailable targets from the list — made "full" and "not there" look identical, which is exactly the ambiguity that made the vehicle-replication bug so hard to read from the screen.
- **M7: the screen is unusable on a controller, and that is now a backlog item (08).** The flow above assumes a mouse at every step — markers are picked by clicking them — so a pad player can open the deploy screen and then has no way to choose a spawn or confirm one. The fix is a stick-driven target reticle with snapping onto the nearest marker, not a cursor emulation; `deploy_confirm` is already bound to Enter / A. Noting it here because the flow section, not just the input map, is what needs revising.
- **M7: the deploy screen works on a controller.** It was mouse-only at every step, so a pad player could open it and then had no way to deploy — the one screen where a controller was a dead end, and the first screen anyone sees.
  Selection is **directional, not positional**: a stick flick scores every selectable marker by `dot(direction) / distance` and takes the best, so it moves between targets rather than dragging a cursor over them. Disabled points and full squadmate seats are excluded from the candidate list, which means the greying already shown on screen and the reachability of a marker cannot disagree.
  A `DeployReticle` draws corner brackets around whatever is selected, on either device, so the current choice is legible without reading the footer. The footer itself now names the confirm button through `InputHints`, so it reads *Enter* on a keyboard and *A* on a pad.
- M7: the reticle is a child of `MarkerLayer`, and `_build_markers()` frees every child of that layer on each rebuild — which happens whenever a squadmate's state changes. It skips the reticle explicitly and re-raises it to the top of the draw order. Caught by a shutdown error in the test rather than by the assertions, which is worth remembering: a suite that only checks behaviour at one instant will miss lifetime bugs entirely.
- **M7: the deploy screen no longer opens on the frame you die.** `on_killed` now carries the death position, `DeathCam` holds on it for 2.5 s with a slow orbit, and only then does the map open. The flow above is otherwise unchanged — this sits in front of step 1. Respawning during the hold (which cannot happen today, but will once bots or auto-deploy exist) cancels it through `end_death_cam()`, so the countdown can never open the map over a live player.
- M7: the death cam carries a **KILLED IN ACTION** banner (`ui/hud/death_banner.gd`, a sibling of the HUD under the level's `UI` layer). It has to be a sibling rather than part of the HUD because the HUD hides itself whenever `my_entity` is null, which is exactly the state the hold runs in. It clears when the deploy screen opens, since that screen already carries its own KIA header — the two never show at once.
