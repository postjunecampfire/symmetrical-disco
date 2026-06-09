# ADR-0022: Class progression — branching trees at Acts 6/9/12, universal Ascension at Act 15

**Status:** Accepted (refines the promotion *structure* of [ADR-0021](0021-deferred-class-race-origin.md); supersedes the fixed promotion branches — Berserker/Guardian, Assassin/Duelist, Pyromancer/Sage — of [ADR-0015](0015-classes-races-leveling.md). Extends [ADR-0019](0019-eighteen-act-dungeon-progression.md), [ADR-0020](0020-card-scaling-ladder.md).)
**Date:** 2026-06-08
**Deciders:** Michael (owner); Claude (build partner)

## Context

[ADR-0021](0021-deferred-class-race-origin.md) set the cadence: class at the end of Act 3,
then **promotions at the end of Acts 6, 9, 12, 15**, each feeding the tier wall after it.
It left *what the promotions are* as content (a flagged open question). [ADR-0015](0015-classes-races-leveling.md)
sketched a single pick-1-of-2 per class (Berserker/Guardian, Assassin/Duelist, Pyromancer/Sage).

An initial design fleshed this into a full binary tree per class but placed the first **choice**
at Act 9 (a Journeyman → Fighter "formalize" lead-in occupied Acts 3 and 6). In review the owner
found that **too slow** — the player makes no real identity decision until halfway through an
18-act run. Separately, the owner wanted Act 15 to be a **power payoff** ("Ascended X": a flat
boost to all cards plus a player "Ult"), not another fork.

## Decision

- **Branching choice tree, shifted up.** Class is chosen at Act 3 ([ADR-0021](0021-deferred-class-race-origin.md), unchanged).
  A **pick-1-of-2** lands at the end of **Acts 6, 9, and 12** — archetype, specialization, capstone —
  forming a binary tree **1 → 2 → 4 → 8** per line. The Journeyman/Acolyte/Pickpocket "initiate"
  name now flavors the **pre-Act-3 race-only "normal person"** ([ADR-0021](0021-deferred-class-race-origin.md)),
  not a separate beat — removing the linear lead-in that made it slow.
- **Act 15 is universal Ascension, not a branch.** Whatever Act-12 capstone you reached becomes
  **"Ascended &lt;Capstone&gt;"**: (1) a **flat power bump to every card in the run deck**, applied as a
  `stat_mult` step per [ADR-0020](0020-card-scaling-ladder.md), and (2) a **signature "Ult" card**
  appended to the deck. The five-beat cadence and tier-wall alignment of
  [ADR-0021](0021-deferred-class-race-origin.md) are unchanged — only the **nature** of the Act-15
  beat changes (universal step-up vs another 1-of-2).
- **Three lines, 24 capstones, 24 Ults.** Fighter (STR) / Mage (INT) / Rogue (DEX); themes lean on
  *Fire Emblem: The Sacred Stones* names and map to existing combat mechanics. The full tree, the
  24 capstone/Ult pairs, and the data model live in
  [`docs/systems/class-progression.md`](../systems/class-progression.md) with a visual companion at
  [`docs/systems/class-progression-matrix.html`](../systems/class-progression-matrix.html).
- **Data.** Progression becomes a per-line tree keyed by act boundary (node = stat bonus +
  unlocked card ids + parent; capstones also carry `ult_card_id` + `ascension_stat_mult`),
  hosted by the existing `eligible_promotions / apply_promotion` plumbing generalized to walk the
  tree. Ascension is a distinct code path (apply boost to owned cards + append the Ult), not a
  promotion branch. Everything tunable is data ([ADR-0003](0003-data-driven-content-architecture.md)).

## Why the cadence still lines up

| End of act | Beat | Choice | Then faces |
|---|---|---|---|
| Act 3 | **Class** (Fighter/Mage/Rogue) | 1 of 3 lines | Act 4 wall (tier 2) |
| Act 6 | **Archetype** | 1 of 2 | Act 7 wall (tier 3) |
| Act 9 | **Specialize** | 1 of 2 | Act 10 wall (tier 4) |
| Act 12 | **Capstone** | 1 of 2 | Act 13 wall (tier 5) |
| Act 15 | **Ascension** (Ascended X) | universal — no branch | Act 16 wall (tier 6) |

Each injection still lands right before the difficulty step it clears; the difference from
[ADR-0021](0021-deferred-class-race-origin.md) is that the early beats are now real **choices**
and the final beat is a guaranteed **power spike**.

## Options considered

| Option | Verdict |
|--------|---------|
| **Branch at 6/9/12; universal Ascension at 15** | **Chosen** — a real identity choice every beat through Act 12; Act 15 is a clean power payoff and authors 8 (not 16) capstones per line. |
| Branch at 9/12/15 with a Journeyman→Fighter lead-in (initial design) | Rejected — first choice at the halfway mark; felt too slow. |
| Make Act 15 a fourth 1-of-2 branch | Rejected — owner wants a guaranteed power spike (boost + Ult), not more divergence, at the climax. |
| One Ult per line (3) or per archetype (6) | Rejected — owner chose **one Ult per capstone** (24) for maximum build identity. |

## Consequences

- **Refines** the promotion structure of [ADR-0021](0021-deferred-class-race-origin.md) (cadence
  intact; beats are now branch/branch/branch/Ascension) and **supersedes** the specific promotion
  branches of [ADR-0015](0015-classes-races-leveling.md). The class-promotion *plumbing* already
  built (P3·06: `eligible_promotions/apply_promotion`) carries forward, generalized to a tree walk
  plus an Ascension path.
- **New content:** 3 line roots + 6 archetypes + 12 specializations + 24 capstones + 24 Ult cards,
  with per-node stat bonuses and unlocked card ids — all data.
- **New code:** tree-walk promotion at Acts 6/9/12; Ascension step at Act 15 (apply
  `ascension_stat_mult` to owned cards, append `ult_card_id`); progression data schema + loader/validation; GUT tests.
- **Pairs with [ADR-0020](0020-card-scaling-ladder.md):** Ascension reuses the `stat_mult` ladder,
  so the boost compounds with attack-stat scaling rather than adding a parallel system.
- **Pairs with HANDOFF §5 balance work:** two capstones (Plaguebringer / Venomancer) terminate in
  block-ignoring poison — intentional anti-turtle payoff lines.

## Open questions (tunable / deferred)

- **Ascension card-boost magnitude** (the flat `stat_mult` step) and **Ult scaling** (fixed vs scales with the boost / attack stat).
- **Eligibility** — act/tier boundary vs accrued level (revisit `promotion_level`, per [ADR-0021](0021-deferred-class-race-origin.md)).
- **Per-node stat bonuses** and whether a branch pick is **locked for the run** (assumed yes).
- Whether **Act 6** should ever offer a no-choice "formalize" fallback (currently always a choice).
- Ult **card design** (cost, draw shape) — they live in `data/cards/` like any card.
