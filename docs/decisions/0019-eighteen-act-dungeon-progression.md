# ADR-0019: Eighteen-act dungeon progression & power curve

**Status:** Accepted (supersedes the single-act v1 scope of [ADR-0012](0012-run-structure-and-map.md))
**Date:** 2026-06-08
**Deciders:** Michael (owner); Claude (build partner)

## Context

[ADR-0012](0012-run-structure-and-map.md) scoped v1 to **one act** (~8 rows + a single boss) and explicitly **deferred multi-act maps**. The run/map layer, leveling ([ADR-0015](0015-classes-races-leveling.md)), HP attrition ([ADR-0011](0011-death-downed-and-hp-attrition.md)) and meta-progression ([ADR-0018](0018-meta-progression-exit-package.md)) are now built and tested against that single act. The dungeon needs depth: a long, escalating descent the player is **not expected to clear in one run**, where meta-progression ([ADR-0018](0018-meta-progression-exit-package.md)) is what carries gains across deaths.

This ADR adopts an **18-act dungeon** with a defined power curve. It does not change combat, cards, or the per-act map model from ADR-0012 — it stacks 18 of those acts into one descent and defines how difficulty scales between them. Enemy *rosters* per act are deliberately out of scope here (this ADR fixes the **structure and curve**, not which monsters appear — see [act-progression.md](../systems/act-progression.md)).

## Decision

- **The dungeon is 18 acts ("floors"), played as a continuous descent.** Each act is one ADR-0012 branching map terminating in a boss. Clearing an act's boss descends to the next act; a TPK ends the run (meta-progression persists, [ADR-0018](0018-meta-progression-exit-package.md)).
- **Difficulty steps up every act and ramps noticeably every 3 acts.** The 18 acts form **6 tiers of 3 acts**. Within a tier, act-to-act difficulty rises gently; crossing into a new tier is a deliberate step-change (a "gate").
- **Boss level is the power-curve anchor.** Each act's boss has a *level* (a single scalar that scales enemy stats; the level→stat mapping is defined in [act-progression.md](../systems/act-progression.md) and tuned in data, not here). The benchmark, fixed by the owner: **the Act 12 boss is level 250.** All other acts are calibrated against that anchor.
- **The run is meant to be near-unwinnable in a single attempt.** Player power (leveling + drafted deck + relics/boons) is tuned to fall behind the curve as tiers climb — especially across tier gates — so deep acts are an aspirational, meta-progression-gated goal, not a first-run expectation.
- **Structure escalates with depth, not just stats.** Deeper acts add rows, more elites, and heavier late-row combat weighting (defined in [act-progression.md](../systems/act-progression.md)). The single-act map generator ([ADR-0012](0012-run-structure-and-map.md) / `map_generator.gd`) is extended to take a **per-act config**; the generation algorithm is unchanged.
- **Everything tunable lives in data.** Boss levels, enemy level bands, rows/widths, and node weights per act are authored content in `/data` ([ADR-0003](0003-data-driven-content-architecture.md), AGENTS.md) — **no balance magic numbers in code.**

## Benchmark curve (boss level by act)

The owner-anchored curve (Act 12 = 250). Tiers scale ~2.3–2.4× capstone-to-capstone; tier-gate jumps (+41–56%) exceed within-tier steps (+22–32%). Full per-act bands and structure in [act-progression.md](../systems/act-progression.md).

| Tier | Acts (boss level) |
|------|-------------------|
| 1 | A1 · 5  →  A2 · 11  →  A3 · 18 |
| 2 | A4 · 28  →  A5 · 36  →  A6 · 44 |
| 3 | A7 · 62  →  A8 · 82  →  A9 · 105 |
| 4 | A10 · 150  →  A11 · 198  →  **A12 · 250** |
| 5 | A13 · 360  →  A14 · 465  →  A15 · 580 |
| 6 | A16 · 820  →  A17 · 1050  →  A18 · 1300 |

## Options considered

| Option | Verdict |
|--------|---------|
| **18 acts, 6 tiers, data-driven curve anchored at A12=250** | **Chosen** — gives a long escalating descent with a clear "ramp every 3 acts" cadence and a fixed calibration point. |
| Keep one act, scale only enemy level | Rejected — no sense of descent/progression; wastes the map model. |
| 18 acts with smooth (no-tier) exponential scaling | Rejected — the owner wants a *noticeable* ramp every 3 acts, not a smooth slope. |
| Pure linear boss levels to 250 by A12 | Rejected — too shallow late; can't reach an "almost impossible" deep game. |

## Consequences

- **Supersedes** the "one act, multi-act deferred" decision in [ADR-0012](0012-run-structure-and-map.md). ADR-0012's node model, rewards, rest/event/relic systems carry forward unchanged — they now repeat across 18 acts.
- **New work:** an act-progression data set (`/data/acts/…`), map generator taking a per-act config, an enemy level→stat scaler, run-controller act-advance flow, and tests for the curve/structure invariants. These are tracked as tasks (Asana, "Unnamed Game").
- **Meta-progression matters more:** because a single run can't reach A18, the exit-package/boon model ([ADR-0018](0018-meta-progression-exit-package.md)) is the primary axis of long-term progress. Expect to revisit meta-pacing (`meta_cash_out_acts`) against the new depth.
- **Enemy content is decoupled:** rosters/intents per act are authored separately against the level bands here; this ADR won't need revising when monsters are added.

## Open questions (tunable / deferred)

- The exact **level→enemy-stat** function (linear vs. mild-exponential HP/damage growth) — set during balancing in data.
- Where **meta cash-out** should sit now that depth is 18 (currently `meta_cash_out_acts: 9`).
- Whether tier gates also introduce **mechanical** modifiers (e.g. new statuses, act modifiers) on top of stat scaling — ~~deferred~~ **implemented (M3)**: each tier has a mechanical identity and its own boss kit — see [act-progression.md §4b](../systems/act-progression.md).
- **Act rosters** (which enemies per act/tier) — ~~deferred~~ **implemented (M3)** via `tier_pools` in `data/acts/act_progression.json`.
