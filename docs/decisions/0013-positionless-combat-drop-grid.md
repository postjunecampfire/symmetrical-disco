# ADR-0013: Positionless combat — drop the tactical grid

**Status:** Accepted
**Date:** 2026-06-07
**Deciders:** Michael (owner); Claude (build partner)
**Supersedes:** the *tactical grid combat* pillar of [ADR-0001](0001-card-driven-tactical-roguelite.md) (the run/roguelite and card pillars of 0001 still stand).

## Context

The original design carried three legs: Slay-the-Spire run structure, Fire-Emblem grid positioning, and cards as the action system. In review we concluded the grid is the single most expensive and most *optional* leg: it forces two simultaneous state systems (board + hand), drives pathfinding/terrain/facing complexity, and is the only part of the design that ever strained the engine choice. Slay the Spire demonstrates that positionless card combat is fully capable of carrying a deckbuilder. The owner's priority is a buildable, playable game; reducing scope where it doesn't cost fun is the goal.

## Decision

**Combat is positionless.** Remove the tactical grid: no tiles, movement, range, terrain, or facing. Combat resolves as a Slay-the-Spire-style abstract encounter (party vs. enemies, targets selected directly, no spatial layer). The map between fights remains the branching node structure from [ADR-0012](0012-run-structure-and-map.md) — "map structure" and "in-combat positioning" are separate decisions, and only the latter is removed here.

## Options Considered

| Option | Verdict |
|--------|---------|
| Keep the Fire-Emblem tactical grid | Rejected — highest complexity leg; not required for a successful deckbuilder; strained solo build scope. |
| Abstract row/lane layer (Darkest Dungeon / Banners of Ruin) | Rejected for now — still adds a positional system to balance; revisit only if combat feels flat. |
| **Fully positionless (StS-style)** | **Chosen** — collapses board+hand to a single hand-state system, removes pathfinding, proven by Slay the Spire. |

## Consequences

- The grid/pathfinding module (`src/grid/`, `grid_model`, `pathfinder`, tile-targeting) is **retired** from the active design. Existing combat/deck/effect/data-loader code is unaffected and carries forward.
- The differentiator shifts: with the grid gone, the game's distinctive hook is now the **RPG progression layer** (stats, classes, leveling — [ADR-0014](0014-stat-driven-characters.md), [ADR-0015](0015-classes-races-leveling.md)), not tactical positioning. This is a deliberate bet and should be validated like one.
- Turn order ([ADR-0010](0010-turn-order-strict-phases.md)) simplifies — strict player/enemy phases with no positional sub-ordering. `speed` remains unused data.
- The competitive frame moves toward the (crowded) StS-like space; the stat/class RPG layer is what must earn the differentiation.
