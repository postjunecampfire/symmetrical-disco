# ADR-0010: Turn order — strict player/enemy phases (prototype)

**Status:** Accepted
**Date:** 2026-06-05
**Deciders:** Michael (owner); Claude (build partner)

## Context

`docs/systems/data-schemas.md` left turn order as an open question: strict **player-phase / enemy-phase** (Fire Emblem style) versus **speed-based initiative** (interleaved turns ordered by a `speed` stat). The battle-state task ([P1·04]) had to commit to one to build the turn loop, energy refill, and status ticking. The shared-deck economy ([ADR-0004](0004-shared-deck-character-tagged-cards.md)) refills one energy pool per player turn, which interacts with how turns are sequenced.

## Decision

For the prototype, use **strict phases**: the **player phase** (all player units may act) runs to completion, then the **enemy phase** (all enemies act) runs as a block. The shared energy pool refills and the hand is drawn at **player-phase start**. The `speed` stat is retained in the data model but is **not** used for initiative yet.

## Options Considered

- **Strict player/enemy phases** — **Chosen.** Simplest loop; matches the Fire Emblem feel of the design pillars; aligns cleanly with a single shared energy pool refilled once per player turn.
- **Speed-based initiative (interleaved)** — Deferred. More complex, and interleaving enemy turns into the middle of a player turn interacts awkwardly with one shared hand and one shared energy pool. Revisit only if the design wants it.

## Consequences

- The turn loop, energy refill, and status ticking are straightforward and testable (driven to win/loss in P1·04 tests).
- Enemy AI ([P1·08]) runs as a phase-level block rather than per-initiative-slot.
- `speed` remains available for later use (e.g. acting order *within* a phase, or a future initiative model) without a data change.
- If interleaved initiative is later desired, it will need to be reconciled with the shared-deck energy economy — that would be a new ADR superseding this one.
