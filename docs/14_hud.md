# 14 — HUD

Written at M7, after the HUD had been grown one label at a time since M1 and nobody had ever said what belonged on it. `04` defines the *contract* — the HUD polls the possessed node once a frame and asks it for values, and never reaches into simulation state — and that contract is unchanged. This doc defines the *layout and the language*.

## Colour language

Three colours carry meaning everywhere on screen. Nothing else may use them.

| Colour | Means |
|---|---|
| **Blue** | your team |
| **Green** | your squad, and your own health |
| **Red** | the enemy |

**Squad colours (Red/Yellow/Blue/Green from `13`) stop at the lobby.** They exist so four squads can be told apart while picking a slot; once the match starts they are noise, because in play the only questions are *is this mine, is this my squad, is this the enemy*. A player in Yellow squad does not want to remember that Yellow is friendly — they want blue to mean friendly. This is a deliberate reversal of the M7 deploy-map behaviour, which tinted squadmate markers by squad colour.

## Layout

```
┌──────────────────────────────────────────────────┐
│                                                  │
│                        ✛                         │
│                   (prompt / banner)              │
│                                                  │
│                                    SQUAD         │
│                                    Alder  ▓▓▓▓░░ │
│   25          24                   Brack  ▓▓▓▓▓▓ │
│   ▓▓▓▓▓▓▓▓    ▓▓▓▓▓░░░             Cobb   ▓▓░░░░ │
│  ┌──────────┐                                    │
│  │          │                      Rifle         │
│  │ minimap  │                      30 / 120      │
│  │          │                      ▓▓▓▓▓▓▓░░░    │
│  └──────────┘                                    │
└──────────────────────────────────────────────────┘
```

**Bottom left — situation.** The minimap in the corner. Directly above it, one ticket count per team: your number in blue, theirs in red, each with a bar beneath it that is full at `START_TICKETS` and shrinks as tickets are spent. The bar is the thing read at a glance; the number is for when you care about the exact figure.

**Bottom right — self.** Current weapon, ammo as `loaded / reserve`, and your health as a green bar. Above it, your squad: one row per squadmate, name and a health bar each. Placeholder names are fine.

**Centre — the moment.** Reticle, hit marker, hull indicator (tank sight only), interaction prompt, kill banner, and the reload state — `RELOADING` while it runs, `RELOAD [B]` when the magazine is dry and there is reserve left. Reload feedback sits under the reticle because it is the one thing you need while looking down the sights.

**Top centre — the match.** Result banner only.

**No control hints.** They were useful while bindings were moving weekly; they are clutter now, and `02` is the reference.

## In a vehicle

The bottom-right block swaps to describe the seat, not the soldier: the seat's weapon (cannon, rockets, minigun) with its own readout — reload for the cannon, heat for a minigun, salvo for rockets — and **vehicle** health in place of player health. The bottom-left half does not change; tickets and the minimap mean the same thing whatever you are sitting in.

## Minimap

Drawn, not rendered. It is a 2D widget fed explicit markers, **not** a second camera on the world — partly for cost, since it is always on, and mostly because a rendered view shows whatever is in frame and would hand out enemy positions by construction. Drawing it means it can only ever show what it is given.

What it shows:

- **Squadmates** — green, from `roster.squadmates()`, never from a scan of the world.
- **You** — green, with a facing indicator.
- **Spawn points** — neutral.
- **Vehicles you or your squad occupy** — green.
- **Enemy gunshots** — red, transient. See `07`: firing reveals you, as a position at a moment rather than a tracked entity. The ping never moves after it appears.

North-up. Enemies are never drawn from world state, only from gunshot events.

## Dependencies this doc creates

Three things the HUD wants that do not exist yet, each its own piece of work:

1. **Ammo.** `WeaponDef` has fire mode, rpm and draw time; `InfantryState` has no ammo field at all — weapons are infinite with no reload. Magazine, reserve and a reload action land inside `InfantrySim.simulate`, the pure step function the server and the predicting client both run, so it has to be deterministic and replay-safe or reconciliation breaks. **Being built before the HUD pass**, so the readout is never a placeholder that lies.
2. **Player names.** `Roster` holds peer and slot. The squad list needs a name per slot, replicated with the roster.
3. **Kills and deaths.** Tracked per player server-side, replicated, for the after-battle report below.

## After-battle report (stretch)

At match end, in place of or beneath the result banner: every player, their kills and their deaths, grouped by team. Wants dependency 3, and reads better with 2.

## Open questions

- M7: layout settled as minimap bottom-left, self bottom-right. The alternative considered was one continuous bottom-left block; two independent corners won because each can grow without shoving the other, which is exactly how the single hand-positioned panel drifted in the first place.
- M7: `START_TICKETS` is 25, so a ticket bar has 25 discrete steps. Fine at that number; if tickets ever scale with player count the bar stays honest but the number does the work.
- M7: squad health bars need a squadmate's health client-side. Snapshots carry `h` per player entity, so a living squadmate is readable; a **dead** one has no entity at all, which the list has to render as dead rather than as missing — the same "absent and unavailable look identical" trap already recorded in `07`.
