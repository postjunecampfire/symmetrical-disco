# ADR-0012: Run structure & map (v1)

**Status:** Accepted
**Date:** 2026-06-06
**Deciders:** Michael (owner); Claude (build partner)

## Context

The combat loop is built and test-proven, and single-encounter telemetry confirmed what playtesting suggested: in an isolated fight with nothing to preserve HP for, pure offense is correct and one repeatable card dominates. The decisions the design actually cares about — when defense is worth a turn, whether deck variety matters, how attrition shapes choices, whether a spammable card stays dominant across many fights on one HP bar — **only exist once there is a run.** This ADR defines that run/map layer, wrapping the combat we have, per the Slay-the-Spire run model ([ADR-0001](0001-card-driven-tactical-roguelite.md)) and the attrition/death rules ([ADR-0011](0011-death-downed-and-hp-attrition.md)).

## Decision (v1 scope)

- **Branching node map, Slay-the-Spire style.** One **act** for v1 (~8–10 nodes deep with branching paths), terminating in a single **boss**. The player chooses a path through the branches.
- **Node types (v1):** **Combat**, **Elite** (harder combat, better reward), **Rest**, **Event**, **Boss**. **Shop/currency is deferred.**
- **RunState persists across nodes:** the party, **per-character HP carried over** ([ADR-0011](0011-death-downed-and-hp-attrition.md)), the **run deck** (cards drafted this run), **relics** (a light persistent-modifier system, in v1), the run **seed**, and map position. Supports a **mid-run save/resume**.
- **Deckbuilding via card rewards:** after each combat, the player picks **1 of N** cards from a **character-tagged pool** to add to the run deck — the core roguelite loop ([ADR-0004](0004-shared-deck-character-tagged-cards.md)).
- **Rest nodes:** choose **heal a chunk** OR **upgrade a card** (uses the `upgrade_of` field already in the schema).
- **Relics (light, v1):** a small, data-driven persistent-modifier system — relics are acquired from elites, the boss, and some events, and apply at defined hooks (e.g. +1 energy/turn, start combat with block, draw +1). Ship a handful; broad relic depth grows later.
- **Events:** minimal, data-driven **choice → outcome** nodes (HP / card / relic deltas). Ship a few; **broad event development is deferred** to later.
- **HP & death** per [ADR-0011](0011-death-downed-and-hp-attrition.md): HP carries; downed units revive next encounter at low HP; a small post-combat partial heal; **TPK ends the run**; cross-death meta-progression deferred.

## Options Considered

| Option | Verdict |
|--------|---------|
| **StS-style branching map, 1 act, card-draft rewards** | **Chosen** — matches the deckbuilding-run identity and lets attrition/defense decisions emerge. |
| Into-the-Breach fixed-island structure | Rejected for v1 — less of a deckbuilding-run feel. |
| Linear encounter sequence | Rejected — removes the path-choice that makes the map interesting. |
| Shop/currency in v1 | **Deferred** — adds an economy to balance; not needed to prove the loop. |
| Relics/powers in v1 | **Chosen (light)** — relics are core to roguelite build texture; a small data-driven system ships in v1. Broad relic depth grows later. |

## Consequences

- The interesting design questions become **real and measurable**: extend telemetry to the run level (nodes visited, rewards drafted, run length, death node, per-fight attrition) and we can finally see whether the economy holds across a run.
- New systems to build: the **run/map data schema** (`docs/systems/run-structure.md`), **map generation**, a **run controller/flow**, **card-reward**, **rest** and **event** node handlers, an **encounter pool** (more than `skirmish_01`), and a **map/run UI**.
- The existing **`EncounterAssembler` / `BattleState` plug in unchanged**: a Combat node hands the RunState's party, carried-over HP, and run deck to the assembler — no combat rewrite.
- Validates (or pressure-tests) the cooldown economy: a `return`-keyword card that opts out of deck cycling will now be measured across many fights, not one.

## Open questions (tunable / deferred)

- **Shop & currency**, **cross-death meta-progression**, **multi-act maps** — deferred from v1; revisit after the loop is proven. **Relics** ship in v1 but lightly (a handful, simple triggers); **Events** ship in v1 but minimal — broad development of both comes later.
- Exact **map size / node-type distribution**, **heal and reward numbers**, **reward choice count (N)**, and **revive HP** — tunable in data, set during balancing.
- Whether **Events** ship in v1 or get deferred to a rest+combat-only first cut.
