# Architecture Decision Records (ADRs)

Each file records one settled decision: its context, the choice, the alternatives, and the consequences. **ADRs are append-only.** To change a decision, write a *new* ADR that supersedes the old one and update the old one's Status — never rewrite a decided ADR's substance. The history is the value.

| # | Decision | Status |
|---|----------|--------|
| [0001](0001-card-driven-tactical-roguelite.md) | Adopt a card-driven tactical roguelite structure | Accepted (grid pillar superseded by 0013) |
| [0002](0002-engine-godot-gdscript.md) | Engine: Godot 4 + GDScript | Accepted |
| [0003](0003-data-driven-content-architecture.md) | Data-driven content architecture | Accepted |
| [0004](0004-shared-deck-character-tagged-cards.md) | Shared deck with character-tagged cards | Superseded (party sizing by 0016; shared deck by 0026 — owner-tagging carries forward) |
| [0005](0005-innate-strike-defend.md) | Innate Strike/Defend, not in the deck | Superseded by 0026 (Strike/Defend are deck cards) |
| [0006](0006-draw-as-cooldown-model.md) | Draw = cooldown; deck size is the cooldown dial | Accepted |
| [0007](0007-build-on-existing-templates.md) | Build on existing template code, wrapped behind our interfaces | Accepted |
| [0008](0008-target-platforms-distribution.md) | Target platforms & distribution (Steam + Steam Deck; itch.io web demo) | Accepted |
| [0009](0009-toolchain-and-version-control.md) | Toolchain & version control (Godot pin, git + private GitHub remote) | Accepted |
| [0010](0010-turn-order-strict-phases.md) | Turn order — strict player/enemy phases (prototype) | Accepted |
| [0011](0011-death-downed-and-hp-attrition.md) | Death, downed units, and HP attrition (hybrid: TPK ends run) | Accepted |
| [0012](0012-run-structure-and-map.md) | Run structure & map (v1: StS branching map, card-draft rewards) | Accepted (single-act scope superseded by 0019) |
| [0013](0013-positionless-combat-drop-grid.md) | Positionless combat — drop the tactical grid | Accepted (supersedes grid pillar of 0001) |
| [0014](0014-stat-driven-characters.md) | Stat-driven characters (STR/DEX/CON/INT) power the floor and scale cards | Accepted |
| [0015](0015-classes-races-leveling.md) | Classes, races & player-allocated stat-point leveling | Accepted (class-as-base-template superseded by 0021) |
| [0016](0016-party-size-two-owner-tagged-cards.md) | Party size fixed at 2; cards owner-tagged & stat-scaled | Accepted (supersedes party sizing in 0004; shared-deck aspect superseded by 0026) |
| [0017](0017-keep-cards-energy-and-return.md) | Keep cards over cooldowns; base-3 shared energy; restricted `return` | Accepted (shared energy pool superseded by 0025) |
| [0018](0018-meta-progression-exit-package.md) | Meta-progression — exit-package extraction, horizontal boons | Accepted |
| [0019](0019-eighteen-act-dungeon-progression.md) | Eighteen-act dungeon progression & power curve (boss A12 = lvl 250) | Accepted (supersedes single-act scope of 0012) |
| [0020](0020-card-scaling-ladder.md) | Card scaling ladder — flat → hybrid → multiplier (symmetric, via `stat_mult`) | Accepted (extends 0014, 0016) |
| [0021](0021-deferred-class-race-origin.md) | Deferred class — race-base origin, class at Act 3, promotions at 6/9/12/15 | Accepted (promotion structure refined by 0022; supersedes class-as-template of 0015) |
| [0022](0022-class-progression-trees-ascension.md) | Class progression — branching trees at Acts 6/9/12, universal Ascension at Act 15 | Accepted (refines promotion structure of 0021; supersedes promotion branches of 0015) |
| [0023](0023-sts-style-map-run-structure.md) | StS-style map — bottom-up, fog-of-war, shop/treasure nodes | Accepted (supersedes map presentation & node-set of 0012) |
| [0024](0024-act-structured-squad-recruitment.md) | Act-structured squad recruitment — solo Act 1, RNG 1-of-3 race-only recruit at Act 2, both class at Act 3 | Accepted (supersedes one-race-for-the-pair rule of 0021) |
| [0025](0025-per-character-decks-and-hands.md) | Per-character **energy** pools (supersedes shared energy of 0017) — *deck/hand question resolved by 0026* | Accepted |
| [0026](0026-derived-decks-from-skill-loadouts.md) | Per-character derived decks from active skill loadouts — 10 slots, rarity→copies, 20-card min via basic auto-fill | Accepted (supersedes shared deck of 0004/0016; reverses 0005) |

**Status values:** Proposed → Accepted → (later) Deprecated / Superseded by ADR-NNNN.

> **2026-06-07 pivot:** ADRs 0013–0018 record a design shift — combat goes **positionless** (grid dropped), a **stat/class/leveling RPG layer** is added, and **party is fixed at 2** with owner-tagged, stat-scaled cards. The card, run-structure, death/attrition, engine, and data-driven pillars carry forward. The concept brief (`docs/concept/concept-brief.md`) predates this pivot and is now partially stale — the ADRs are binding where they differ.
