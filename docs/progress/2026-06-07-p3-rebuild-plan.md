# P3 Rebuild Plan — positionless + stat/class combat (P3·01–03)

**Date:** 2026-06-07
**Owners:** Michael; Claude
**Governs:** ADR-0013 (positionless), ADR-0014 (stats), ADR-0016/0017 (owner-tagged cards, restricted `return`).
**Goal of this phase:** rebuild the combat core on the new concepts so the *eventual* attrition test (P3·09) measures the economy we'll actually ship — not the old flat-number grid combat.

> **Plan only.** No code or schema edits are made by this document. Each task below lists its contract change and acceptance tests so it can be delegated as a discrete, test-gated unit per `AGENTS.md`. Build order is strict: **P3·01 → P3·02 → P3·03**, each landing the headless GUT suite green (human-verified) before the next begins.

---

## Ordering rationale

1. **P3·01 (positionless) first** — it's a destructive refactor of the tested combat core and rewrites the targeting surface. Clear the grid before layering stats/cards onto it, so later work isn't fighting tile logic.
2. **P3·02 (stats) second** — additive; underpins card scaling.
3. **P3·03 (cards) third** — card scaling reads the *owner's* stats, so stats must exist first.

Each task's **step 1 is to update the contract** in `docs/systems/data-schemas.md` (the seam), then implement against it.

---

## Grid quarantine (mechanics, applies in P3·01)

"Quarantine, remove from build" = recoverable in-repo, excluded from the Godot build:

- Move `src/grid/**` (grid_model, pathfinder, README) and `tests/grid/**` + `tests/combat/test_tile_targeting.gd` into a new top-level `/attic/grid/`.
- Drop a `.gdignore` file in `/attic/` so Godot's resource scanner skips it (no compile, no class registration) — still in git history and on disk, fully recoverable.
- Sever every reference to grid classes from active combat code (see P3·01). The build must contain **zero** live references to `GridModel` / `Pathfinder` once done.

---

## P3·01 — Positionless combat (quarantine grid)

**Goal:** combat resolves Slay-the-Spire-style — party vs. enemies, targets chosen directly, no tiles/movement/range/terrain/facing.

**Changes**
- Quarantine grid per the section above.
- `combatant.gd`: remove positional fields (tile/position/facing).
- `target_spec.gd` + `effect_resolver.gd`: replace tile/range targeting with positionless target *kinds* — `self`, `ally`, `all_allies`, `enemy`, `all_enemies`, `random_enemy`. AoE = `all_enemies` (fixes the **Frost Nova over-promise** bug); single-target = `enemy`.
- `effect.target_override`: **Decided (2026-06-07): remove the field** from the schema and parser — positionless target kinds make it redundant. Closes the parsed-but-never-applied dangling-bug task. A test asserts the field is gone (loading data that includes it is ignored or rejected, per the loader's strict-validation stance).
- `encounter_data.gd` / `encounter_assembler.gd`: drop spawn-tile / grid layout; party and enemies are plain lists.
- `battle_state.gd` / `encounter_battle.gd`: remove grid references; turn loop and phases (ADR-0010) otherwise unchanged.
- `battle_view.gd` (UI): **UI work is on hold (confirmed 2026-06-07).** The *only* permitted change is severing grid references so the project compiles and the GUT suite runs — no new UI, no target-selection UX, no polish. If combat can be driven and tested without battle_view, prefer leaving it minimally stubbed. UI is picked back up only after P3·03 is green.
- `data/`: strip tile/position/range fields from encounter and character JSON; retarget card/status effects to the new target kinds.

**Contract change (`data-schemas.md`):** remove grid/tile/position/range from Combatant, Encounter, and TargetSpec; redefine TargetSpec as the positionless kind enum above.

**Acceptance (GUT)**
- A battle assembles and runs to win **and** loss with no grid module loaded; the suite contains no reference to grid classes.
- Single-target card hits exactly one chosen enemy; `all_enemies` card hits every enemy (Frost Nova regression); `self`/`ally` targeting resolves correctly.
- Chosen `target_override` behavior is asserted (removed-from-schema *or* applied).
- All previously-green non-grid combat / deck / effect / AI tests still pass.
- Quarantined grid tests are excluded; no orphaned references anywhere.

**Out of scope:** stats, card ownership (later tasks), UI polish.

---

## P3·02 — Stat system + stat-powered innate floor

**Goal:** characters carry STR/DEX/CON/INT; the innate Strike/Defend floor (ADR-0005) and HP derive from stats, all via data.

**Changes**
- `character_data.gd`: add `strength`, `dexterity`, `constitution`, `intelligence` (int) and `attack_stat: StringName` (`str` | `int`) — which stat powers that character's innate Strike (vanguard = `str`, mage = `int`).
- `combatant.gd`: carry the four stats; derive `max_hp` from CON via a data-defined formula.
- Innate actions / `effect_resolver.gd`: innate Strike damage = `base + attack_stat`; innate Defend block = `base + DEX`. Formula coefficients live in `battle_config` / data — **no magic numbers in code**.
- `data/characters/mage.json`, `vanguard.json`: add stat blocks + `attack_stat`.

**Contract change (`data-schemas.md`):** Character gains the four stats + `attack_stat`; Combatant `max_hp` is CON-derived; document the innate Strike/Defend formulas as reading from data.

**Acceptance (GUT)**
- Max HP equals the CON formula from data.
- Innate Strike = `base + attack_stat`: vanguard scales off STR, mage off INT — assert both.
- Innate Defend block = `base + DEX`.
- Changing a stat value in test data changes the derived output (proves data-driven).
- No regression in existing combat-flow tests with stats wired in.

**Out of scope:** card scaling (P3·03), leveling (P3·05), classes (P3·04).

---

## P3·03 — Owner-tagged, stat-scaled cards + restricted `return`

**Goal:** every card belongs to one character, scales off that owner's stats (one number, one legal player), and the `return` exploit is closed at the loader.

**Changes**
- `card_data.gd`: add `owner: StringName` (character id, or `neutral`) and a scaling spec — `scales_with: StringName` (`str` | `int` | `none`) + coefficient. Neutral cards: `owner = neutral`, `scales_with = none` (flat).
- `card_play.gd` / `effect_resolver.gd`: a card's scaled values use the **owner's** stats, looked up at play time. Enforce that only the owner may play an owned card (neutral = either character).
- `deck.gd`: cards carry owner; hand surfaces it.
- `content_database.gd` (loader validation): a card with the `return` keyword **and** stat-scaling damage **fails validation** (mirror the existing strict-validation fixtures). `return` on flat utility is allowed.
- `data/cards/*.json`: tag each card to an owner or `neutral`; add `scales_with` where relevant; fix `arcane_bolt` so it no longer both scales **and** returns (the original exploit).

**Contract change (`data-schemas.md`):** Card gains `owner` + `scales_with`; `return` + stat-scaling-damage is an invalid combination the loader rejects; neutral cards are flat.

**Acceptance (GUT)**
- An owned damage card played by its owner deals `base + owner-stat scaled` damage; the same card is illegal for the non-owner.
- A neutral card deals a flat value regardless of who plays it.
- New loader fixture: a `return` + scaling-damage card fails validation; a `return` + flat-utility card passes.
- `arcane_bolt` regression: it no longer both scales and returns.
- Existing deck / card-play tests pass with ownership wired in.

**Out of scope:** classes (P3·04), leveling (P3·05), the card-draft reward (already built in P2).

---

## After P3·03 — the handoff to the attrition test

With combat rebuilt on the shipping model, it becomes the valid test rig. The path to the actual experiment:

1. Wrap it with the **run controller (P2·04)** + **HP carryover/revive (P2·05)** + **run-level telemetry (P2·11)** — these wrap combat unchanged per ADR-0012.
2. Run **P3·09** — the minimal full run — and read the data against the pass criteria set on 2026-06-07:
   - a greedy all-offense deck fails to reach the boss a meaningful fraction of the time;
   - a deck drafting some defense/utility clears more often;
   - the innate Defend / block actually gets **used** (zero last time was the smoking gun);
   - HP visibly **depletes** across the run.
   - If it fails, the instrumented knobs to turn: fewer heals, more enemy damage, more fights, or a lower offense ceiling.

Classes (P3·04), leveling (P3·05), promotion (P3·06), and the exit-package meta (P3·08) come **after** the thesis reads green — they deepen identity but don't change whether the economy works.

---

## Conventions reminder (from `AGENTS.md`)

Typed GDScript throughout; warnings-as-errors (no `:=` inferred from a `Variant`); data over code (no inline balance numbers); one system per module; agents can't run Godot, so each task ends with a **human GUT run** as the gate from "written" to "done."
