# ADR-0011: Death, downed units, and HP attrition

**Status:** Accepted
**Date:** 2026-06-05
**Deciders:** Michael (owner); Claude (build partner)

## Context

We needed to define what "death" means in the roguelite loop ([ADR-0001](0001-card-driven-tactical-roguelite.md)). The choices ranged from full Fire Emblem permadeath (a unit reduced to 0 HP is gone for the run) to a softer model. Two of our existing decisions make pure permadeath costly in *this* game specifically:

- **Shared, character-tagged deck** ([ADR-0004](0004-shared-deck-character-tagged-cards.md)): permanently deleting a unit mid-run would strip their cards from the deck, creating dead cards / a shrinking deck (which is also the cooldown dial, [ADR-0006](0006-draw-as-cooldown-model.md)) and discarding deckbuilding investment.
- **Small party (2–3)**: losing one unit means finishing the run at 50–66% strength, which death-spirals rather than creating recoverable tension.

The owner wants to keep the "don't let a unit drop" tension without those failure modes.

## Decision

A **hybrid** model:

- **Total Party Kill (TPK) ends the run.** If every party unit is downed within a single encounter, the run is over and restarts (the party-scale analog of Slay the Spire's death, [ADR-0001](0001-card-driven-tactical-roguelite.md)).
- **A single downed unit is NOT permadeath.** A unit reduced to 0 HP is **downed** — out for the remainder of the current encounter — but is **not deleted**. The unit and their cards remain part of the run.
- **Downed units return for the next encounter at low HP** (a data-driven revive value, [ADR-0003](0003-data-driven-content-architecture.md)). The cost of a death is paid through the **healing economy**, not by losing the unit.
- **HP carries across encounters** (attrition is a real run resource). Recovery between fights comes from: (a) a small **fixed partial heal after each combat**, and (b) dedicated **rest / event nodes** on the run map offering larger, often optional or trade-off healing.

## Options Considered

| Option | Verdict |
|--------|---------|
| Fire Emblem permadeath (dead = gone for the run) | Rejected — corrodes the shared deck (dead cards), death-spirals a 2–3 party, discards deckbuilding investment. |
| TPK-only, downed units fully revived each fight | Rejected as too soft — a single death would carry almost no weight. |
| **Hybrid: TPK ends run; downed unit revives next encounter at low HP; HP attrition + metered healing** | **Chosen** — keeps per-unit stakes, protects the deck economy, and makes HP a meaningful run resource. |

## Consequences

- Tactical tension is preserved (a dropped unit is a real setback) without the death spiral or dead-card problem; the deck stays intact ([ADR-0004](0004-shared-deck-character-tagged-cards.md)/[0005](0005-innate-strike-defend.md)/[0006](0006-draw-as-cooldown-model.md)).
- **HP becomes a cross-encounter resource**, giving the run an attrition arc and a concrete reason for the run/map layer to include **rest and event nodes**.
- Implies new mechanics to build in the (currently deferred) run/map layer: a **downed** state distinct from "removed"; **revive-at-low-HP** on the next encounter; **HP persistence** across encounters; a **post-combat partial heal**; and **rest/event node** types.
- The current single-encounter prototype already aligns: `BattleState.check_outcome()` treats an all-party-down state within the encounter as a loss = the TPK condition. The run-level pieces are future work.

## Open questions (tunable, resolve during balancing)

- The **revive HP** value for a downed unit returning next encounter (data-driven).
- The **post-combat partial heal** amount, and how rest/event nodes heal (fixed, %, or trade-off).
- Whether to additionally layer a temporary **injury debuff** on a revived unit for extra bite, or keep the cost purely in the HP/healing economy (start without; revisit).
- Whether a downed unit can be revived **mid-encounter** (prototype assumption: no — downed = out until the next encounter).
