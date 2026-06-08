# ADR-0014: Stat-driven characters — STR/DEX/CON/INT power the floor and scale cards

**Status:** Accepted
**Date:** 2026-06-07
**Deciders:** Michael (owner); Claude (build partner)
**Relates to:** [ADR-0005](0005-innate-strike-defend.md) (innate floor), [ADR-0004](0004-shared-deck-character-tagged-cards.md) (character-tagged cards).

## Context

With the tactical grid removed ([ADR-0013](0013-positionless-combat-drop-grid.md)), the game's differentiation moves to an RPG progression layer. A character needs a persistent identity beyond their card list. The risk of bolting RPG stats onto a deckbuilder is diluting the deckbuilder's clarity — "the card says what it does" — by making every number depend on a hidden sheet.

## Decision

Each character has four base stats: **STR, DEX, CON, INT.**

- **STR** → base physical damage
- **DEX** → base block / defense
- **CON** → max HP
- **INT** → base magic damage (the caster's STR analog)

Stats **power the innate floor** from [ADR-0005](0005-innate-strike-defend.md): the innate **Strike** scales with STR (or INT for casters), innate **Defend** with DEX, HP with CON. Stats also **scale drafted cards**, but that scaling is resolved by the card's **owner** ([ADR-0016](0016-party-size-two-owner-tagged-cards.md)), so a card always shows one number for one character. Cards remain effects-and-multipliers on top of the stat floor — they are *not* replaced by raw stat numbers, preserving "the card says what it does."

## Options Considered

- **No persistent stats (pure StS)** — Rejected. Removes the RPG progression that is now the differentiator.
- **Stats replace card values entirely** — Rejected. Dilutes deckbuilder clarity; cards stop being legible.
- **Stats power the innate floor; cards scale off the owner** — **Chosen.** The sheet raises the floor and gives leveling weight; cards stay all-signal spikes ([ADR-0005](0005-innate-strike-defend.md)).

## Consequences

- The character sheet *is* the scaling innate floor — leveling ([ADR-0016](0016-party-size-two-owner-tagged-cards.md) party; [ADR-0015](0015-classes-races-leveling.md) leveling) visibly raises baseline power.
- STR vs. INT becomes a build axis: a character's stat allocation decides whether physical or magic cards pay off. **Requirement:** the draftable card pool must contain both physical and magic cards, or stat allocation decouples from deckbuilding and the sheet stops mattering.
- Stats are data ([ADR-0003](0003-data-driven-content-architecture.md)); damage/block/HP formulas read from stats, never hardcoded.
- Neutral cards (playable by either character) should be **flat** (no stat scaling) so they never reintroduce per-character value math.
