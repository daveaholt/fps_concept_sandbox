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
2. Click a marker → selected (highlight ring, name in footer). Clicking straight on **Deploy**, or double-clicking a marker, confirms.
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
- Open, and a consequence of the above that the live view already has: the top-down `SubViewport` renders the real world, so enemy soldiers are visible on it as moving bodies even with no markers drawn. Recon mode (M while alive) is therefore currently an enemy-position reveal by construction. Options are to cull soldier bodies from the deploy camera by render layer — the same mechanism as own-body hiding in 09 — or to accept it as another documented sandbox gap alongside 10's interest-management note. Unresolved.
