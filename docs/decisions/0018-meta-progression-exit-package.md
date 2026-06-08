# ADR-0018: Meta-progression — exit-package extraction, horizontal boons

**Status:** Accepted
**Date:** 2026-06-07
**Deciders:** Michael (owner); Claude (build partner)
**Relates to:** [ADR-0001](0001-card-driven-tactical-roguelite.md) (run-scoped over meta), [ADR-0012](0012-run-structure-and-map.md) (run structure). Resolves the "what persists across deaths" open question.

## Context

The concept left cross-death meta-progression undecided. We want persistence that rewards investment without the classic failure modes: vertical "start stronger every run" power creep that either trivializes early floors or becomes mandatory (making boon-less runs feel bad).

## Decision

- **Exit-package extraction.** After clearing a threshold (a number of **acts/floors** — exact depth tunable), the player is **offered an exit**. Taking it ends the run as a *graduation*: from then on, each new run **starts with a relic or boon** of some kind. Declining pushes deeper for richer in-run rewards — a genuine "cash out now vs. push your luck" choice.
- **Boons are mostly horizontal.** Persistent unlocks favor **new options** (cards, classes, relics, races into the pool) over flat power. Any vertical boon is small and prized.

## Options Considered

| Option | Verdict |
|--------|---------|
| No cross-death persistence (pure StS run-scoping) | Rejected — the owner wants persistence that rewards repeated play. |
| Vertical "start each run stronger" power ladder | Rejected — trivializes early floors or becomes mandatory; boon-less runs feel bad. |
| **Exit-package extraction + mostly-horizontal boons** | **Chosen** — adds an extraction-tension decision and grows the option pool without power creep. |
| Difficulty ladder (StS Ascension) | **Complementary, deferred** — the horizontal-meta + separate-difficulty-dial split is the model to grow into later. |

## Consequences

- A new persistent (cross-run) save layer is required, distinct from the in-run `RunState` ([ADR-0012](0012-run-structure-and-map.md)): unlocked options + earned starting boons.
- The "offer an exit" node/flow is a new run-structure element to design at the act boundary.
- Keeping boons horizontal protects early-floor balance and avoids a mandatory-boon trap; revisit a separate difficulty dial (Ascension-style) once the core loop is proven.
- Exact thresholds, the boon set, and what an exit forfeits are **tunable, set during balancing**. This remains **deferred** behind proving the single-run loop works.
