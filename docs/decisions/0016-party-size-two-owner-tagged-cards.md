# ADR-0016: Party size fixed at 2; cards owner-tagged and stat-scaled

**Status:** Accepted
**Date:** 2026-06-07
**Deciders:** Michael (owner); Claude (build partner)
**Supersedes:** the *2–3 (prototype with 2)* party sizing in [ADR-0004](0004-shared-deck-character-tagged-cards.md). The shared-deck + character-tagged-cards model of 0004 is **retained and reaffirmed** here; only the party-size range is fixed.

## Context

Keeping the card system ([ADR-0017](0017-keep-cards-energy-and-return.md)) re-activates the deck-cycling tension from [ADR-0006](0006-draw-as-cooldown-model.md): more characters → more signature cards in one shared deck → each character's key cards resurface more slowly. With the stat layer ([ADR-0014](0014-stat-driven-characters.md)), the open question of whether a card's value is computed per-player at *play* time (ambiguous, multiplies cognitive load) or fixed at *draft* time (one number, one player) also needed settling.

## Decision

- **Party size is fixed at 2.** Two controllable characters per run.
- **Cards are owner-tagged.** Each card belongs to exactly one of the two characters (drafted by/for them); it is always played by that owner and always scaled by that owner's stats ([ADR-0014](0014-stat-driven-characters.md)). A card therefore shows **one number** and has **one legal player** — the stat math is resolved at draft time, not re-evaluated every turn.
- **Neutral cards** (either character may play) are kept few and **flat** (unscaled), so they never reintroduce routing math.
- **Shared deck, one hand, one energy pool** ([ADR-0004](0004-shared-deck-character-tagged-cards.md), [ADR-0017](0017-keep-cards-energy-and-return.md)) — unchanged.

## Options Considered

| Option | Verdict |
|--------|---------|
| Party of 3 | Rejected — ~25–30 card deck strangles signature-card cycling ([ADR-0006](0006-draw-as-cooldown-model.md)); bloats the board read. |
| Party of 1 | Rejected — loses party-composition variety and the two-pole (physical/magic) identity contrast. |
| Stat-gate cards by type, value computed at play time | Rejected for a 2-character party — ambiguous numbers, multiplied cognitive load, "routing" optimization erodes identity. |
| **Party of 2; owner-tagged, stat-scaled-at-draft cards** | **Chosen** — deck stays tight (~16–20 to start, cycles every 3–4 turns), one number per card, identity preserved. |

## Consequences

- The cooldown dial ([ADR-0006](0006-draw-as-cooldown-model.md)) works at this size instead of strangling signature skills; heavy per-character draw-guarantee machinery is likely unnecessary (a light "each active character has ≥1 play" insurance rule covers the dead-hand edge).
- Identity must come from **contrast** — pair a physical (STR/DEX) character with a caster (INT) rather than two similar builds; this two-pole split also covers the whole stat space.
- A single **downed** unit means 50% party strength for the rest of that fight, which makes [ADR-0011](0011-death-downed-and-hp-attrition.md)'s "downed ≠ permadeath, revive next encounter" **more** load-bearing, not less.
- Party-composition variety is delivered through class/race/stat choices across the two slots ([ADR-0015](0015-classes-races-leveling.md)), not through party size.
