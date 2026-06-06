# AGENTS.md — Unnamed Game

> **Single source of truth for anyone — human or AI agent — writing code in this repo. Read this first, before any task.**
> If guidance here ever conflicts with a task ticket, this file and the ADRs win; stop and flag the conflict.

---

## What this project is

A **card-driven tactical roguelite**: Slay the Spire's run structure and deckbuilding, Fire Emblem's grid positioning, played as small, sharp tactical skirmishes across a death-restarts run.

- **Full vision:** `docs/concept/concept-brief.md`
- **Settled decisions:** `docs/decisions/` (numbered ADRs). These are binding. Do not contradict them without writing a new ADR that supersedes the old one.
- **System specs:** `docs/systems/` (card system, combat/grid, run structure, data schemas).

---

## Tech stack

- **Engine:** Godot 4.x — pin the exact version in `project.godot` and a `.godot-version` file; do not assume a different minor version.
- **Language:** GDScript (primary). C# only if an ADR explicitly decides it for a given system.
- **Tests:** GUT (Godot Unit Test), under `res://tests/`.
- **Targets:** Desktop (Windows / macOS / Linux) first; web (HTML5) export considered later.

---

## Planned repo layout

```
/                     project.godot, .godot-version, AGENTS.md, CLAUDE.md
/docs
  /concept            concept-brief.md
  /decisions          0001-*.md … (ADRs, append-only)
  /systems            card-system.md, combat-grid.md, run-structure.md, data-schemas.md
/src                  game code, one folder per system (cards/, combat/, run/, units/, ui/)
/data                 card/character/enemy/encounter definitions (.tres or .json)
/assets               sprites, tilesets, audio (placeholder first)
/addons               third-party addons (GUT, any templates) — extend via wrappers, don't edit internals
/tests                GUT test suites mirroring /src
/third_party          vendored template/base code, each with a PROVENANCE.md
```

If a folder doesn't exist yet, create it as needed — but keep to this structure.

---

## Core architectural rules (non-negotiable)

1. **Data-driven, always.** Cards, characters, enemies, and encounters are **data** (Godot `Resource`/`.tres` or JSON in `/data`), not hardcoded classes. Code reads data and applies rules. See `docs/systems/data-schemas.md` for the exact shapes — treat those schemas as contracts.
2. **No magic numbers for balance in code.** Any tunable value (damage, energy cost, draw count, cooldown/deck size, HP) lives in data, never inline in a script.
3. **Wrap external code.** Template/borrowed code stays behind our own interfaces so it's swappable. Never scatter direct calls to third-party internals across the codebase. Record provenance + license in `/third_party/<name>/PROVENANCE.md`.
4. **One system per module, decoupled.** Systems communicate through signals or clearly defined interfaces, not by reaching into each other's internals. A change in one system shouldn't require editing another.
5. **The data schema is the seam.** Implement against the documented schema so card-loading, card-authoring, and combat can be built in parallel by different agents.

---

## GDScript conventions

- **Files:** `snake_case.gd`. **`class_name`:** `PascalCase`. **Functions/variables:** `snake_case`. **Constants:** `ALL_CAPS`. **Private members:** `_leading_underscore`.
- **Use typed GDScript** everywhere: `var hp: int = 0`, `func take_damage(amount: int) -> void:`. Types are documentation the agent and engine both enforce.
- **Signals** are named in the past tense for things that happened: `card_played`, `unit_died`, `turn_ended`.
- **Scenes/Nodes:** `PascalCase`. One reusable type per file via `class_name`.
- Prefer composition (child nodes / resources) over deep inheritance.

---

## How to run and test

- **Run the game:** open `project.godot` in the Godot editor, or `godot --path .`
- **Run all tests (headless):**
  `godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests -gexit`
- **Every non-trivial system ships with GUT tests.** A task is not done until its acceptance criteria are covered by passing tests.

---

## Working as a delegated agent

- **Read first:** this file → the ADRs your system depends on → the relevant `docs/systems/*` spec → your task's acceptance criteria.
- **Stay in scope.** Implement your task and its interface contract only. Do **not** refactor neighboring systems, restructure folders, or change shared interfaces as a side effect.
- **Acceptance criteria are the spec.** Satisfy them exactly and write GUT tests that prove each one.
- **When blocked by a decision:** if your task would require contradicting an ADR or changing a shared interface/schema, **STOP and flag it.** Propose a new ADR; do not silently diverge.
- **Do not touch without explicit instruction:** project settings, other systems' files, third-party addon internals (extend via wrappers), or any decided ADR's substance.

---

## Decision discipline (ADRs)

- Settled decisions live in `docs/decisions/` as numbered, **append-only** ADRs (context, decision, alternatives, consequences).
- To **change** a decision: write a *new* ADR that references and supersedes the old one. Never rewrite a decided ADR's substance — the history is the value.
- Before changing anything that feels "already settled," grep `docs/decisions/` first.

---

## Existing / borrowed code

- Prefer extending documented, working template code over greenfield (it raises the success floor).
- For each borrowed base: vendor it under `/third_party/<name>/`, add `PROVENANCE.md` (source URL, version/commit, **license**, and what we changed), and wrap it behind our interface.
- License hygiene: permissive (MIT/Apache/BSD) preferred; flag any copyleft (GPL/AGPL) for a decision before relying on it.

---

*Keep this file authoritative and current. If a rule changes, update it here — and if the change is a real decision, record it as an ADR too.*
