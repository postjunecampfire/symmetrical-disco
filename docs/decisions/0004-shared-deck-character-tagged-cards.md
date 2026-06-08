# ADR-0004: Shared deck with character-tagged cards

**Status:** Accepted — *party sizing (2–3) is superseded by [ADR-0016](0016-party-size-two-owner-tagged-cards.md) (fixed at 2); the shared-deck + character-tagged-cards model stands and is reaffirmed there.*
**Date:** 2026-06-05
**Deciders:** Michael (owner); Claude (build partner)

## Context

The game has a party of 2–3 controllable units *and* a card-based action system. The open question was how cards relate to multiple units without overwhelming the player. The thing that actually overwhelms players is not the number of units but the number of simultaneous **hands and resource pools**.

## Decision

Use a **single shared deck**. Each turn the player has **one hand and one energy pool**, regardless of party size. Cards are **tagged to a character** (only the knight can play this; only the mage can play that), with some **neutral** cards any unit can use. **Controllable party is 2–3 (prototype with 2).**

## Options Considered

- **Per-unit decks (a deck/hand each)** — Rejected. Multiplies cognitive load and turn time; breaks the Slay-the-Spire "one hand" rhythm.
- **Single player-character + AI allies** — Rejected as the core model. Loses the Fire Emblem feel of piloting a distinct roster. (Retained as *occasional* scripted NPC allies, outside the deck.)
- **Shared deck, character-tagged cards** — **Chosen.** Keeps roster distinctiveness (grid units play differently) while holding cognitive load at one hand. Proven by Trials of Fire / Banners of Ruin.

## Consequences

- One hand to read per turn no matter the party size — the load-bearing reason a multi-character card game stays playable.
- **Party composition shapes the card pool**, which doubles as the character-creation mechanic.
- Risk of a "dead hand" (cards for a down/out-of-position unit) — mitigated by innate Strike/Defend (see [ADR-0005](0005-innate-strike-defend.md)).
- Deck size couples to party size, feeding the cooldown model (see [ADR-0006](0006-draw-as-cooldown-model.md)); this is why the party is capped at 2–3.
