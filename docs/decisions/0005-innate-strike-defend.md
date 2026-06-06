# ADR-0005: Innate Strike/Defend, not in the deck

**Status:** Accepted
**Date:** 2026-06-05
**Deciders:** Michael (owner); Claude (build partner)

## Context

A shared, character-tagged deck ([ADR-0004](0004-shared-deck-character-tagged-cards.md)) creates a failure mode: the player can draw a hand full of cards for a unit who is already down or out of position — a "dead hand" with nothing useful to do. Slay the Spire's default of stuffing starter decks with basic Strikes/Defends also dilutes the deck with filler.

## Decision

Every character **always** has **Strike** and **Defend** available as **innate actions** — *not* cards in the deck. The deck holds only *interesting* signature skills. Strike/Defend still cost energy (or a unit's action), so drawn cards remain the meaningful spikes.

## Options Considered

- **Strike/Defend as deck cards (StS default)** — Rejected. Bloats the deck with filler and reintroduces the dead-hand problem.
- **Innate Strike/Defend** — **Chosen.** Guarantees every unit can always act, keeps the deck all-signal, and the baseline floor scales automatically with party size.

## Consequences

- No bricked turns; every unit has a floor of agency.
- Deckbuilding stays high-signal — drafted cards are all meaningful.
- **Balance contract:** Strike/Defend are the reliable *modest* floor; drawn cards are combos/utility/burst. Energy cost must be tuned so players don't simply spam the floor and ignore the deck.
