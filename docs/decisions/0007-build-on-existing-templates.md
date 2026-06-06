# ADR-0007: Build on existing template code, wrapped behind our interfaces

**Status:** Accepted
**Date:** 2026-06-05
**Deciders:** Michael (owner); Claude (build partner)

## Context

The build is solo + agent-delegated with limited coding capacity. Greenfielding engine-level systems (grid movement, turn FSM, card hand/draw) is exactly the high-risk, well-trodden work most likely to stall the project. Incorporating proven existing code is the biggest available lever to "raise the floor" on success — and agents extend documented, working code far more reliably than they write from scratch.

## Decision

Start foundational systems from **known-good open-source bases** rather than from zero:
- Grid / movement / turn FSM from a reputable **Godot tactical RPG template** (e.g. GDQuest tactical-movement, Godot Tactical RPG template).
- Card hand / deck / draw from an open **card-battler** base where one fits.

For every borrowed component: vendor it under `/third_party/<name>/`, add a `PROVENANCE.md` (source URL, version/commit, **license**, and exactly what we changed), and **wrap it behind our own interface** so it is swappable. Use **permissive licenses only** (MIT/Apache/BSD); flag any copyleft (GPL/AGPL) for an explicit decision before depending on it.

## Options Considered

- **Greenfield everything** — Rejected. Highest risk, slowest, most agent failure surface.
- **Fork a template and edit in place** — Rejected. Provenance and upgrade path get lost; coupling spreads.
- **Vendor + wrap proven bases** — **Chosen.** Fast, reliable, swappable, and license-clean.

## Consequences

- Faster, more reliable foundation; agents extend documented working code.
- Adds provenance/license bookkeeping and an integration/wrapping step per component.
- Some borrowed code will be replaced later — the interface wrappers make that a contained change, not a rewrite.
- Reinforces the data-driven boundary ([ADR-0003](0003-data-driven-content-architecture.md)): borrowed code sits behind our interfaces and reads our data.
