# ADR-0006: Draw = cooldown; deck size is the cooldown dial

**Status:** Accepted
**Date:** 2026-06-05
**Deciders:** Michael (owner); Claude (build partner)

## Context

Skills need an availability/cooldown model. Rather than bolt a separate timer system onto a card game, we can let the deck's natural draw/discard/reshuffle cycle *be* the cooldown mechanism.

## Decision

Treat **drawing a skill as that skill coming off cooldown.** This makes **deck size the global cooldown dial**: a small deck means each skill resurfaces often (short effective cooldown); a large deck means skills appear rarely (long cooldown). Standard card mechanics map onto cooldown semantics:

- **Exhaust** = a one-shot or very-long-cooldown ability.
- **Return-to-hand** = a short cooldown.
- **Shuffle frequency** = the baseline cooldown length.

## Options Considered

- **Separate per-skill cooldown timers** — Rejected. Redundant with card cycling; adds a parallel system to balance and display.
- **Draw-as-cooldown (deck cycling)** — **Chosen.** Gives a cooldown system "for free," with one intuitive designer-facing knob.

## Consequences

- A whole cooldown system emerges from card mechanics already being built.
- Deck size couples to party size and to balance (more characters → more signature cards → slower cycling), reinforcing the 2–3 party cap from [ADR-0004](0004-shared-deck-character-tagged-cards.md).
- Designers tune ability frequency by adjusting deck size and card keywords (exhaust / return) rather than editing timers.
- Requires deliberate deck-size tuning per party configuration.
