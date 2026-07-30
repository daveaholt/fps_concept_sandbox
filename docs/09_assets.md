# 09 — Asset Strategy (placeholders now, real assets later)

## Position

**No external assets are required for any milestone M0–M5.** Every visual in the prototype is a CSG shape or primitive mesh with a flat `StandardMaterial3D`, built directly in the editor. You never block on art. But every entity is structured so that a real model can replace its placeholder later *without touching physics, logic, or scene wiring* — the swap is a leaf-node operation.

## The Visual-swap contract

Every entity scene separates three concerns that must never be mixed:

```
Tank (VehicleBody3D)                  # LOGIC + PHYSICS — never contains meshes
├── CollisionShape3D(s)               # PHYSICS — simple shapes, authored by hand,
│                                     #   deliberately NOT derived from the visual mesh
├── Visual (Node3D)                   # VISUAL — the ONLY place meshes live
│   ├── HullMesh (placeholder boxes)  #   ...entire subtree is replaceable
│   └── TurretVisual (Node3D)         #   visuals that must move with logic nodes
│       └── ...                       #   are driven BY them, see below
├── TurretYaw / Muzzle / ExitPoint …  # LOGIC markers — outside Visual, never replaced
└── VehicleCommon …
```

Rules that make the swap trivial:

1. **Scripts never reference nodes inside `Visual`** except through a small, listed set of hooks (below). Grep for `$Visual` should return almost nothing.
2. **Collision is authored, not generated.** Placeholder and final model share the same hand-made collision shapes (box hull, capsule player, skid boxes). A prettier tank does not get new collision unless deliberately re-tuned — art swaps must not change handling.
3. **Articulated parts follow logic nodes, not vice versa.** The turret's *logic* node (`TurretYaw`) rotates; its visual child is just parented under a `RemoteTransform3D` or re-parented into the logic node at swap time. Same for cannon pitch, heli rotor spin, wheels.
4. **Markers (`Muzzle`, `ExitPoint`, seat/camera markers) are logic**, positioned to match whatever the current visual is. Swapping in a longer-barreled model = move the Muzzle marker, done.

### Per-entity visual hooks (the whole replaceable surface)

| Entity | Hooks a real model must provide (as child node names/attachment) |
|---|---|
| Player | `Body`, `Head`, `WeaponProxy` (rigid placeholder soldier seen by remote players, 03; owner's camera culls it by render layer) |
| Tank | `Hull`, `Turret`, `Barrel` sub-visuals; optional `WheelL1..R3` for wheel spin. Eye markers: `GunnerEye` on the body, `DriverEye` on `TurretYaw/CannonPitch` |
| Helicopter | `Fuselage`, `MainRotor`, `TailRotor` (rotors spun by script via these names — the one allowed name-based lookup, resolved once in `_ready` with a null-safe fallback) |
| Terrain/props | free-form; not swap-structured (graybox is rebuilt, not reskinned) |

Two obligations apply to every crewed vehicle regardless of model:

- **A `GunnerEye` `Marker3D`** (logic node, outside `Visual`) giving the gunner's viewpoint. The camera rig reads the marker; a new model means dragging the marker, never editing a script.
- **Meshes that would block an occupant's view belong to the `vehicle_shell` group.** `VehicleCommon` moves that group to render layer 2 **while the active camera is geometrically inside the group's bounds**, and every camera in the project excludes layer 2 — the same mechanism the player already uses to hide its own body. Weapons stay out of the group: a gunner must still see the gun being aimed.

## Import conventions (for when assets arrive)

- Format: **glTF (.glb)** preferred; anything Godot 4.7 imports is acceptable.
- Scale: **1 unit = 1 meter**, real-world sizes (tank ≈ 3.5 m wide, heli rotor ≈ 11 m disc). Fix scale at import, never with node scale on physics bodies (scaled collision on RigidBody/VehicleBody misbehaves).
- Orientation: **−Z forward, Y up** at rest.
- Location: `assets/<entity>/` (e.g. `assets/tank/tank.glb` + textures). Placeholder-era this folder holds only shared flat-color materials (`assets/materials/`) so the graybox look is consistent and retint-able in one place.
- No animations needed, likely ever, for the vehicles: turret, rotors, and wheels are node-driven by script. A rigged infantry body (third-person / M5+) would be the first thing to actually need an AnimationPlayer.

## The Asset Viewer scene

`levels/asset_viewer.tscn` — a standalone scene, runnable directly (F6), for validating any imported model *before* it goes near an entity:

- Neutral ground grid, 3-point light rig, orbit camera, meter-stick reference object (1 m cube + 2 m capsule "person").
- Drop an imported scene under its `Subject` node: verify scale against the reference, verify −Z forward via a floor arrow, eyeball materials in the project's actual environment.
- A checkbox toggles a ghost overlay of each entity's collision shapes (pulled from the entity scenes) so you can see whether the model roughly fits the physics it will inherit.

Swap procedure once a model passes the viewer: open the entity scene → delete placeholder children of `Visual` → instance the `.glb` under `Visual` → rename/point the hook nodes (table above) → nudge markers (Muzzle etc.) to match → run the entity's existing acceptance criteria from its spec doc. No script edits expected; if a swap *does* demand a script edit, that's a contract violation worth fixing in the entity, not the asset.

## Milestone impact

- **M0** gains: `assets/materials/` shared placeholder materials, and the Asset Viewer scene (it's ~30 min and immediately useful for eyeballing CSG placeholders too).
- **M3/M4** gain one acceptance criterion each: "all meshes live under `Visual`; scripts pass the `$Visual` grep rule."
- Real asset swaps themselves are M5+ backlog items, entirely optional to the sandbox's goals.

## Open questions

- Wheel visuals for the tank: `VehicleWheel3D` can drive a wheel mesh child directly; with fake-tread boxes v1 skips it. Decide when a real tank model (with visible road wheels) shows up.
- A future *rigged, animated* infantry body would replace the rigid placeholder — and would also require per-bone hit-zone history per 11's flag. The two costs arrive together; budget them together.
- M0: the Asset Viewer's collision-ghost toggle walks any `CollisionShape3D` under `Subject` and draws `shape.get_debug_mesh()`, rather than pulling shapes from named entity scenes — there are no entity scenes yet, and the generic version works for anything dropped in.
- Post-M2: own-body hiding via `cull_mask` has to be applied **dynamically on possession**, not baked into the entity scene. `cull_mask` is a property of the camera and applies to every object on that layer, so putting all player bodies on a hidden layer means every camera hides every body and nobody can see anyone. Bodies now default to the visible layer and `possess()` moves only the owned body to the culled layer.
- Post-M5: the tank's turret and barrel meshes hung under holder nodes named `TurretVisual` / `BarrelVisual`, which is not what the `Visual` contract says and is not what a `$Visual` swap would find. Both are now named `Visual` under their own parents. The M0 asset check had been reporting "2 meshes outside Visual" the whole time — it was doing its job; nobody was reading its output once M0 closed. Worth re-running the earlier milestone checks, not just the current one.
- M7: the helicopter canopy is now an actual transparent material (`transparency = 1`, albedo alpha 0.28) rather than an opaque blue box. It read as glass from outside either way, but any camera placed *behind* it — the gunner station — had 80% of its forward view filled by a solid box. Placeholder art gets away with a lot, but not with lying about which surfaces you can see through.
- **M7: the first gunner-camera fix was placeholder-shaped and would not have survived a model.** It worked by seating the eye *inside* the canopy, which clears the view only because a `BoxMesh` has no interior — every face backface-culls when seen from within. A modelled cockpit has real interior geometry and a real fuselage, so the trick evaporates exactly when the art improves. It was also a contract violation on its own terms: the eye lived in an `@export var` rather than in the `Marker3D` this doc already required, so a swap would have demanded a script edit.
  Replaced by the durable mechanism, which was already in the codebase — `player.gd` hides its own body by moving its meshes to render layer 2, which every camera's `cull_mask` excludes. Vehicles now do the same for their `vehicle_shell` group. The tuned canopy transparency is kept because it is correct independently: a real model ships glass as glass.
- M7: `groups` in a `.tscn` belongs in the **node header** (`[node name="Hull" … groups=["vehicle_shell"]]`), not on a property line below it. Written as a property it is silently ignored — no error, no warning, the group is simply empty. The layer-swap tests still passed against that empty set, because a loop over nothing violates nothing; only the separate "tags at least one mesh" assertion caught it. Any test that iterates a collection needs a companion assertion that the collection is not empty.
- **M7: hiding the shell for any first-person camera made both vehicles disappear from under their own crew.** The tank's gunner eye sits at y 2.45 against a shell that tops out at 1.83 — an exposed commander's position, outside the hull — so blanking the hull left the gunner floating above nothing. Hiding is now decided by geometry rather than by seat: the shell is culled only while the **active camera is inside the shell's own bounds**. That answers both vehicles correctly with no per-vehicle rule (tank gunner outside → drawn, helicopter gunner and pilot inside → culled) and keeps answering correctly when a model changes the bounds. `verify_gunner_view` asserts the outcome — visible with nobody aboard, visible again after the occupant leaves, hidden if and only if the eye is enclosed.
