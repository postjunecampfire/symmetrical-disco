# ADR-0020: Card scaling ladder — flat → hybrid → multiplier

**Status:** Accepted (extends [ADR-0014](0014-stat-driven-characters.md) and [ADR-0016](0016-party-size-two-owner-tagged-cards.md))
**Date:** 2026-06-08
**Deciders:** Michael (owner); Claude (build partner)

## Context

[ADR-0014](0014-stat-driven-characters.md) made the innate floor and owned cards
scale with the owner's attack stat, and [ADR-0016](0016-party-size-two-owner-tagged-cards.md)
made owned cards stat-scaled while neutral cards stay flat. Today that scaling is
purely **additive**: a play deals `card_base + attack_stat (+ strength)`, and block
is `card_base + DEX`. Every card adds its stat exactly once (`×1`).

[ADR-0019](0019-eighteen-act-dungeon-progression.md) makes enemy power **geometric**
across 18 acts. Additive cards plus linear-ish leveling are **sub-geometric** — they
structurally fall behind a compounding curve. Per-turn offense is roughly
`a × (base + S)` (plays × (card base + scaling stat)); when `S` grows linearly, that
can't track a geometric enemy. A card that **multiplies the stat** turns a linearly
growing stat into geometrically growing output — the only same-shape answer to the
curve. So the card pool should itself *be* the power curve: you descend by drafting
bigger multipliers.

Related, already decided: innate **Defend now grants block = DEX only** (no flat
base — HANDOFF §5), making block an opportunity-cost stat investment rather than a
freebie. This ADR keeps offense and defense **symmetric** so that direction holds at
every magnitude.

Full taxonomy, example cards, crossover table, and pool weighting:
[docs/systems/card-scaling.md](../systems/card-scaling.md).

## Decision

- **Cards scale on a three-rung ladder, gated by depth:**
  - **Flat (A)** — base carries, stat auto-adds (`×1`, today's behavior). Common; the
    reliable floor; dominant in Tiers 1–2.
  - **Hybrid (B)** — base + an amplified stat (`×1.5–2.0`). Uncommon; the bridge;
    Tiers 3–4.
  - **Multiplier (C)** — near-zero base, stat `×2–4`. Rare and always guardrailed;
    the geometric ceiling; Tiers 5–6.
- **Both axes get the full ladder, symmetrically.** Offense scales the owner's
  `attack_stat`; defense scales DEX → block. A multiplier that exists for attacks has
  a mirror that exists for block, so the DEX-vs-damage balance invariant (HANDOFF §5)
  holds at the new magnitude.
- **One engine primitive expresses the whole ladder:** an optional `stat_mult` float
  (default `1.0`) on the `damage` and `block` effects —
  `scaled = base + floor(stat × stat_mult)`. Absent/`1.0` is exactly today's
  behavior, so every existing card and the pure-DEX Defend are unchanged. Neutral
  cards still ignore scaling ([ADR-0016](0016-party-size-two-owner-tagged-cards.md)).
- **Availability is crossover-gated.** A multiplier "Deal `m×S`" beats a flat
  "`base+S`" only when `S > base/(m−1)`; each multiplier is rarity- and pool-gated so
  its crossover lands in the tier where the player could have that stat. Big
  multipliers are never freely available early.
- **Class C is guardrailed by default** — Exhaust / X-cost / single-turn, with caps
  on per-turn multiplier stacking. Multiplicative offense is the mirror of the turtle
  exploit (runaway damage ↔ unkillable defense); poison (ignores block) stays the
  pressure valve on runaway *defense*.
- **Everything is data** — magnitudes, `stat_mult` values, rarities, and per-tier
  reward-pool weights are authored content ([ADR-0003](0003-data-driven-content-architecture.md)),
  not code.

## Options considered

| Option | Verdict |
|--------|---------|
| **Flat→hybrid→multiplier ladder, symmetric axes, via a `stat_mult` field** | **Chosen** — makes the deck the player's geometric answer to the curve; backward-compatible; ties offense/defense together. |
| Keep additive-only cards, scale via stats/relics alone | Rejected — additive can't track a geometric curve; late deckbuilding stops mattering. |
| Multipliers on offense only | Rejected — aggression outscales defense at depth, breaking the balance invariant by accident (any asymmetry must be a deliberate choice, not the default). |
| Multiplicative scaling with no guardrails | Rejected — the classic infinite-combo blow-up; Class C must be Exhaust/cost/cap-gated. |

## Consequences

- **New engine work:** add `stat_mult` to `Effect` (type-checked float, default 1.0)
  and apply it in the damage/block scaling path of `battle_state` — the single change
  that unlocks the multiplicative tier. Tracked as a task alongside the scaler.
- **Pairs with the scaler** ([ADR-0019](0019-eighteen-act-dungeon-progression.md)
  `EnemyScaler`): the enemy curve grows geometrically and the player's multiplicative
  cards are the same-shape counter. Tune them together.
- **New content axis:** per-tier reward pools weighted A→B→C with depth (drives the
  per-act draft pool the assembly task will read).
- **Extends, does not supersede,** ADR-0014/0016 — additive scaling remains the
  `stat_mult = 1.0` case.

## Open questions (tunable / deferred)

- **Rogue double-dip — DEFERRED TO PLAYTEST.** The Rogue's `attack_stat` IS dex and
  block also scales DEX, so one stat feeds both its offense and defense multipliers.
  Decision: leave the class as-is and let playtesting size it. If it proves too
  strong, prefer dampening/gating Rogue access to Class-B/C *defense* multipliers
  (not a hard removal) and/or leaning the both-ways DEX build into the **Duelist**
  promotion. Nerfing Rogue *attacks* is likely the wrong lever — it pushes toward the
  dex-turtle. Measure with the `dex-turtle` harness cohort. (See card-scaling.md §6.)
- **Ceiling height** — does Class C cap at `×3` (controlled) or allow `×4+` with heavy
  Exhaust (swingy, combo-y)?
- **Hybrid tier** — keep B as the mid-game default, or jump A→C at a hard tier line?
- **Defense parity** — exact mirror of offense, or hold defense multipliers slightly
  behind so aggression keeps a small, deliberate edge at depth?
