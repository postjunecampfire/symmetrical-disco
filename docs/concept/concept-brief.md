# Concept Brief — "Unnamed Game" (Working Title)

*Document of record. Captures the original framing of the design.*

> **⚠️ Predates the 2026-06-07+ pivot — the ADRs are binding where they differ.** Two pillars in this brief have since changed:
> 1. **The tactical grid is cut.** Combat is now **positionless** (Slay-the-Spire-style, no tiles/movement/range/terrain/facing) — see [ADR-0013](../decisions/0013-positionless-combat-drop-grid.md). With the grid gone, the game's differentiator is the **stat/class/leveling RPG layer** (ADRs [0014](../decisions/0014-stat-driven-characters.md), [0015](../decisions/0015-classes-races-leveling.md), [0021](../decisions/0021-deferred-class-race-origin.md), [0022](../decisions/0022-class-progression-trees-ascension.md)), not positioning.
> 2. **Party is fixed at 2 and recruited in-run.** The run is **solo in Act 1**, then offers an **RNG 1-of-3 race-only recruit at Act 2**; both characters pick their class together at Act 3 ([ADR-0024](../decisions/0024-act-structured-squad-recruitment.md)). Whether the two characters share one deck and energy pool or each carry their own is under revision ([ADR-0025](../decisions/0025-per-character-decks-and-hands.md), Proposed).
>
> Sections below describing grid/board positioning and run-start party loadout are superseded accordingly. See [`docs/decisions/`](../decisions/README.md) for the live record.

---

## 1. One-line pitch

A **card-driven tactical roguelite**: Slay the Spire's run structure and deckbuilding, Fire Emblem's grid positioning and character depth, played as a series of small, sharp tactical skirmishes across a single death-restarts run.

**North-star references:** *Fights in Tight Spaces* and *Trials of Fire* (card + grid + roguelite), *Into the Breach* (tight tactical encounters), *Slay the Spire* (run loop, deckbuilding, the card mechanic itself).

---

## 2. Design pillars

1. **Playable first.** The goal is a game the designer actually wants to play. Content and feel beat engineering elegance. Let the engine carry the plumbing; spend effort on battles, characters, and the run.
2. **Roguelite run structure.** Death leads to a full restart (Slay the Spire model), with save points between encounters. Run-scoped state (what you have this run) sits on top of meta-progression (what persists across deaths).
3. ~~**Tactical grid combat.** Fire Emblem–style positioning: small grids, terrain, range, facing.~~ **Superseded ([ADR-0013](../decisions/0013-positionless-combat-drop-grid.md)): combat is positionless.** Encounters are tight, puzzle-sharp deckbuilding fights (Slay-the-Spire abstract — party vs. enemies, targets picked directly), not sprawling armies and not a spatial board.
4. **Cards as the action system.** A shared deck drives what units can do each turn. Deckbuilding *is* the progression.
5. **Character depth & creation.** A small roster of distinct, customizable characters; party composition shapes the run.
6. **Bounded, deferred art.** Prototype with placeholder/free assets; commission custom art only after the loop is proven fun.

---

## 3. Core combat loop

Each turn the player has **one shared hand and one shared energy pool**, regardless of party size.

- **Shared deck, character-tagged cards.** The whole party draws from a single deck. Cards are tagged to a character (only the knight can play this; only the mage can play that), with some neutral cards anyone can use. This preserves Fire Emblem's "control a roster of distinct units" feel while keeping cognitive load at Slay the Spire's "one hand per turn" level. *(This is the load-bearing decision — it's why a multi-character card game stays manageable.)*
- **Innate Strike / Defend.** Every character always has Strike and Defend available as innate actions — *not* cards in the deck. This solves the "dead hand" failure (drawing cards for a unit who's down or out of position), keeps the deck full of only interesting skills, and means the baseline floor scales automatically with party size.
- **Drawn cards are the spikes.** Strike/Defend are the reliable, modest floor; drawn cards are the combos, utility, and burst that make a turn exciting. Balance contract: Strike/Defend still cost energy or a unit's action, so drawn cards are what let you exceed the baseline. Every draw should feel like an opportunity, not noise.
- ~~**Grid resolution.** Cards (and Strike/Defend) play out on a small grid where terrain, range, and positioning matter.~~ **Superseded ([ADR-0013](../decisions/0013-positionless-combat-drop-grid.md)): positionless resolution.** Cards (and Strike/Defend) resolve against directly-selected targets; there is no spatial layer.

### The "draw = cooldown" model
Drawing a card represents a skill **coming off cooldown** and becoming available again. This reframes standard card-cycling as a cooldown system and yields two useful properties:

- **Deck size is the global cooldown dial.** Small deck → each skill resurfaces often → short effective cooldown. Large deck → skills appear rarely → long cooldown.
- **Existing card mechanics map onto cooldown semantics.** A card that *exhausts* = a one-shot or very-long-cooldown ability; a card that *returns to hand* = a short cooldown; shuffle frequency = baseline cooldown length.

This ties directly to party sizing: more characters → more signature cards in the pool → slower cycling. So either keep parties small or accept longer cooldowns.

---

## 4. Party & deck sizing

- **Controllable party: 2–3 units** (not 4 — four bloats both the board and the card pool). **Prototype with 2.**
- **Deck composition:** mostly meaningful skill cards; no filler Strikes needed (those are innate). A smaller share of signature character cards, padded with neutral cards as connective tissue.
- **Deck size scales with party, but draw stays tight** to preserve consistency and the cooldown relationship above.
- **NPC allies** exist but are *not* the core mechanic: occasional AI-controlled allies in specific fights (story beats, rescue/escort, guest characters), running on simple AI and outside the player's deck.

---

## 5. Progression & character creation

- **Run-scoped acquisition (Slay the Spire form):** pick up cards, powers/relics, and stat growth as a run unfolds, layered on a Fire Emblem–style stat/skill framework.
- **Character creation = party composition + starting deck/archetype.** Choosing which 2–3 characters you run determines which cards you can draft during the run, so party choice *is* a creation/build decision.
- **Meta-progression:** persistent unlocks across deaths (new characters, cards, starting options) — exact model TBD.

---

## 6. Encounter & run structure

- **Run = Slay the Spire-style node map:** a sequence of encounters with branching paths, **save points between fights**, and a full restart on death.
- **Encounters = small, sharp tactical skirmishes** (Into the Breach / Fights in Tight Spaces scale), not large Fire Emblem battle maps. Big deck, small board.
- Long, accretive *run*; short, tight *fights*.

---

## 7. Technology

- **Engine: Godot** (2D-first, free/open-source, no royalties, strong tilemap workflow). Chosen over a purpose-built engine (e.g. Lex Talionis) because the roguelite + card + custom-progression systems are things we *compose*, not content we author into an existing campaign engine.
- **Language: GDScript** (Python-like, low boilerplate) and/or C# if static typing is preferred.
- **Build model: partnership** — same approach as the designer's prior Slay the Spire mod. The card-as-data + effect-hook pattern from that mod transfers almost directly here, which is why a card-driven design is the friendliest architecture for a limited-coding build.
- **Data-driven design:** cards, characters, enemies, and encounters authored as data so balance and content don't require recompiling.

---

## 8. Art approach

- **Placeholder-first.** Prototype entirely with free/placeholder assets (itch.io tactical sprite packs, free tilesets). Validate fun before spending money — art is the most expensive and most *replaceable* layer.
- **Bounded scope.** A tactical grid game needs far less unique art than a JRPG: a handful of unit sprites, one reusable tileset, a few effects, plus card-frame UI.
- **Commission later, piecemeal.** Hire an artist only once the core loop is proven; card art and unit sprites can be ordered incrementally.

---

## 9. Open questions / decisions still to make

- Meta-progression model: what exactly persists across deaths?
- Energy economy specifics: cost of Strike/Defend vs. drawn cards; energy per turn.
- Grid size and turn order (per-unit initiative vs. player-phase/enemy-phase).
- Enemy AI approach (utility scoring vs. scripted intents à la Slay the Spire).
- Theme, setting, and characters (none chosen yet).
- Win condition / run length (number of encounters per run).

---

## 10. Proposed first milestone (for discussion)

The smallest version that is actually *playable and fun*:

- **1–2 controllable characters**, innate Strike/Defend.
- **A starter deck of ~10 cards** with character tags and a few cooldown behaviors (exhaust / return).
- **One small grid**, terrain optional.
- **Three enemies** with simple intent-based AI.
- **A single encounter** with clear win/lose and a basic energy economy.

Goal: prove the shared-deck + grid + cooldown feel before building the run layer, meta-progression, or any custom art.

---

*Last updated: June 5, 2026.*
