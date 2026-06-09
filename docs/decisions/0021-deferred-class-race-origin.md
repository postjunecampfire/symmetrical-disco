# ADR-0021: Deferred class — race-base origin, class chosen at Act 3, progression cadence

**Status:** Accepted (promotion *structure* refined by [ADR-0022](0022-class-progression-trees-ascension.md) — branch at 6/9/12, Ascension at 15; cadence here unchanged. Supersedes the *class-as-base-template* model of [ADR-0015](0015-classes-races-leveling.md); extends [ADR-0014](0014-stat-driven-characters.md), [ADR-0019](0019-eighteen-act-dungeon-progression.md), [ADR-0020](0020-card-scaling-ladder.md). **The *one-race-for-the-whole-pair / no-mix-and-match* rule is superseded by [ADR-0024](0024-act-structured-squad-recruitment.md)** — the run starts solo and recruits the second member via RNG at Act 2, reopening mixed-race pairs; everything else here stands.)
**Date:** 2026-06-08
**Deciders:** Michael (owner); Claude (build partner)

## Context

[ADR-0015](0015-classes-races-leveling.md) made a **class the base character template** (Fighter/Rogue/Mage hold the base stat block) with race as a small modifier, both chosen at character creation. You begin a run as a fully-formed, high-stat class.

The 18-act descent ([ADR-0019](0019-eighteen-act-dungeon-progression.md)) and the card-scaling ladder ([ADR-0020](0020-card-scaling-ladder.md)) want a **long power arc with high early stakes and slow creep**. Starting as a fully-formed class undercuts both: you begin powerful, so Act 1 has no stakes and the early curve is flat-topped. The owner wants Act 1 to feel like **a normal person entering a dungeon** — fragile, defined only by their race — who *becomes* a class through how they play.

This ADR **inverts race and class**: race becomes the low base template, class becomes a mid-run identity chosen at the end of Tier 1. Leveling and the existence of classes/races ([ADR-0015](0015-classes-races-leveling.md)) carry forward unchanged.

## Decision

- **Character creation picks RACE only — not class.** Party stays 2 ([ADR-0016](0016-party-size-two-owner-tagged-cards.md); a later reduction to 1 is possible, not decided). **You pick ONE race for the whole starting pair — no mix-and-match.** That makes the choice a real tradeoff: the race's stat-lean shapes *both* party members (you can't pair an Orc tank with an Elf mage), and per-character divergence comes later from stat allocation and the Act-3 class pick — a shared racial floor, divergent class ceiling. Race is the base stat template: **low and near-flat**, a "normal person." Illustrative lines (tunable in data), with a small allocation budget on top:
  - **Human** — 3 / 3 / 3 / 3 (balanced, flexible)
  - **Elf** — STR 2 / DEX 5 / CON 2 / INT 5 (fragile finesse/arcane lean)
  - **Orc** — STR 5 / DEX 3 / CON 4 / INT 2 (durable martial lean)
- **Acts 1–3 are the origin tier, classless.** You level (3 pts/level, [ADR-0015](0015-classes-races-leveling.md)), allocate stats, and draft from the **neutral + race** pool only — the flat Class-A cards ([ADR-0020](0020-card-scaling-ladder.md)). Pre-class, innate Strike scales off your **highest stat** (or a race default) until a class locks it.
- **End of Act 3: choose a class.** **Any race may pick any class** — race nudges via its stat-lean but never locks the choice. The pick is the Tier-2 power injection: a stat bump, it **locks your attack_stat**, and it **unlocks that class's tagged card pool** (hybrids/multipliers, [ADR-0020](0020-card-scaling-ladder.md)) for the rest of the run. It lands immediately before the Act 4 wall.
- **Promotions at the end of Acts 6, 9, 12, 15.** Each tier gate after the class pick gets a promotion beat (the existing Berserker/Guardian, Assassin/Duelist, Pyromancer/Sage branches, [ADR-0015](0015-classes-races-leveling.md)). **Five progression beats** — class @ Act 3 plus four promotions — feed the **five tier walls** (Acts 4 / 7 / 10 / 13 / 16). Tier 1 is the only stretch with no injection: you are just a person, leveling. Eligibility is now an **act/tier boundary**, not a raw level — `promotion_level` is revisited accordingly.
- **Power curve: Act 1 is a linearly-reduced entry, WITHIN the existing 18 acts.** The current enemy stat blocks stay the reference; the `EnemyScaler` ([ADR-0019](0019-eighteen-act-dungeon-progression.md)) baseline is recalibrated so the early bands scale them **down** (linear, exponent 1.0). E.g. baseline ≈ 8 → Act 1 ≈ ×0.25 (footman 7 dmg → ~2 vs a ~8-HP character), returning to ×1.0 (today's Act-1 strength) by ~Act 3, then climbing. **No literal "Act 0" act** — the A12 = 250 anchor and 6-tier math ([ADR-0019](0019-eighteen-act-dungeon-progression.md)) are untouched; "Act 0" is a concept (the reduced entry), not a 19th act.
- **Data model flips:** `races/*.json` become full base stat templates; `classes/*.json` become mid-run upgrade packages (stat bonus + unlocked card tag + attack_stat). Everything tunable lives in data ([ADR-0003](0003-data-driven-content-architecture.md)).

## Why the cadence lines up

| End of act | Beat | Then faces |
|---|---|---|
| Act 3 | **Choose class** (unlock pool + attack_stat + stat bump) | Act 4 wall (tier 2) |
| Act 6 | Promotion | Act 7 wall (tier 3) |
| Act 9 | Promotion | Act 10 wall (tier 4) |
| Act 12 | Promotion | Act 13 wall (tier 5) |
| Act 15 | Promotion | Act 16 wall (tier 6) |

Each power injection lands right before the difficulty step it's meant to clear — the "progression is a need" structure, now structural rather than incidental.

## Options considered

| Option | Verdict |
|--------|---------|
| **Race-base origin; class chosen end of Act 3; promotions at 6/9/12/15** | **Chosen** — high early stakes, slow creep, and an "become who you play" arc; beats align with the tier walls and the card-pool gating. |
| Keep class chosen at creation ([ADR-0015](0015-classes-races-leveling.md)) | Rejected — starts you powerful; no stakes in Act 1, flat early curve. |
| Add a literal "Act 0" tutorial act below Act 1 | Rejected — breaks the 18-act count and the A12 = 250 anchor; recalibrate the scaler within 18 instead. |
| Lock class to race (Orc → Fighter, etc.) | Rejected — kills the emergent "become who you play" identity; race nudges, never locks. |
| Let players mix races across the pair | Rejected — removes the tradeoff; cherry-picking complementary races (Orc tank + Elf mage) trivializes the origin choice. One race for the pair. |

## Consequences

- **Supersedes** the class-as-base-template model of [ADR-0015](0015-classes-races-leveling.md). Stat-point leveling, the class/race *concepts*, and the promotion branches carry forward; what changes is *when* class is acquired and *which* layer holds the base stats.
- **New work:** creation screen → race-only; run-controller class-pick at Act 3 + promotion beats at 6/9/12/15; draft-pool gating (neutral/race pre-class → class pool post-pick); data split (races = base templates, classes = overlays); `EnemyScaler` baseline recalibration for the Act-1 reduction.
- **Pairs with [ADR-0020](0020-card-scaling-ladder.md):** Tier 1 classless = neutral flat pool; the class pick is what opens the hybrid/multiplier cards — class-deferral and card scaling are the same gate.
- **Pairs with [ADR-0019](0019-eighteen-act-dungeon-progression.md):** the scaler baseline is the Act-1 reduction lever; linear (exponent 1.0) is confirmed as the default.
- **Higher early lethality:** CON 2–5 → very low HP. `hp_per_con` and the Act-1 reduction factor are the tuning levers.
- **Promotion timing** moves from raw level to act/tier boundaries — revisit `promotion_level` (and `meta_cash_out_acts`, already flagged).

## Open questions (tunable / deferred)

- Exact **race base stat lines** and the starting **allocation budget** (lines above are illustrative).
- **`hp_per_con`** and the **Act-1 reduction factor** — how brutal Act 1 is (playtest).
- Is the Act-3 class pick **free choice** or **recommended/gated** by your built stat profile?
- **Pre-class attack_stat** rule — highest stat vs a race default — confirm in implementation.
- What the **six promotion branches** actually grant (content) — still TBD, ties to [ADR-0020](0020-card-scaling-ladder.md).
- Possible later **party reduction to 1** (the "lone normal person").
