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
| Tank | `Hull`, `Turret`, `Barrel` sub-visuals; optional `WheelL1..R3` for wheel spin |
| Helicopter | `Fuselage`, `MainRotor`, `TailRotor` (rotors spun by script via these names — the one allowed name-based lookup, resolved once in `_ready` with a null-safe fallback) |
| Terrain/props | free-form; not swap-structured (graybox is rebuilt, not reskinned) |

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
