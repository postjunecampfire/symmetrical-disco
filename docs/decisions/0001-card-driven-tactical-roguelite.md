# ADR-0001: Adopt a card-driven tactical roguelite structure

**Status:** Accepted
**Date:** 2026-06-05
**Deciders:** Michael (owner); Claude (build partner)

## Context

The goal is a game the owner actually wants to play, drawing on Fire Emblem (tactical grid combat, character depth), Final Fantasy VII (a party of distinct characters), and Slay the Spire (roguelite run loop, deckbuilding — the owner has shipped a StS mod). Constraints: limited solo coding capacity, a partnered/agent-delegated build, and a desire for bounded, deferrable art. A single coherent structural spine is needed before any system choices.

## Decision

Build a **card-driven tactical roguelite**:
- Slay-the-Spire **run structure** — a node-map run, save points between encounters, **full restart on death**, run-scoped state layered over meta-progression.
- Fire-Emblem **grid combat** — small, sharp tactical skirmishes (Into the Breach scale), not large armies.
- **Cards as the action system** — deckbuilding *is* the progression.
- A **small party (2–3)** of distinct, customizable characters.

## Options Considered

| Option | Verdict |
|--------|---------|
| Authored FE-style campaign | Rejected — conflicts with roguelite/death-restart pillar; content-heavy. |
| Menu-driven JRPG (FF7) | Rejected — fun requires a large authored world; art/content cost too high for solo+playable. |
| Pure Slay the Spire clone | Rejected — loses the tactical-grid depth the owner wants. |
| **Card + grid + roguelite hybrid** | **Chosen** — unifies all pillars; proven by Fights in Tight Spaces / Trials of Fire / Into the Breach. |

## Consequences

- No turnkey engine fits this exactly, which drove the Godot choice (see [ADR-0002](0002-engine-godot-gdscript.md)).
- Art scope stays bounded (small grids, reusable tiles) and can be deferred.
- The build leans on the owner's existing card-as-data modding skills.
- Two systems run at once (board state + hand state); to stay manageable, **keep grids small and runs long** (see [ADR-0004](0004-shared-deck-character-tagged-cards.md), [ADR-0006](0006-draw-as-cooldown-model.md)).
