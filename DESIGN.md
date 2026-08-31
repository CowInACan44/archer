# Archer — Kingdom Growth Design

Living design doc for the pawn/kingdom-building layer on top of the existing
tower-defense core. Update this as the design changes — don't let it rot.

## Core loop (new)

The game splits into alternating **Day** and **Night** phases, counted by a
day number:

- **Day** — peaceful. Manage pawns: assign them to gather resources or send
  them to buildings to become units. Resource nodes (trees, rock/mineral
  fields) have a chance to spawn fresh at the start of the day.
- **Night** — combat. Waves attack (today's wave system, reframed as
  "tonight's wave"). Kills earn gold/wood/meat. Rock/mineral nodes have a
  chance to spawn at night instead of day (so day = wood-leaning, night =
  stone-leaning, per the request).
- Every **5th or 7th night** is a horde: more enemies, at least one
  upscaled enemy with its own boss health bar.
- Pawn **scouts** (unlocked later) warn which side of the map the horde is
  coming from before it arrives.

This replaces "wave N" as the pacing unit for a lot of systems — enemy
scaling, resource-node spawn chance, and eventually scout warnings should
key off the day count instead of (or alongside) the wave count.

## Resources

- Existing: **Gold**, **Wood**
- New: **Stone** (mined), **Meat** (from sheep)
- Later: **Iron**, **Tin** (refined from Stone? or their own nodes — TBD
  once Stone gathering exists and we see how the pacing feels)

## Pawns

Pawns are a resource you manage, not a currency you spend outright:

- Spawned by **Houses** (see below), up to each house's capacity.
- An idle pawn can be **assigned** to:
  - Gather from a resource node (walk out, harvest, return, repeat)
  - Walk to a conversion building and become a different unit (see below)
- Managing pawns (who's gathering what, who's training where) is itself
  the day-phase gameplay.

## Buildings

| Building    | Holds/Produces                                  | Notes |
|-------------|--------------------------------------------------|-------|
| **House**   | Houses pawns (capacity, not a training queue)     | Player-placed. Starts holding only 2 pawns; capacity is raised through the incremental tree, up to 4. Same sprite at every capacity tier — only the number goes up, no new art needed. |
| **Barracks**| Converts pawns → **Warriors** and **Spearmen**    | Ground melee units |
| **Archery** | Converts pawns → **Archers**                      | Ranged, patrol in packs per the original vision |
| **Monastery**| Converts pawns → **Monks**                       | Healers |

Each conversion building has its own **conversion rate** — a fixed time per
pawn to finish becoming a unit, independent of the other buildings' rates.

All buildings reuse the **Yellow faction** assets already in the project
(Yellow Buildings, Yellow Units) — no new art needed for the first pass.

## Unlock pacing

Building placement isn't available from the start — it's unlocked through
the existing incremental/merchant system, gated by gold earned, kills, and
keeping towers alive:

1. Early game (today): towers + walls only, as now.
2. First unlock, a few towers in: a **placement area** opens up and you can
   place your first House. This is the "even start small" option — it
   doesn't have to wait for the full octagon.
3. Placing that first House unlocks a **new incremental tree**: chance for
   trees to spawn at day start, chance for rocks/minerals to spawn at
   night, etc.
4. Full octagon (all 8 towers + walls/gates on all 4 cardinal directions)
   unlocks the "real" kingdom-growth game — more building types, bigger
   placement area.

## UI

A new widget (separate from the existing Stats/Inventory/Options tabs)
showing:

- Current pawn count (idle / gathering / training, by building)
- Active unit counts by type (Warriors, Spearmen, Archers, Monks)
- Click a building → send N idle pawns to it

## Build order (proposed)

These build on each other, so this is also roughly the dependency order.
Each phase should be shippable and testable on its own before starting the
next one — that's the lesson from this session's UI work: half-built
systems compound into bugs that are hard to untangle later.

1. **Day/Night cycle** — day counter, Day/Night state machine, reframe the
   existing wave system to fire during Night. This is the temporal spine
   everything else keys off (resource spawns, scouts, hordes), so it goes
   first even though it has no pawns in it yet.
2. **Houses + pawns** — placement (player picks the spot, constrained to
   the unlocked area), pawn spawning up to capacity, capacity upgrade via
   the incremental tree, idle pawns visible and assignable (even if
   "assign" just means "walk to a marked resource node" at first).
3. **Resource nodes** — trees and rock/mineral fields as world objects
   with day/night spawn chance; pawns gather from them into Wood/Stone.
4. **Conversion buildings** — Barracks/Archery/Monastery, each with its own
   conversion rate, turning pawns into the four unit types.
5. **Pawn/unit management widget** — the UI to see and direct all of the
   above at a glance, once there's enough state to actually need it.
6. **Horde nights + scouts** — boss-tier enemy with its own health bar
   every 5th/7th night, pawn scouts warning of horde direction.

## Open questions (flagging rather than guessing)

- House capacity upgrade cost/curve — same merchant-gold model as tower
  upgrades, or its own resource (Stone?) once that exists.
- Whether idle pawns need explicit player-driven pathing (click pawn, click
  destination) or an auto-assign system (pawn picks nearest open node).
  Auto-assign is far less work and probably reads fine for a first pass.
- Do Warriors/Spearmen/Archers actively patrol and intercept enemies before
  they reach the walls, or do they only fight at the wall line like towers
  do now? Changes the AI a fair amount.
- Iron/Tin: refined from Stone, or their own map resource? Deferred until
  Stone gathering exists and we can see how that resource loop feels.
