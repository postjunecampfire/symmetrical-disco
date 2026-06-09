# ADR-0026: Per-character derived decks from active skill loadouts

**Status:** Accepted — resolves the deck/hand question split out of [ADR-0025](0025-per-character-decks-and-hands.md). Supersedes the **shared deck** of [ADR-0004](0004-shared-deck-character-tagged-cards.md)/[ADR-0016](0016-party-size-two-owner-tagged-cards.md) (owner-tagging and party-of-2 carry forward) and **reverses** [ADR-0005](0005-innate-strike-defend.md) (Strike/Defend become deck cards). Promotes [`docs/systems/skill-deck-model.md`](../systems/skill-deck-model.md) from design discussion to decision.
**Date:** 2026-06-09
**Deciders:** Michael (owner); Claude (build partner)
**Relates to:** [ADR-0006](0006-draw-as-cooldown-model.md) (draw = cooldown), [ADR-0017](0017-keep-cards-energy-and-return.md)/[ADR-0025](0025-per-character-decks-and-hands.md) (energy), [ADR-0020](0020-card-scaling-ladder.md) (rarity ↔ scaling), [ADR-0021](0021-deferred-class-race-origin.md)/[ADR-0022](0022-class-progression-trees-ascension.md) (skill acquisition), [ADR-0024](0024-act-structured-squad-recruitment.md) (Act-2 recruit).

## Context

Per-character energy is settled ([ADR-0025](0025-per-character-decks-and-hands.md)); the companion deck/hand question was carved into [`docs/systems/skill-deck-model.md`](../systems/skill-deck-model.md). The core tension: cards should reflect a character's *current* skills with cooldown expressed as deck frequency ([ADR-0006](0006-draw-as-cooldown-model.md)), but skills change across a run (class at Act 3, tree branches at 6/9/12, Ascension at 15 — [ADR-0022](0022-class-progression-trees-ascension.md)), and manually managing two literal decks card-by-card isn't fun.

## Decision

**The player curates skills, not cards. Each character's deck is a derived view of their active skill loadout.** The class/progression tree and the deck are one system: tree nodes grant skills into the collection; the deck is the projection of the active loadout into cards.

Each character has:

1. **A skill collection** — every skill acquired this run (drafts, class pick, tree promotions, Ascension). Skills are never lost; inactive ones stay in the collection and can be re-activated later.
2. **An active loadout** — up to **10 skill slots** (tunable) the player fills from the collection.
3. **A derived deck** — auto-populated from the active loadout, each skill contributing copies by rarity.

### Rarity → copies (per-skill cooldown dial)

| Skill rarity | Copies in deck | Effective cooldown | [ADR-0020](0020-card-scaling-ladder.md) tier |
|---|---|---|---|
| Common | 3 | Short | Flat (A) |
| Uncommon | 2 | Medium | Hybrid (B) |
| Rare | 1 | Long | Multiplier (C) |

Scarcity and power line up by construction: the rare ×-multiplier appears once per shuffle — the guardrail [ADR-0020](0020-card-scaling-ladder.md) wants, for free.

### Deck size: slots set the ceiling, a 20-card minimum sets the floor

- **Ceiling:** 10 slots × 3 copies (all-common) = **30 cards max**. Slot count is the global cooldown dial of [ADR-0006](0006-draw-as-cooldown-model.md), now a player-facing build knob.
- **Floor:** the derived deck must hold **at least 20 cards**. If the active loadout yields fewer (an all-rare loadout yields 10), the system **auto-fills with basic Strike/Defend copies** (alternating, tunable ratio) up to 20.
- **Why 20:** at a hand of 5, a 20-card deck cycles in 4 turns — a rare's 1 copy lands roughly once per 4 turns, long enough to feel rare. A 15-card floor cycles in 3 turns (rares too frequent, undermines the 0020 guardrail and invites combo loops); a 25-card floor makes early decks >60% padding. 20 is the value of record; revisit only if hand size changes.

The auto-fill rule replaces any "no playable card" insurance: it *is* the floor. It also produces the Act-1 experience automatically — a race-only origin character with 2–3 skills gets a deck that's mostly Strike/Defend, and the run becomes the familiar deck-thinning arc as real skills displace fill.

### Strike/Defend become ordinary common cards (reverses [ADR-0005](0005-innate-strike-defend.md))

Of 0005's three rationales: "out-of-position dead hand" is moot (positionless combat, [ADR-0013](0013-positionless-combat-drop-grid.md), and per-character decks mean you only draw your own cards); "floor scales with party size" is moot (decks are per-character); "all-signal deck" is reframed (basics are the early floor and cooldown texture, and thinning them out *is* the progression). **No innate fallback is retained** — a hand with no playable card is accepted as a rare cost. Basics are slotless: they enter only as auto-fill and never consume loadout slots. Energy cost on basics still applies ([ADR-0017](0017-keep-cards-energy-and-return.md)) so signature skills stay the spikes.

### Loadout changes: rest nodes + progression beats

The loadout can be edited at **rest nodes** and at **progression beats** (class pick, Act 6/9/12 promotions, Act 15 Ascension — whenever new skills are granted). Not freely between fights — loadout choices carry weight between rests, StS-style.

### Progression and rewards rewire to skills

- Card-reward drafts ([ADR-0012](0012-run-structure-and-map.md)) become **skill drafts**; rest-node "upgrade a card" becomes "**upgrade a skill**" (all copies upgrade at once).
- Tree nodes ([ADR-0022](0022-class-progression-trees-ascension.md)) grant skills into the collection; Ascension's flat boost applies to the derived deck; the Ult is a rare (1-copy) skill — naturally long-cooldown.
- The Act-2 recruit ([ADR-0024](0024-act-structured-squad-recruitment.md)) arrives with its own collection/loadout/derived deck — the provisional "recruit ships with its own deck" assumption is now confirmed.

## Options considered

| Option | Verdict |
|---|---|
| Two literal per-character decks, managed card-by-card | Rejected — doubles the least-fun management; no answer for skills changing across the run. |
| Keep shared character-tagged deck ([ADR-0004](0004-shared-deck-character-tagged-cards.md)/[ADR-0016](0016-party-size-two-owner-tagged-cards.md)) | Rejected — couples characters at the deck layer just as shared energy did ([ADR-0025](0025-per-character-decks-and-hands.md)); dead-hand risk returns. |
| **Derived deck from active skill loadout (slots + rarity→copies + 20-card auto-fill floor)** | **Chosen** — player manages skills; cooldown, scaling guardrails, and the thinning arc all fall out of one mechanism. |
| Card bound (20–30) only, no slot cap | Rejected — owner prefers slots as the loadout unit; the card range then emerges (10 slots → max 30) instead of being a separate rule. |
| Keep innate Strike/Defend + insurance floor | Rejected — owner chose full reversal, no insurance; auto-fill density (3 copies each of Strike/Defend in a padded deck) is the statistical floor. |

## Consequences

- **Schema:** per-character `skill_collection`, `active_loadout` (≤10 slot ids), and a deterministic `derive_deck()` (loadout → copies by rarity → auto-fill basics to 20). The deck stops being stored state and becomes a projection; upgrades/Ascension annotate **skills**, not card instances. All values data-driven ([ADR-0003](0003-data-driven-content-architecture.md)).
- **UI:** a skill-management screen per character (collection ↔ loadout, live preview of derived deck and cycle rate), surfaced at rest nodes and progression beats.
- **Status updates applied:** deck model of [ADR-0004](0004-shared-deck-character-tagged-cards.md)/[ADR-0016](0016-party-size-two-owner-tagged-cards.md) superseded (owner-tagging survives as skill ownership; party of 2 unchanged); [ADR-0005](0005-innate-strike-defend.md) superseded (reversed); [ADR-0025](0025-per-character-decks-and-hands.md)'s open deck question resolved.
- **Tunables for prototype:** slot count (10), copies per rarity (3/2/1), minimum (20), auto-fill ratio (Strike:Defend 1:1), per-character base energy (from [ADR-0025](0025-per-character-decks-and-hands.md)).
- **Risk:** no guaranteed basic action in hand. Accepted; monitor bricked-turn frequency in prototype — if it exceeds feel thresholds, the lightweight insurance floor from the design discussion is the prepared fallback.

## Open questions (deferred to prototyping)

- Exact hand size and draw count per character per turn (assumed 5 above; cycle math depends on it).
- Whether slot count itself grows across the run (e.g., +1 slot at tier walls) or stays fixed at 10.
- Auto-fill composition beyond 1:1 Strike/Defend (race-flavored basics?).
- Whether the two Act-1 pole identities (physical/caster) each feel distinct when decks are ~70% identical fill — may motivate race-flavored basic variants.
- **Injected non-skill card layer.** As decided, every card is a projection of a skill — clean but monochrome, and it removes StS-style deck-management pressure. Candidate fix: a card layer injected into the derived deck *after* derivation, outside the loadout:
  - **Curses/wounds/statuses** — forced in by enemies/events, can't be deactivated, must be *removed* (removal becomes a resource; shops/events get something to sell). Sub-question: do injected cards count toward the 20-card minimum (junk displaces fill) or sit on top (deck swells past the cap)?
  - **Consumable item cards** — found/bought cards that exhaust on use; one-run texture without touching the skill system.
  - **Derivation modifiers** — relics/boons that change projection rules ("+1 copy of a chosen skill," "Uncommons count as Common").
  - Related: **earned floor reduction** (rare relics/boons lowering the 20 minimum) as the gated path back to the small-deck reliability archetype.
