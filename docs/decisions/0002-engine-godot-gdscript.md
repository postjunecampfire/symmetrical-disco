# ADR-0002: Engine — Godot 4 + GDScript

**Status:** Accepted
**Date:** 2026-06-05
**Deciders:** Michael (owner); Claude (build partner)

## Context

[ADR-0001](0001-card-driven-tactical-roguelite.md) commits to a card-driven tactical roguelite — a set of custom, *composed* systems (run loop, deckbuilding, grid combat, custom progression) rather than content authored into an existing campaign engine. The project is 2D, solo+partnered, cost-sensitive, and agent-delegated. We need an engine that gives us the loop/render/input/audio/tilemap plumbing for free while leaving the RPG/card systems fully in our hands.

## Decision

Use **Godot 4.x** with **GDScript** as the primary language (C# only if a future ADR justifies it for a specific system). Pin the exact engine version in the repo.

## Options Considered

| Option | Complexity | Cost | Fit | Verdict |
|--------|-----------|------|-----|---------|
| **Godot 4 + GDScript** | Low–Med | Free, no royalties | 2D-first, data-friendly, strong tilemaps | **Chosen** |
| Lex Talionis (Python/Pygame) | Low | Free | FE campaign engine — fights the roguelite/card structure | Rejected |
| RPG Maker MZ (JS) | Low | Paid | JRPG-locked battle model | Rejected |
| Unity (C#) | Med | Free-ish, licensing uncertainty | Capable, heavier, business-model risk | Rejected (for now) |
| Custom (C++/Rust/MonoGame) | High | Free | Maximum control, must build all plumbing | Rejected — too much floor to build |

## Consequences

- We build the RPG and card systems ourselves — mitigated by starting from templates (see [ADR-0007](0007-build-on-existing-templates.md)).
- Excellent 2D and tilemap workflow; Godot `Resource`s pair naturally with our data-driven design (see [ADR-0003](0003-data-driven-content-architecture.md)).
- GDScript's low boilerplate suits a limited-coding, agent-delegated build.
- Smaller asset/library ecosystem than Unity; some wheels we'll build or borrow.
