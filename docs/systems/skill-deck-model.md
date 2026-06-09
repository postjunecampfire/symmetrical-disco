# Skill-Management Deck Model — design discussion

**Status:** DECIDED — adopted (with owner modifications) as [ADR-0026](../decisions/0026-derived-decks-from-skill-loadouts.md). Key deltas from these notes: Strike/Defend reversal **without** an insurance floor; loadout bounded by **10 skill slots** (deck max 30 emerges) with a **20-card minimum enforced by basic auto-fill**; activation at **rest nodes + progression beats**. These notes are retained as design rationale.
**Date:** 2026-06-09
**Owner:** Michael · **Partner:** Claude
**Tracked by:** Asana *"Design: per-character skill management & deck-population system."*
**Touches:** [ADR-0005](../decisions/0005-innate-strike-defend.md) (innate Strike/Defend — this model would **reverse** it), [ADR-0006](../decisions/0006-draw-as-cooldown-model.md) (draw = cooldown), [ADR-0017](../decisions/0017-keep-cards-energy-and-return.md) / [ADR-0025](../decisions/0025-per-character-decks-and-hands.md) (energy), [ADR-0020](../decisions/0020-card-scaling-ladder.md) (rarity ↔ scaling), [ADR-0021](../decisions/0021-deferred-class-race-origin.md) / [ADR-0022](../decisions/0022-class-progression-trees-ascension.md) (skills accrue across the run), [ADR-0012](../decisions/0012-run-structure-and-map.md) (card-reward / rest-upgrade).

---

## The problem we're backing into

Per-character **energy** is settled ([ADR-0025](../decisions/0025-per-character-decks-and-hands.md)). Per-character **decks** are agreed *in principle* — but **manually managing two literal decks may not be fun**, and there's a deeper issue underneath it:

> Cards should reflect a character's **current** skills/abilities, with cooldown expressed as a skill's **frequency in the deck** ([ADR-0006](../decisions/0006-draw-as-cooldown-model.md)). But skills/abilities **change across a run** (class at Act 3, branches at 6/9/12, Ascension at 15 — [ADR-0021](../decisions/0021-deferred-class-race-origin.md)/[ADR-0022](../decisions/0022-class-progression-trees-ascension.md)). So *what happens to old skills/powers*, and how does the player keep a deck coherent without fiddly card-by-card management?

## Proposed model: the deck is a *derived view* of an active skill loadout

The player curates **skills**, not individual cards. Each character has:

1. **A skill collection** — every skill/power they've acquired this run (drafts, class pick, promotions, Ascension). Skills are never lost; old ones go **inactive**.
2. **An active loadout** — the subset the player has **activated**.
3. **A derived deck** — the system auto-populates a deck of **20 (min) – 30 (max) cards** from the active loadout, with each skill contributing **copies according to its rarity**.

The player's decision space is "which skills are active," not "how many copies of card X." The deck — and therefore the cooldown cadence ([ADR-0006](../decisions/0006-draw-as-cooldown-model.md)) — falls out of that.

### Rarity → copy count (the per-skill cooldown dial)

Rarity sets how many copies of a skill land in the deck, which *is* its effective cooldown:

| Skill rarity | Copies in deck | Effective cooldown | Pairs with [ADR-0020](../decisions/0020-card-scaling-ladder.md) |
|---|---|---|---|
| Common | 3–4 | Short — resurfaces often | Flat (A) — reliable floor |
| Uncommon | 2 | Medium | Hybrid (B) — bridge |
| Rare | 1 | Long — shows rarely | Multiplier (C) — guardrailed spike |

This **meshes cleanly with the card-scaling ladder** ([ADR-0020](../decisions/0020-card-scaling-ladder.md)): the rarest skills are the biggest multipliers *and* the longest cooldowns, so power and scarcity reinforce each other automatically — a rare ×3 multiplier that appears once per shuffle is self-limiting, exactly the guardrail 0020 wants.

### Deck size (20–30) is the second dial

Per [ADR-0006](../decisions/0006-draw-as-cooldown-model.md), total deck size is the *global* cooldown dial. Here it becomes a **player-facing knob**: a lean 20-card deck cycles fast (signature skills come around often, less variety); a 30-card deck cycles slower (more breadth, rarer spikes). Choosing how full to pack the loadout is itself a build decision, bounded so it can't degenerate (too small = combo loop; too large = nothing reliable).

---

## The starting-deck problem → Strike/Defend should become cards

**This is the consequential bit Michael flagged.** If the deck must hold ≥20 cards drawn only from activated skills, then **at run start a classless, race-only origin character ([ADR-0021](../decisions/0021-deferred-class-race-origin.md)) has almost no skills** — not nearly enough to fill 20. Something has to be the floor.

**Proposal: make Strike and Defend ordinary common skills (cards in the deck), reversing [ADR-0005](../decisions/0005-innate-strike-defend.md)'s "innate, not in the deck."**

- At Act 1, a deck is mostly **Strike ×N + Defend ×N** plus a couple of race/starter skills — they *are* the 20-card floor.
- As the player drafts skills and picks a class, they **activate new skills and deactivate basics** to stay within 20–30. The deck **thins from generic toward signature** over the run — the familiar, satisfying Slay-the-Spire de-basic arc (which Michael has shipped a mod for).
- "What happens to old skills" is answered the same way: **deactivate, keep in the collection, re-activate later.** Nothing is stripped.

### Why reversing ADR-0005 is now defensible

ADR-0005 made Strike/Defend innate for three reasons; **two no longer hold**, and the third is weaker:

| ADR-0005 rationale | Status under this model |
|---|---|
| Avoid a "dead hand" for a **down / out-of-position** unit | **Mostly moot** — combat is positionless ([ADR-0013](../decisions/0013-positionless-combat-drop-grid.md)), so "out of position" is gone; with per-character decks a character only ever draws *their own* cards. Only "downed" remains, and a downed unit isn't drawing anyway. |
| Innate floor **scales automatically with party size** | **Moot** — decks are now per-character, not a shared pool sized to the party. |
| Keep the deck **"all-signal"** (no filler) | **Weaker / reframed** — basics aren't filler here, they're the **early-game floor and the cooldown texture**; the deck-thinning arc *is* the progression. |

So the original anti-dead-hand purpose of 0005 is largely solved by other decisions already, and folding Strike/Defend into the deck is what makes a 20-card minimum coherent from turn one.

**Cost to weigh:** we give up the guarantee that *every* hand has a basic action available. Mitigations: keep Strike/Defend **common (3–4 copies)** so they're statistically almost always present; optionally retain a light "if your hand has no playable card, you may make a basic attack" floor as insurance (a much smaller commitment than full innate Strike/Defend). Energy cost on basics still applies ([ADR-0005](../decisions/0005-innate-strike-defend.md) balance contract, [ADR-0017](../decisions/0017-keep-cards-energy-and-return.md)) so drawn signature skills stay the spikes.

---

## How it meshes with the rest of the design

- **[ADR-0006](../decisions/0006-draw-as-cooldown-model.md) (draw = cooldown):** unchanged and *strengthened* — cooldown now has two clean dials (per-skill rarity → copies; total deck size 20–30). Exhaust = one-shot; `return` = short cooldown still apply per card.
- **[ADR-0017](../decisions/0017-keep-cards-energy-and-return.md) / [ADR-0025](../decisions/0025-per-character-decks-and-hands.md) (energy):** orthogonal — energy is the per-turn spend brake, deck composition is the availability/cooldown layer. Both per character.
- **[ADR-0020](../decisions/0020-card-scaling-ladder.md) (scaling ladder):** strongly synergistic — rarity already drives both copy count *and* scaling tier, so scarcity and power line up by construction (see table above).
- **[ADR-0021](../decisions/0021-deferred-class-race-origin.md)/[ADR-0022](../decisions/0022-class-progression-trees-ascension.md) (progression):** class pick / promotions / Ascension **grant skills into the collection**; the player then activates them. Ascension's "flat boost to every card in the deck" applies to the derived deck; the appended **Ult** is a rare (1-copy) skill — naturally long-cooldown.
- **[ADR-0012](../decisions/0012-run-structure-and-map.md) (rewards / rest upgrades):** card-reward drafts become **skill** drafts; a rest-node "upgrade a card" becomes "**upgrade a skill**," and all its copies upgrade at once — cleaner than upgrading one physical copy.
- **[ADR-0016](../decisions/0016-party-size-two-owner-tagged-cards.md) (owner-tagged):** each skill belongs to one character; each character has their own collection, loadout, and derived deck. Two characters → two loadouts to manage, but the unit of management is *skills*, not loose cards — which is the answer to the "managing two decks isn't fun" worry.

---

## Open questions to settle before writing the ADR

1. **Activation friction:** can you re-activate/deactivate **anytime out of combat**, only at **rest nodes**, or only at progression beats? (Anytime = flexible but low-stakes; rest-gated = StS-like deliberateness.)
2. **Loadout constraint:** is the only cap the **20–30 card** bound, or also a **max number of active skills** (a "slots" model)?
3. **Frequency formula:** exact copies per rarity, and how rounding interacts with the 20–30 bound when the active set doesn't divide evenly. Auto-fill with basics to reach 20?
4. **Strike/Defend reversal — confirm.** Fold them into the deck as common skills (reverse [ADR-0005](../decisions/0005-innate-strike-defend.md))? Keep a minimal "no playable card" insurance floor or not?
5. **Two pole identities still hold?** Confirm a physical and a caster character each get a coherent ≥20-card floor at Act 1 from race-only skills + basics.
6. **Does this replace [ADR-0025](../decisions/0025-per-character-decks-and-hands.md)'s "two physical decks"** with "one derived deck per character from an active loadout"? (Recommended framing — same per-character outcome, but the player curates skills, not decks.)
7. **UI:** the skill-management screen (collection ↔ active loadout, with a live preview of the resulting deck and its cycle rate).
