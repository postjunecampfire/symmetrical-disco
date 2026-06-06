# ADR-0003: Data-driven content architecture

**Status:** Accepted
**Date:** 2026-06-05
**Deciders:** Michael (owner); Claude (build partner)

## Context

The game needs lots of content — cards, characters, enemies, encounters — and frequent rebalancing. We also want to delegate work to multiple agents in parallel and let the owner tune balance without touching code. The way content is stored determines whether that is possible.

## Decision

All content is **data**, not hardcoded logic. Cards, characters, enemies, and encounters are defined as data files (**Godot `Resource`/`.tres`**, with JSON as an interchange/authoring option) under `/data`. Code reads data and applies rules. The shape of each entity is documented as a **schema contract** in `docs/systems/data-schemas.md`. No balance "magic numbers" live in code.

## Options Considered

- **Hardcoded classes** — fastest to start, but every change needs a recompile and blocks parallel content authoring. Rejected.
- **Godot Resources (`.tres`)** — editor-integrated, fast to load, native. **Chosen as the runtime format.**
- **JSON** — diffs cleanly, tool-agnostic, great for bulk authoring and version control. **Kept as an authoring/interchange option**, baked or loaded into Resources.

## Consequences

- The **data schema becomes the parallelization seam**: one agent builds the card loader while another authors 40 cards, against the same contract.
- The owner can rebalance by editing data, no recompile.
- Requires up-front schema discipline and a loader with validation.
- Slightly more initial plumbing than hardcoding — paid back immediately once content volume grows.
