# ADR-0017: Keep cards over cooldowns; base-3 shared energy; restricted `return`

**Status:** Accepted — *the **shared** energy pool is superseded by [ADR-0025](0025-per-character-decks-and-hands.md) (energy is now per character); the base-3 amount, the relic/boon increase model, and the `return` restriction all carry forward unchanged.*
**Date:** 2026-06-07
**Deciders:** Michael (owner); Claude (build partner)
**Relates to:** [ADR-0004](0004-shared-deck-character-tagged-cards.md), [ADR-0006](0006-draw-as-cooldown-model.md) (draw = cooldown), [ADR-0005](0005-innate-strike-defend.md), [ADR-0025](0025-per-character-decks-and-hands.md) (per-character energy). Resolves the energy-economy open question from the concept brief.

## Context

The return-spam telemetry finding (one cheap, infinitely-returning card did ~two-thirds of damage) raised whether to abandon cards for an explicit per-skill cooldown system ("use Skill X, refreshes in 2 turns"). Explicit cooldowns kill the exploit by design but also discard two of the three jobs the deck does: per-turn **variance** (the draw) and **deckbuilding as progression** (the draft loop — the roguelite replayability engine and the owner's modding strength). Cooldowns only replace the third job (availability timing).

## Decision

- **Keep the card/deck system.** The build-a-deck loop is the primary decision generator, and its RNG is desirable texture, not a defect. Explicit cooldowns are rejected.
- **Energy: base 3, shared.** One shared energy pool of **3 per player turn** ([ADR-0004](0004-shared-deck-character-tagged-cards.md) one pool; [ADR-0010](0010-turn-order-strict-phases.md) refilled at player-phase start). Increases come only from **relics/boons** ([ADR-0012](0012-run-structure-and-map.md)), which are rare and prized.
- **`return` is restricted.** The return-to-hand keyword is allowed only on **low/no-damage utility** (block, draw, a small fixed ping) and **banned on any card whose output scales with stats**. Energy cost is the primary governor on recasts.

## Options Considered

| Option | Verdict |
|--------|---------|
| Replace cards with explicit per-skill cooldowns | Rejected — kills variance + deckbuilding progression to fix one exploit that is fixable inside cards. |
| Keep `return` unrestricted | Rejected — bypasses the deck-cycle cooldown ([ADR-0006](0006-draw-as-cooldown-model.md)) and enables infinite scaling attacks. |
| Higher base energy (4+) | Deferred — 3 keeps action economy tight and doubles as the recast brake; raise only via relics. |
| **Keep cards; base-3 energy; restrict `return`** | **Chosen.** |

## Consequences

- **Energy scarcity is the real exploit brake**, more than deck size: a shared pool of 3 caps any card's recasts per turn regardless of `return`, because each cast still costs energy. Bigger decks dilute *draw* frequency but do **not** touch a `return` card's availability (it never enters the discard/reshuffle cycle).
- Tuning the **innate-floor cost** (Strike/Defend, [ADR-0005](0005-innate-strike-defend.md)) shares the same dial — set it so drawn cards remain the spikes and the floor isn't free-spammable.
- **+1 energy is a ~33% throughput swing** here, so energy relics/boons must be rare and high-value ([ADR-0018](0018-meta-progression-exit-package.md) keeps boons horizontal for the same reason).
- Deckbuilding only has stakes if a greedy all-offense deck is punished across a run — that depends on **HP attrition** ([ADR-0011](0011-death-downed-and-hp-attrition.md)) and remains the central **untested** thesis (see open questions).

## Open question (must be tested over a full run)

Whether a fun balance point exists where a greedy offense deck dies and a varied/defensive deck survives — i.e., whether attrition gives deckbuilding real weight. This can only be measured over a multi-fight run on one HP bar; it is the reason the next milestone is a minimal full-run loop, not more single-fight polish.
