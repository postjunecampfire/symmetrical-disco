# ADR-0027: Per-character energy base = 3 (DRAFT)

**Status:** **Draft — proposed, NOT accepted, NO implementation.** Revises the base-amount
guidance of [ADR-0025](0025-per-character-decks-and-hands.md) (which leaned "likely 2,
possibly 3", deferring to prototyping). The per-character *structure* of ADR-0025 is
unchanged; this draft only pins the base value. Do not build against this until the
owner flips it to Accepted.
**Date:** 2026-06-09
**Deciders:** Michael (owner); Claude (build partner)
**Relates to:** [ADR-0025](0025-per-character-decks-and-hands.md) (per-character pools — the
decision this refines), [ADR-0017](0017-keep-cards-energy-and-return.md) (energy as the
recast/exploit brake; +1 energy ≈ 33% throughput swing), [ADR-0026](0026-derived-decks-from-skill-loadouts.md)
(rarity → copy caps; derived decks), [ADR-0024](0024-act-structured-squad-recruitment.md)
(solo Act 1 → recruit at Act 2).

## Context

[ADR-0025](0025-per-character-decks-and-hands.md) made energy per-character but left the
base amount open, leaning toward 2 because two base-3 pools ≈ double the board economy
versus the shared pool. Since then, two things changed the picture:

1. **ADR-0026 landed.** Derived decks cap copies by rarity (3/2/1) and floor decks at 20
   cards with Strike/Defend fill. The 2026-06-09 playtest exploit — `mana_surge` ×6 into
   double AoE — becomes structurally impossible, so the energy *base* no longer has to do
   the anti-stacking work alone; the deck shape now brakes throughput too.
2. **Every authored card cost assumes a base of 3.** Costs run 1–3; a base-2 pool makes
   every 3-cost card unplayable without ramp and most 2-cost cards turn-consuming,
   which would force a re-cost pass across the entire card pool before anything could
   be playtested.

The owner's call (2026-06-09): **confirm 3 per character.**

## Decision (draft)

- **Each character's energy pool refills to 3** at player-phase start
  ([ADR-0010](0010-turn-order-strict-phases.md)), spent only on that character's cards
  (basics included, per [ADR-0026](0026-derived-decks-from-skill-loadouts.md)).
- **Solo Act 1 runs on one base-3 pool** — identical feel to today's single-character
  economy; the second pool arrives with the Act-2 recruit
  ([ADR-0024](0024-act-structured-squad-recruitment.md)).
- **Acceptance is gated on measurement, not vibes.** Before this draft is accepted, the
  attrition sim (re-pointed at per-character pools) and a playtest must show the doubled
  Act-2+ economy doesn't reopen the 1-turn-trash problem *after* ADR-0026's copy caps are
  in. If it does, the fallback dial is **enemy HP / per-act bands**, not the base
  (re-costing the card pool is the change of last resort).

## Options considered

| Option | Verdict |
|---|---|
| Base 2 per character (ADR-0025's lean) | Rejected (draft) — requires re-costing the whole card pool before any playtest; punishes the solo Act-1 origin hardest (2 energy + mostly Strike/Defend fill is a non-game). |
| **Base 3 per character** | **Chosen (draft)** — preserves authored costs and the solo-Act-1 feel; the doubled Act-2+ economy is braked by ADR-0026 copy caps and measured before acceptance. |
| Asymmetric (3 origin / 2 recruit) or scaling by act | Rejected (draft) — two different economies to balance and explain; revisit only if measurement fails base-3. |

## Implementation sketch (for when accepted — NOT yet built)

1. **BattleState:** replace the single `energy` int with per-player pools (keyed by
   combatant); `start_player_turn` refills each living player to `energy_per_turn`.
   `add_energy` / the `gain_energy` effect credit **the playing character's** pool.
2. **CardPlay:** cost validation and spend against the *owner's* pool (neutral cards:
   the selected actor's pool). Innate path is removed separately by ADR-0026's
   Strike/Defend task — sequence these together to avoid double-touching.
3. **Relics/boons:** `turn_start` energy relics currently credit the shared pool —
   **open sub-question:** does an energy relic credit one chosen character or +1 to each?
   (0017's "rare and prized" framing suggests one character; decide at acceptance.)
4. **UI (battle_view):** energy displays per character on their panel, not in the
   shared footer; card playability greys against the owner's pool.
5. **Sim/tests:** attrition policies spend per-pool; GUT — pools are independent, refill
   per turn, reject unaffordable plays, `gain_energy` credits the actor, solo Act 1 has
   exactly one pool.
6. **Telemetry:** `card_played.energy_left` becomes per-actor.

## Open questions

- Energy relic semantics per pool (see #3 above).
- Whether `energy_per_turn` stays one global knob or becomes per-character data
  (race/class line) — keep global until a design need appears.
- X-cost cards (ADR-0020 class-C guardrail) read "all of the owner's energy" — confirm
  wording when the first one is authored.
