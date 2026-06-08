# ADR-0015: Classes, races & stat-point leveling

**Status:** Accepted
**Date:** 2026-06-07
**Deciders:** Michael (owner); Claude (build partner)
**Relates to:** [ADR-0014](0014-stat-driven-characters.md) (stats), [ADR-0016](0016-party-size-two-owner-tagged-cards.md) (party of 2).

## Context

The stat system ([ADR-0014](0014-stat-driven-characters.md)) needs a way for characters to acquire identity and grow it over a run. A roguelite restarts often, so identity that only arrives late (pure Fire-Emblem promotion) risks never paying off — many runs end before it lands. Identity should be available up front and *amplified* later, not first granted late.

## Decision

- **Class chosen at run start.** The player picks a class archetype keyed to a primary stat — a **STR**, **DEX**, or **INT** class — for each party slot. This front-loads identity from turn one.
- **Cards flesh out the archetype.** Between class changes, drafted cards ([ADR-0012](0012-run-structure-and-map.md) rewards) deepen and specialize the chosen archetype.
- **Class promotion later, as an amplifier.** After a threshold (a number of levels, or at the end of an act — exact trigger tunable) a character may promote/branch into a new class or bonus, Fire-Emblem style. Promotion *amplifies* an identity the player already has; it is never the first time they get one.
- **Race = light modifier.** Race (fantasy staples) applies a **small stat modifier** plus **~one custom card**. It is flavor-plus-nudge, not a primary build axis.
- **Leveling = player-allocated stat points.** On level-up the player allocates a small pool of points (working default **3 per level**) across STR/DEX/CON/INT. Growth is a player choice, not fixed/random.

## Options Considered

| Option | Verdict |
|--------|---------|
| Generic start, class only via mid-run promotion (FE) | Rejected — identity arrives too late for a restart-heavy loop. |
| Fixed/random stat growth (FE growths) | Rejected — removes a meaningful per-level decision. |
| Race as a full build axis | Rejected — over-weights a cosmetic-leaning choice; kept as a light modifier. |
| **Class at start + promotion as amplifier; player-allocated points; race as light mod** | **Chosen** — identity up front, deepened by cards, amplified by promotion. |

## Consequences

- Run-start choices (class ×2, race ×2, then stat allocation) provide party-composition variety that the fixed party-of-2 ([ADR-0016](0016-party-size-two-owner-tagged-cards.md)) otherwise gives up.
- New data entities: class definitions (primary stat, starting kit, promotion options), race definitions (stat mod + custom card), and a level/stat-allocation model — all data ([ADR-0003](0003-data-driven-content-architecture.md)).
- Exact numbers (points per level, promotion threshold, per-class kits, XP/level curve) are **tunable, set during balancing**.
- Class/race/level state must persist in `RunState` across nodes ([ADR-0012](0012-run-structure-and-map.md)).
