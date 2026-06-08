# Architecture Decision Records (ADRs)

Each file records one settled decision: its context, the choice, the alternatives, and the consequences. **ADRs are append-only.** To change a decision, write a *new* ADR that supersedes the old one and update the old one's Status — never rewrite a decided ADR's substance. The history is the value.

| # | Decision | Status |
|---|----------|--------|
| [0001](0001-card-driven-tactical-roguelite.md) | Adopt a card-driven tactical roguelite structure | Accepted (grid pillar superseded by 0013) |
| [0002](0002-engine-godot-gdscript.md) | Engine: Godot 4 + GDScript | Accepted |
| [0003](0003-data-driven-content-architecture.md) | Data-driven content architecture | Accepted |
| [0004](0004-shared-deck-character-tagged-cards.md) | Shared deck with character-tagged cards | Accepted (party sizing superseded by 0016) |
| [0005](0005-innate-strike-defend.md) | Innate Strike/Defend, not in the deck | Accepted |
| [0006](0006-draw-as-cooldown-model.md) | Draw = cooldown; deck size is the cooldown dial | Accepted |
| [0007](0007-build-on-existing-templates.md) | Build on existing template code, wrapped behind our interfaces | Accepted |
| [0008](0008-target-platforms-distribution.md) | Target platforms & distribution (Steam + Steam Deck; itch.io web demo) | Accepted |
| [0009](0009-toolchain-and-version-control.md) | Toolchain & version control (Godot pin, git + private GitHub remote) | Accepted |
| [0010](0010-turn-order-strict-phases.md) | Turn order — strict player/enemy phases (prototype) | Accepted |
| [0011](0011-death-downed-and-hp-attrition.md) | Death, downed units, and HP attrition (hybrid: TPK ends run) | Accepted |
| [0012](0012-run-structure-and-map.md) | Run structure & map (v1: StS branching map, card-draft rewards) | Accepted |
| [0013](0013-positionless-combat-drop-grid.md) | Positionless combat — drop the tactical grid | Accepted (supersedes grid pillar of 0001) |
| [0014](0014-stat-driven-characters.md) | Stat-driven characters (STR/DEX/CON/INT) power the floor and scale cards | Accepted |
| [0015](0015-classes-races-leveling.md) | Classes, races & player-allocated stat-point leveling | Accepted |
| [0016](0016-party-size-two-owner-tagged-cards.md) | Party size fixed at 2; cards owner-tagged & stat-scaled | Accepted (supersedes party sizing in 0004) |
| [0017](0017-keep-cards-energy-and-return.md) | Keep cards over cooldowns; base-3 shared energy; restricted `return` | Accepted |
| [0018](0018-meta-progression-exit-package.md) | Meta-progression — exit-package extraction, horizontal boons | Accepted |

**Status values:** Proposed → Accepted → (later) Deprecated / Superseded by ADR-NNNN.

> **2026-06-07 pivot:** ADRs 0013–0018 record a design shift — combat goes **positionless** (grid dropped), a **stat/class/leveling RPG layer** is added, and **party is fixed at 2** with owner-tagged, stat-scaled cards. The card, run-structure, death/attrition, engine, and data-driven pillars carry forward. The concept brief (`docs/concept/concept-brief.md`) predates this pivot and is now partially stale — the ADRs are binding where they differ.
