# Data Schemas — Content Contracts

**Status:** Draft (prototype scope)
**Owners:** Michael; Claude
**Depends on:** [ADR-0003](../decisions/0003-data-driven-content-architecture.md) (data-driven), [ADR-0004](../decisions/0004-shared-deck-character-tagged-cards.md) (shared deck), [ADR-0005](../decisions/0005-innate-strike-defend.md) (innate Strike/Defend), [ADR-0006](../decisions/0006-draw-as-cooldown-model.md) (draw = cooldown)

> This document is a **contract**. Code reads these shapes; content authors fill them in. Anyone (human or agent) building a loader implements against these fields; anyone authoring a card/enemy/encounter populates exactly these fields. Changing a shape here is an interface change — flag it (and likely an ADR) before diverging.

---

## 1. Principles & conventions

- **Runtime format:** Godot `Resource` (`.tres`). **Authoring/bulk format:** JSON, baked or loaded into Resources. Both express the *same* shapes below.
- **IDs:** every entity has a globally unique `id` in `snake_case` (`StringName`). IDs are how entities reference each other (a card's `character_tag`, an encounter's `enemy` spawns). IDs are permanent — renaming one is a breaking change.
- **No balance magic numbers in code.** Every tunable (damage, cost, hp, hand size, deck size) lives in these data files, never inline in a script (ADR-0003).
- **Required vs optional:** fields marked **required** must be present; optional fields fall back to the listed **default**.
- **File layout under `/data`:**

  ```
  /data
    /cards         card_*.tres
    /characters    char_*.tres
    /enemies       enemy_*.tres
    /encounters    enc_*.tres
    /status        status_*.tres        (status-effect definitions)
    battle_config.tres                   (global battle tunables)
  ```

- **Validation:** the loader must validate on load — unknown `effect.type`, missing required fields, or dangling ID references are hard errors, surfaced loudly, not silently skipped.

---

## 2. Shared vocabulary (used by multiple entities)

### 2.1 TargetSpec
How an action chooses what it affects on the grid.

| Field | Type | Req | Default | Notes |
|-------|------|-----|---------|-------|
| `target_type` | StringName | yes | `enemy` | `self` \| `ally` \| `enemy` \| `any_unit` \| `tile` \| `empty_tile` |
| `range` | int | no | `1` | Tiles from the acting unit. `0` = self / no range. |
| `shape` | StringName | no | `single` | `single` \| `line` \| `area` |
| `radius` | int | no | `0` | For `area`: tiles from the chosen target. |

```gdscript
class_name TargetSpec extends Resource
@export var target_type: StringName = &"enemy"
@export var range: int = 1
@export var shape: StringName = &"single"
@export var radius: int = 0
```

### 2.2 Effect (the atomic action — the heart of the model)
A card or enemy intent is a **list of effects**. Each effect has a `type` discriminator the loader dispatches on. This is the extensibility seam: a new mechanic = a new effect `type` + its handler, authored as data everywhere else.

| Field | Type | Req | Default | Notes |
|-------|------|-----|---------|-------|
| `type` | StringName | yes | — | See registry in §2.3. |
| `amount` | int | no | `0` | Magnitude (damage, block, heal, stacks for some). |
| `status` | StringName | no | `""` | For `apply_status`: the status id (§2.4). |
| `stacks` | int | no | `0` | For `apply_status`: how many. |
| `target_override` | TargetSpec | no | null | If set, this effect retargets instead of using the card/intent target. |
| `params` | Dictionary | no | `{}` | Escape hatch for effect-specific data; keep usage rare and documented. |

```gdscript
class_name Effect extends Resource
@export var type: StringName
@export var amount: int = 0
@export var status: StringName = &""
@export var stacks: int = 0
@export var target_override: TargetSpec
@export var params: Dictionary = {}
```

### 2.3 Effect type registry
The loader maps each `type` to a handler. **Prototype set** (build these first):

| `type` | Meaning | Uses |
|--------|---------|------|
| `damage` | Deal `amount` damage to target. | `amount` |
| `block` | Grant `amount` block to target. | `amount` |
| `heal` | Restore `amount` HP. | `amount` |
| `apply_status` | Add `stacks` of `status` to target. | `status`, `stacks` |
| `move` | Move the acting unit toward/onto target tile. | `target_override` (tile) |
| `push` | Shove target `amount` tiles away. | `amount` |
| `draw` | Draw `amount` cards. | `amount` |
| `gain_energy` | Add `amount` energy this turn. | `amount` |

**Deferred (post-prototype):** `summon`, `teleport`, `pull`, `multi_hit`, `conditional`, `transform_card`. Add as new handlers; do not overload existing types.

### 2.4 Status / StatusData
Reusable status-effect definitions (`/data/status`).

| Field | Type | Req | Default | Notes |
|-------|------|-----|---------|-------|
| `id` | StringName | yes | — | e.g. `poison`, `block`, `stun`, `strength`, `weak`. |
| `display_name` | String | yes | — | UI label. |
| `stacking` | StringName | no | `intensity` | `intensity` (stacks add up) \| `duration` (counts down) \| `flag` (on/off). |
| `decays_each_turn` | bool | no | `true` | Whether stacks tick down each turn. |
| `icon` | Texture2D | no | null | Placeholder allowed. |

**Prototype statuses:** `block`, `poison`, `stun`, `strength`, `weak`.

---

## 3. Card / CardData

Cards are the action system (ADR-0004). Innate Strike/Defend are Cards flagged `innate: true`, referenced by a character and **never shuffled into the deck** (ADR-0005). Cooldown behavior is expressed via `keywords` (ADR-0006).

| Field | Type | Req | Default | Notes |
|-------|------|-----|---------|-------|
| `id` | StringName | yes | — | Unique. |
| `display_name` | String | yes | — | |
| `description` | String | no | `""` | If empty, UI may auto-generate from effects. |
| `character_tag` | StringName | yes | `neutral` | Owning character id, or `neutral` (any unit can play). |
| `energy_cost` | int | yes | `1` | Spent from the shared per-turn pool. |
| `keywords` | Array[StringName] | no | `[]` | `exhaust` (one-shot / very long cooldown), `return` (back to hand = short cooldown), `unplayable`, … |
| `innate` | bool | no | `false` | `true` = an innate action (Strike/Defend); lives on the character, not the deck. |
| `rarity` | StringName | no | `common` | `common` \| `uncommon` \| `rare`. Used by draft/reward pools. |
| `target` | TargetSpec | yes | — | How the card picks its target. |
| `effects` | Array[Effect] | yes | — | Ordered; applied in sequence. |
| `art` | Texture2D | no | null | Placeholder allowed. |
| `upgrade_of` | StringName | no | `""` | If this is a "+" version, the base card id. |

```gdscript
class_name CardData extends Resource
@export var id: StringName
@export var display_name: String
@export var description: String = ""
@export var character_tag: StringName = &"neutral"
@export var energy_cost: int = 1
@export var keywords: Array[StringName] = []
@export var innate: bool = false
@export var rarity: StringName = &"common"
@export var target: TargetSpec
@export var effects: Array[Effect] = []
@export var art: Texture2D
@export var upgrade_of: StringName = &""
```

**JSON authoring example — a signature skill:**
```json
{
  "id": "shield_bash",
  "display_name": "Shield Bash",
  "character_tag": "vanguard",
  "energy_cost": 1,
  "keywords": ["exhaust"],
  "rarity": "common",
  "target": { "target_type": "enemy", "range": 1, "shape": "single" },
  "effects": [
    { "type": "damage", "amount": 6 },
    { "type": "apply_status", "status": "stun", "stacks": 1 }
  ],
  "art": "res://assets/cards/shield_bash.png"
}
```

**JSON — an innate action (never in the deck):**
```json
{
  "id": "strike", "display_name": "Strike", "character_tag": "neutral",
  "innate": true, "energy_cost": 1,
  "target": { "target_type": "enemy", "range": 1 },
  "effects": [ { "type": "damage", "amount": 4 } ]
}
```

---

## 4. Character / CharacterData

A playable party unit (2–3 per run, ADR-0004).

| Field | Type | Req | Default | Notes |
|-------|------|-----|---------|-------|
| `id` | StringName | yes | — | Used as cards' `character_tag`. |
| `display_name` | String | yes | — | |
| `max_hp` | int | yes | `30` | |
| `move_range` | int | yes | `3` | Tiles per move. |
| `speed` | int | no | `10` | Turn-order / initiative input (if used). |
| `innate_actions` | Array[StringName] | yes | `["strike","defend"]` | Card ids flagged `innate`; never enter the deck (ADR-0005). |
| `starting_deck` | Array[StringName] | yes | `[]` | Card ids this character contributes to the shared deck. |
| `tags` | Array[StringName] | no | `[]` | Archetype hints (`melee`, `caster`, `support`). |
| `sprite` | Texture2D | no | null | Placeholder allowed. |

```gdscript
class_name CharacterData extends Resource
@export var id: StringName
@export var display_name: String
@export var max_hp: int = 30
@export var move_range: int = 3
@export var speed: int = 10
@export var innate_actions: Array[StringName] = [&"strike", &"defend"]
@export var starting_deck: Array[StringName] = []
@export var tags: Array[StringName] = []
@export var sprite: Texture2D
```

> **Deck assembly rule:** the run's shared deck = the union of each party member's `starting_deck` (plus cards drafted during the run). `character_tag` on each card controls who can *play* it; innate actions are excluded from the deck entirely.

---

## 5. Enemy / EnemyData

| Field | Type | Req | Default | Notes |
|-------|------|-----|---------|-------|
| `id` | StringName | yes | — | |
| `display_name` | String | yes | — | |
| `max_hp` | int | yes | `20` | |
| `move_range` | int | yes | `2` | |
| `speed` | int | no | `8` | |
| `intents` | Array[IntentData] | yes | — | Telegraphed actions (Slay-the-Spire style). |
| `intent_pattern` | StringName | no | `random_weighted` | `random_weighted` \| `sequence`. |
| `sprite` | Texture2D | no | null | Placeholder allowed. |

### IntentData
| Field | Type | Req | Default | Notes |
|-------|------|-----|---------|-------|
| `id` | StringName | yes | — | |
| `telegraph` | StringName | yes | `attack` | Icon shown to player: `attack` \| `block` \| `buff` \| `debuff` \| `move`. |
| `target` | TargetSpec | yes | — | |
| `effects` | Array[Effect] | yes | — | Reuses the §2.2 Effect model. |
| `weight` | int | no | `1` | Selection weight for `random_weighted`. |

```gdscript
class_name EnemyData extends Resource
@export var id: StringName
@export var display_name: String
@export var max_hp: int = 20
@export var move_range: int = 2
@export var speed: int = 8
@export var intents: Array[IntentData] = []
@export var intent_pattern: StringName = &"random_weighted"
@export var sprite: Texture2D

class_name IntentData extends Resource
@export var id: StringName
@export var telegraph: StringName = &"attack"
@export var target: TargetSpec
@export var effects: Array[Effect] = []
@export var weight: int = 1
```

---

## 6. Encounter / EncounterData

A single tactical skirmish (small grid, ADR-0001). Run/map structure that *sequences* encounters is a separate, later schema.

| Field | Type | Req | Default | Notes |
|-------|------|-----|---------|-------|
| `id` | StringName | yes | — | |
| `display_name` | String | yes | — | |
| `grid_size` | Vector2i | yes | `(6,6)` | Keep small (ADR-0001). |
| `terrain` | Array[TerrainCell] | no | `[]` | Sparse overrides; unset tiles default to `plains`. |
| `player_spawns` | Array[Vector2i] | yes | — | One per party unit. |
| `enemy_spawns` | Array[Spawn] | yes | — | `{ enemy: id, pos: Vector2i }`. |
| `win_condition` | StringName | yes | `defeat_all` | `defeat_all` \| `survive_turns` \| `reach_tile`. |
| `win_param` | int | no | `0` | Turns to survive, or packed tile for `reach_tile`. |
| `rewards` | Array[StringName] | no | `[]` | Card/relic ids granted on win (run layer; may be stubbed in prototype). |

`TerrainCell`: `{ pos: Vector2i, terrain: StringName }` where `terrain` ∈ `plains` \| `cover` \| `blocked` \| `hazard` (move cost / effects defined in a terrain table — deferred; prototype may treat all as `plains` except `blocked`).
`Spawn`: `{ enemy: StringName, pos: Vector2i }`.

**JSON authoring example:**
```json
{
  "id": "skirmish_01",
  "display_name": "Ambush at the Ford",
  "grid_size": [6, 6],
  "player_spawns": [[1, 2], [1, 3]],
  "enemy_spawns": [
    { "enemy": "grunt",  "pos": [4, 1] },
    { "enemy": "grunt",  "pos": [4, 3] },
    { "enemy": "archer", "pos": [5, 4] }
  ],
  "win_condition": "defeat_all"
}
```

---

## 7. BattleConfig (global tunables)

Single resource at `/data/battle_config.tres`. Holds the knobs ADR-0006 cares about (deck size lives implicitly in the assembled deck; these govern the per-turn economy).

| Field | Type | Default | Notes |
|-------|------|---------|-------|
| `energy_per_turn` | int | `3` | Shared pool refilled each player turn. |
| `draw_per_turn` | int | `5` | Cards drawn at turn start. |
| `max_hand` | int | `10` | Hand cap. |
| `reshuffle_discard` | bool | `true` | Discard reshuffles into draw when empty — the cooldown cycle (ADR-0006). |

---

## 8. Relationships

```
CharacterData.starting_deck ─┐
                             ├─► CardData.id        (character_tag → CharacterData.id, or "neutral")
CharacterData.innate_actions ┘        │
                                      ├─► Effect.type ∈ registry (§2.3)
                                      └─► Effect.status → StatusData.id
EnemyData.intents ─► IntentData ─► Effect (same model)
EncounterData.enemy_spawns.enemy ─► EnemyData.id
EncounterData.player_spawns ─► (party chosen at run start)
```

Every arrow is an ID reference the loader must validate.

---

## 9. How the loader consumes this (for the loader-builder agent)

1. Load all `StatusData`, `CardData`, `CharacterData`, `EnemyData`, `EncounterData` into typed registries keyed by `id`.
2. Validate: required fields present; every `effect.type` is in the registry; every ID reference resolves; no duplicate ids.
3. Expose lookups: `Cards.get(id)`, `Characters.get(id)`, etc.
4. Dispatch: an `EffectResolver` maps `effect.type` → handler `func(effect, source, target, battle_state)`.
5. Innate actions are loaded as Cards but registered to their character's action bar, excluded from deck assembly.

## 10. How to author content (for content-author agents)

- **New card:** create `/data/cards/card_<id>.tres` (or JSON) with the §3 fields. Only use `effect.type`s in the registry; if you need a new one, that's a code task, not a content task — flag it.
- **New enemy:** §5 fields; intents reuse the Effect model.
- **New encounter:** §6 fields; reference existing enemy ids and a valid grid.
- Keep all balance numbers in the data. Never edit a script to tune a value.

---

## 11. Prototype scope vs deferred

**In scope for the First Playable Prototype:** TargetSpec; Effect types `damage`/`block`/`heal`/`apply_status`/`move`/`draw`/`gain_energy`; statuses `block`/`poison`/`stun`/`strength`/`weak`; CardData, CharacterData (×1–2), EnemyData (×3 intents simple), one EncounterData, BattleConfig.

**Deferred:** terrain effects table, run/map node schema, rewards/relics schema, card upgrade trees, advanced effect types (§2.3 deferred list), line/area targeting beyond `single`.

## 12. Open schema questions

- Turn order: strict player-phase/enemy-phase, or `speed`-based initiative? (affects whether `speed` matters now)
- Block/armor model: does block carry over turns or reset? (affects StatusData defaults)
- Energy: strictly shared, or any per-character reserve? (currently strictly shared)
- Card targeting for multi-unit effects: resolved via `target_override` vs a dedicated `area` shape — confirm one path.
