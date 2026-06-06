# Architecture Decision Records (ADRs)

Each file records one settled decision: its context, the choice, the alternatives, and the consequences. **ADRs are append-only.** To change a decision, write a *new* ADR that supersedes the old one and update the old one's Status — never rewrite a decided ADR's substance. The history is the value.

| # | Decision | Status |
|---|----------|--------|
| [0001](0001-card-driven-tactical-roguelite.md) | Adopt a card-driven tactical roguelite structure | Accepted |
| [0002](0002-engine-godot-gdscript.md) | Engine: Godot 4 + GDScript | Accepted |
| [0003](0003-data-driven-content-architecture.md) | Data-driven content architecture | Accepted |
| [0004](0004-shared-deck-character-tagged-cards.md) | Shared deck with character-tagged cards | Accepted |
| [0005](0005-innate-strike-defend.md) | Innate Strike/Defend, not in the deck | Accepted |
| [0006](0006-draw-as-cooldown-model.md) | Draw = cooldown; deck size is the cooldown dial | Accepted |
| [0007](0007-build-on-existing-templates.md) | Build on existing template code, wrapped behind our interfaces | Accepted |
| [0008](0008-target-platforms-distribution.md) | Target platforms & distribution (Steam + Steam Deck; itch.io web demo) | Accepted |
| [0009](0009-toolchain-and-version-control.md) | Toolchain & version control (Godot pin, git + private GitHub remote) | Accepted |
| [0010](0010-turn-order-strict-phases.md) | Turn order — strict player/enemy phases (prototype) | Accepted |
| [0011](0011-death-downed-and-hp-attrition.md) | Death, downed units, and HP attrition (hybrid: TPK ends run) | Accepted |

**Status values:** Proposed → Accepted → (later) Deprecated / Superseded by ADR-NNNN.
