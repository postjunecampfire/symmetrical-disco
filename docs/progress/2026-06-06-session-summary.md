# Session Summary — June 6, 2026

*From "research how turn-based RPGs are written" to a playable card-driven tactical roguelite, in one session.*

---

## 1. The arc of the day

We started with an open research question — how are classic turn-based RPGs (Fire Emblem, FF7) actually built — and ended with a **playable game prototype** plus the documented foundation and run-layer plan to grow it. The path:

1. **Research** — surveyed the genre, languages, engines, and decompilations; produced two reference docs.
2. **Design conversation** — converged on the actual game through a series of decisions (below).
3. **Documentation foundation** — concept brief, ADRs, data schema, agent guardrails, git repo.
4. **Prototype build** — 12 discrete tasks, delegated to agents, each test-gated, into a playable battle.
5. **Telemetry + a design read** — instrumented the game, played it, and analyzed real data.
6. **Run-layer scope + start** — designed the roguelite meta-loop and built the first half of it.

---

## 2. What the game is (the decisions we made)

A **card-driven tactical roguelite**: Slay the Spire's run structure and deckbuilding, Fire Emblem's grid positioning, played as small sharp skirmishes across a death-restarts run. The defining choices, each recorded as an ADR:

- **Shared deck, character-tagged cards** — one hand and one energy pool per turn regardless of party size (keeps a multi-character card game manageable).
- **Innate Strike/Defend** — every unit always has a floor; the deck holds only interesting cards.
- **Draw = cooldown** — drawing a skill is it "coming off cooldown"; deck size is the global cooldown dial.
- **Hybrid death model** — a TPK ends the run; a single downed unit isn't deleted (revives next encounter at low HP); HP carries across the run with metered healing.
- **Engine: Godot 4.6 + GDScript**, data-driven content, Steam/Steam Deck as the eventual target.

Twelve ADRs total (`docs/decisions/`) capture these and the toolchain/platform choices.

---

## 3. What we built — the prototype (P1, complete)

A **fully playable vertical slice** of a single tactical card battle, every system test-backed:

- **Data loader** with strict validation; all content authored as data (cards, characters, enemies, encounters, statuses).
- **Grid + pathfinding** (reachable tiles, A*), **effect resolver**, **battle state** (turns, energy, statuses, win/lose), **shared deck** (draw/discard/reshuffle, exhaust/return), **card-play flow**, and **enemy AI** with telegraphed intents.
- **Encounter assembly** that builds a live battle from data, wired into a **code-driven playable UI** (grid, units, hand, energy, intents, end-turn, victory/defeat).

The owner has played `skirmish_01` to Victory. Roughly **130 passing GUT tests** cover the whole stack.

---

## 4. How we built it — the process

The method is as much the deliverable as the code:

- **Documentation-first.** Every settled decision is an append-only ADR; every system has a data-schema contract that acts as the "seam" letting work parallelize.
- **Agent delegation in discrete, test-gated chunks.** Each task was scoped with explicit acceptance criteria, handed to an agent that wrote code + tests, reviewed against the criteria, then verified by running the suite before commit.
- **Human-in-the-loop verification.** Agents can't run Godot, so the owner runs the headless test suite (and plays the scene) — that's the gate that turns "written" into "done."
- **Guardrails that compound.** `AGENTS.md` encodes conventions (typed GDScript, warnings-as-errors, no `:=` from Variant) so each new agent avoids the traps the last one hit.

Real bugs surfaced and were fixed through this loop — a Variant-inference compile error, a tile-target crash, a strict-parse type mismatch — each caught by the human test run and turned around in one delegation.

---

## 5. The design read (telemetry)

We built a gameplay telemetry logger and analyzed real playtest runs. The headline finding: **one card (Arcane Bolt) did ~two-thirds of all damage** and was played 41 times across 4 runs, because its `return` keyword lets it skip the deck's cooldown cycle entirely — a cheap, permanently-repeatable nuke. The encounter was also a guaranteed win (no losses), and the innate Strike/Defend went unused.

The important conclusion, reached together: in a single isolated fight with no attrition cost, max-DPS spam *is* correct — so the interesting design questions (defense, deck variety, whether that card stays dominant under pressure) **only become real once there's a run.** That pointed directly at the next layer.

---

## 6. The run layer (P2) — scoped and started

Designed the roguelite meta-loop (**ADR-0012** + `docs/systems/run-structure.md`) and decomposed it into 12 tasks. v1 scope: a Slay-the-Spire branching map (one act, boss at the end), card-draft rewards, rest/event nodes, **light relics**, HP attrition per ADR-0011 — with shop/currency and cross-death meta-progression deferred.

**Built so far:** the run-state models + JSON save/resume, procedural **map generation**, the **card-reward draft**, and a **6-encounter content pool** (escalating fights, an elite, and a 127-HP boss fight). Crucially, the run layer **wraps the existing combat without changing it** — a combat node just feeds the run's party/HP/deck into the assembler we already built.

**Remaining:** the **run controller** (ties map + combat + rewards into an actual run), node handlers (rest/event/relic), HP-carryover wiring, the **map/run UI** (the next "go play it" moment), and run-level telemetry.

---

## 7. Where things stand

- **Repo:** Godot 4.6 project under git, committed in clean test-gated increments; documentation lives beside the code.
- **Tests:** ~130 passing across loader, grid, combat, deck, AI, integration, telemetry, and run-state suites.
- **Asana:** the "Unnamed Game" board traces every decision and task — P1 fully complete, P2 about half-built, each task carrying its build notes and acceptance criteria.
- **Playable:** the single battle, today. The full run becomes playable at the P2 map-UI task.

---

## 8. What's next

1. **`P2·04` — run controller** (the spine: generate a map, traverse it, run encounters, reward on win, end on boss/TPK).
2. **`P2·07` / `P2·08`** — rest and event node handlers (can run alongside the controller).
3. **`P2·05` / `P2·12`** — HP carryover + revive, and the light relic system.
4. **`P2·10`** — the map/run UI: the next time we say "run it and tell me what you see."
5. **`P2·11`** — run-level telemetry + a full-run playtest, then read the data again to tune the real loop.

The throughline for next session: get to a **playable full run**, then let the telemetry tell us what the *design* needs — defense, deck variety, difficulty — with evidence instead of guesses.
