# ADR-0008: Target platforms & distribution

**Status:** Accepted
**Date:** 2026-06-05
**Deciders:** Michael (owner); Claude (build partner)

## Context

We need to know how players actually access the game, because it shapes input, save persistence, renderer, UI, and store overhead. The genre — a deckbuilding tactical roguelite — has a clear commercial home, and the owner's early "handheld" instinct has a modern answer. One Godot project can export to all targets, so this decision is about *primary aim*, not exclusivity.

## Decision

- **Primary release target: Steam** (desktop — Windows / macOS / Linux), with **Steam Deck** support treated as a first-class goal (this genre is ideal for handheld, pausable play).
- **Development, playtesting, and public demo: itch.io**, including an **HTML5 web build** used as a funnel to Steam wishlists.
- **Web is a demo channel, not the home.** It exists to lower the barrier to trying the game, not as the place it "ships."

## Options Considered

| Option | Role | Verdict |
|--------|------|---------|
| **Steam (desktop + Steam Deck)** | Commercial release | **Chosen — primary.** Where the genre's audience and revenue are. |
| **itch.io (desktop + web)** | Dev / demo / funnel | **Chosen — secondary.** Lowest-friction playtesting and a web demo. |
| Browser-only as the release | — | Rejected. Performance ceilings, fiddly save persistence, weak monetization. |
| Consoles (Switch, etc.) | — | Deferred. Requires ports + certification; revisit only post-PC success. |

**Cost note:** Steam Direct is a **one-time $100 fee per game, recoupable** once the game clears $1,000 in revenue. No subscription.

## Consequences

- **Support gamepad input from day one** (Steam Deck). Route everything through Godot input *actions*; never hardcode keys. (Feeds the input-abstraction requirement.)
- **Keep saves web-sandbox-friendly** if the web demo should retain progress: use Godot's `user://` (which maps to browser IndexedDB on web) and avoid OS-specific file assumptions.
- **Renderer = Compatibility** (already selected at project creation) to keep the web export viable — see [ADR-0009](0009-toolchain-and-version-control.md).
- **UI must be readable and controller-navigable at Steam Deck resolution (1280×800).**
- **Steamworks integration is deferred** to near-release; game logic must not couple to it.
