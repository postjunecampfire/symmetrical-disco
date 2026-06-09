# ADR-0025: Per-character energy pools

**Status:** Accepted — supersedes the **shared** energy pool of [ADR-0017](0017-keep-cards-energy-and-return.md) (the base-3 amount and the relic/boon increase model carry forward; only the *shared* aspect changes).
> **Scope split (2026-06-09):** This ADR was originally proposed as *"Per-character decks and hands"* and bundled two decisions. On owner review the **energy** decision was accepted (recorded here) and the **deck/hand** decision was carved out into a dedicated design track — see [`docs/systems/skill-deck-model.md`](../systems/skill-deck-model.md). **Resolved:** the deck/hand model landed in [ADR-0026](0026-derived-decks-from-skill-loadouts.md) (per-character derived decks from active skill loadouts). The filename is retained as-is so existing cross-references don't break.
**Date:** 2026-06-09
**Deciders:** Michael (owner); Claude (build partner)
**Relates to:** [ADR-0017](0017-keep-cards-energy-and-return.md) (base-3 *shared* energy — the model this revises), [ADR-0024](0024-act-structured-squad-recruitment.md) (the Act-2 recruit that motivates per-character independence), [ADR-0016](0016-party-size-two-owner-tagged-cards.md) (party of 2), [ADR-0010](0010-turn-order-strict-phases.md) (energy refilled at player-phase start), [ADR-0006](0006-draw-as-cooldown-model.md).

## Context

[ADR-0017](0017-keep-cards-energy-and-return.md) set **one shared energy pool of 3** for the whole party. [ADR-0024](0024-act-structured-squad-recruitment.md) adds a second character mid-run (solo Act 1 → party of 2 from Act 2). A single shared pool couples the two characters at the resource layer: spending on one starves the other, and it caps how independently the Act-2 recruit can act on arrival. The open question was whether energy should stay shared or become per-character.

(The companion question — whether each character also gets their **own deck and hand** — was split out of this ADR; see the scope note above. This ADR decides energy only.)

## Decision

- **Energy is per character.** Each character has their **own energy pool**, refilled at player-phase start ([ADR-0010](0010-turn-order-strict-phases.md)) and spent only on their own actions. A character's energy is never drawn from to pay for the other's plays.
- **The base amount is an open balance value — not a copy of 0017's "3".** Two pools roughly **double** the energy on the board, and [ADR-0017](0017-keep-cards-energy-and-return.md) established that **+1 energy ≈ a 33% throughput swing**, so 3-per-character (≈6 total) is a large economy increase, almost certainly not the right number. Treat the per-character base (likely **2**, possibly **3**) as a value set in prototyping. Energy relics/boons stay **rare and prized** per 0017.
- **The economy scales naturally with party size.** During solo Act 1 only the origin character's pool exists; the second pool appears with the Act-2 recruit ([ADR-0024](0024-act-structured-squad-recruitment.md)), mirroring how the innate floor and deck size already scale with the party.
- **Energy keeps its exploit-brake role, now per pool.** The recast/spam brake energy provides ([ADR-0017](0017-keep-cards-energy-and-return.md)) must be re-validated **per pool**, since each character's economy is now independent.

## Options Considered

| Option | Verdict |
|--------|---------|
| Keep one shared pool ([ADR-0017](0017-keep-cards-energy-and-return.md)) | Rejected — couples the two characters at the resource layer and caps the Act-2 recruit's independence ([ADR-0024](0024-act-structured-squad-recruitment.md)). |
| Per-character pool, base copied straight from 0017 (3 each) | Rejected — ≈ doubles board energy; +1 energy ≈ 33% swing (0017), so this is an unintended large power increase. |
| **Per-character pool, base re-tuned in prototype (likely 2)** | **Chosen** — gives each character (and the recruit) an independent economy; the larger total budget is re-tuned rather than inherited. |

## Consequences

- **The Act-2 recruit ([ADR-0024](0024-act-structured-squad-recruitment.md)) acts on its own economy** from its first turn without touching the origin character's energy.
- **A bigger, split economy.** Two pools roughly double total board energy versus 0017's single base-3, so the exploit-brake role must be re-validated per pool and the per-character base re-tuned (not copied). Upside: each character's recast brake is independent — one character's energy relic doesn't inflate the other's.
- **Status update applied:** the **shared** energy pool of [ADR-0017](0017-keep-cards-energy-and-return.md) is superseded by this ADR; the index in [`README.md`](README.md) is updated.
- **Schema impact:** energy moves from a single party-level value to a per-character value on `RunState`.
- **Resolved (was open):** decks/hands are now per-character via [ADR-0026](0026-derived-decks-from-skill-loadouts.md) (derived decks from active skill loadouts), which supersedes the shared deck of [ADR-0004](0004-shared-deck-character-tagged-cards.md)/[ADR-0016](0016-party-size-two-owner-tagged-cards.md) and confirms [ADR-0024](0024-act-structured-squad-recruitment.md)'s "recruit ships with its own deck" assumption.
