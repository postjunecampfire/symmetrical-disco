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
How an action chooses what it affects. **Positionless (ADR-0013): targeting is by
KIND, not location** — there is no range/shape/radius and no board.

| Field | Type | Req | Default | Notes |
|-------|------|-----|---------|-------|
| `target_type` | StringName | yes | `enemy` | `self` \| `ally` \| `all_allies` \| `enemy` \| `all_enemies` \| `random_enemy` |

```gdscript
class_name TargetSpec extends Resource
@export var target_type: StringName = &"enemy"
```

Single-target kinds (`enemy`, `ally`) take one chosen unit; group kinds
(`all_allies`, `all_enemies`) resolve to every living unit on that side; `self`
is the acting unit; `random_enemy` picks one living opponent. Resolution lives in
`BattleState.resolve_targets(spec, actor, chosen)`.

### 2.2 Effect (the atomic action — the heart of the model)
A card or enemy intent is a **list of effects**. Each effect has a `type` discriminator the loader dispatches on. This is the extensibility seam: a new mechanic = a new effect `type` + its handler, authored as data everywhere else.

| Field | Type | Req | Default | Notes |
|-------|------|-----|---------|-------|
| `type` | StringName | yes | — | See registry in §2.3. |
| `amount` | int | no | `0` | Magnitude (damage, block, heal, stacks for some). |
| `status` | StringName | no | `""` | For `apply_status`: the status id (§2.4). |
| `stacks` | int | no | `0` | For `apply_status`: how many. |
| `params` | Dictionary | no | `{}` | Escape hatch for effect-specific data; keep usage rare and documented. |

```gdscript
class_name Effect extends Resource
@export var type: StringName
@export var amount: int = 0
@export var status: StringName = &""
@export var stacks: int = 0
@export var params: Dictionary = {}
```

Positionless (ADR-0013): there is **no per-effect `target_override`**. Every effect
in a card/intent applies to that card/intent's single resolved target set.
Group target kinds (`all_*`) apply targeted effects to each unit; global effects
(`draw`, `gain_energy`) fire once regardless of target-set size.

### 2.3 Effect type registry
The loader maps each `type` to a handler. **Prototype set** (build these first):

| `type` | Meaning | Uses |
|--------|---------|------|
| `damage` | Deal `amount` damage to target. | `amount` |
| `block` | Grant `amount` block to target. | `amount` |
| `heal` | Restore `amount` HP. | `amount` |
| `apply_status` | Add `stacks` of `status` to target. | `status`, `stacks` |
| `draw` | Draw `amount` cards. | `amount` |
| `gain_energy` | Add `amount` energy this turn. | `amount` |

**ADR-0028 (DCC adaptation) extensions:**

| `type` | Meaning | Uses |
|--------|---------|------|
| `self_damage` | Caster-side tax: `amount` damage to the CASTER, once per card regardless of target set. Block absorbs; never stat-amplified. | `amount` |
| `self_block` | Caster-side rider: `amount` block to the CASTER, once per card. DEX-scaled like any block grant. | `amount` |
| `charm_damage` | Attack: deal `amount` damage, then apply Charm equal to the UNBLOCKED portion. Scales like `damage`. | `amount`, `stat_mult` |
| `consume_status_damage` | Deal damage equal to the target's stacks of `status`, then remove them all (Coup de Grace). Not stat-scaled. | `status` |
| `add_card` | Add the card `params.card_id` to the CASTER's hand (token generation); overflow past max_hand goes to discard. Global (once per card). | `params.card_id` |

Positionless (ADR-0013): `move` and `push` were **removed with the grid**.

**Deferred (post-prototype):** `summon`, `multi_hit`, `conditional`, `transform_card`. Add as new handlers; do not overload existing types.

### 2.4 Status / StatusData
Reusable status-effect definitions (`/data/status`).

| Field | Type | Req | Default | Notes |
|-------|------|-----|---------|-------|
| `id` | StringName | yes | — | e.g. `poison`, `block`, `stun`, `strength`, `weak`. |
| `display_name` | String | yes | — | UI label. |
| `stacking` | StringName | no | `intensity` | `intensity` (stacks add up) \| `duration` (counts down) \| `flag` (on/off). |
| `decays_each_turn` | bool | no | `true` | Whether stacks tick down each turn. |
| `icon` | Texture2D | no | null | Placeholder allowed. |

**Prototype statuses:** `block`, `poison`, `stun`, `strength`, `weak` (+ `vulnerable`, `frail`).
**ADR-0028:** `charm` — intensity-stacking, never decays. Behaviour in code
(BattleState): every 10 stacks crossed applies 2 Vulnerable + 2 Weak; at stacks
>= the target's max HP the target is executed (hp -> 0, bypasses block).

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
| `signature` | bool | no | `false` | Tree-signature skill (M3): granted only by a progression-node `unlock_cards` pick; excluded from draft/shop pools. |
| `card_kind` | StringName | no | `skill` | `skill` \| `curse` \| `consumable` (ADR-0029). Non-`skill` cards NEVER enter draft/shop/treasure reward pools. Curses are per-member, count toward the derived-deck floor (displacing auto-fill basics); consumables are party inventory injected on top, consumed when played. |
| `on_draw_damage` | int | no | `0` | Curse downside (ADR-0029): damage the DRAWING unit takes when this card is drawn (blockable). |

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

A playable party unit (party of 2, ADR-0016). **Stats (ADR-0014):** STR -> physical
damage, DEX -> block, CON -> max HP, INT -> magic damage. `attack_stat` selects
which stat powers this character's attacks. `max_hp` is **derived** by the loader
as `constitution * BattleConfig.hp_per_con` (not authored directly).

| Field | Type | Req | Default | Notes |
|-------|------|-----|---------|-------|
| `id` | StringName | yes | — | Used as cards' `character_tag`. |
| `display_name` | String | yes | — | |
| `strength` | int | no | `0` | Physical attack bonus (when `attack_stat == str`). |
| `dexterity` | int | no | `0` | Block bonus. |
| `constitution` | int | yes | `0` | Drives `max_hp` (= CON × `hp_per_con`). |
| `intelligence` | int | no | `0` | Magic attack bonus (when `attack_stat == int`). |
| `attack_stat` | StringName | yes | `str` | `str` \| `dex` \| `int` — which stat boosts this character's attacks (fighter/rogue/mage). |
| `speed` | int | no | `10` | Unused under strict phases (ADR-0010). |
| `innate_actions` | Array[StringName] | yes | `["strike","defend"]` | Card ids flagged `innate`; never enter the deck (ADR-0005). |
| `starting_deck` | Array[StringName] | yes | `[]` | Card ids this character contributes to the shared deck. |
| `tags` | Array[StringName] | no | `[]` | Archetype hints (`melee`, `caster`, `support`). |
| `sprite` | Texture2D | no | null | Placeholder allowed. |

`max_hp` is computed, not authored — do not set it in JSON.

```gdscript
class_name CharacterData extends Resource
@export var id: StringName
@export var display_name: String
@export var max_hp: int = 30          # derived from CON by the loader
@export var speed: int = 10
@export var strength: int = 0
@export var dexterity: int = 0
@export var constitution: int = 0
@export var intelligence: int = 0
@export var attack_stat: StringName = &"str"
@export var innate_actions: Array[StringName] = [&"strike", &"defend"]
@export var starting_deck: Array[StringName] = []
@export var tags: Array[StringName] = []
@export var sprite: Texture2D
```

**Stat application (ADR-0014):** outgoing attack damage = base + the attacker's
`attack_stat` value (STR or INT) + Strength stacks, then Weak; block = base + the
source's DEX. Enemies have no stats, so their authored intent damage is flat.

> **Deck assembly rule:** the run's shared deck = the union of each party member's `starting_deck` (plus cards drafted during the run). `character_tag` on each card controls who can *play* it; innate actions are excluded from the deck entirely.

---

## 5. Enemy / EnemyData

| Field | Type | Req | Default | Notes |
|-------|------|-----|---------|-------|
| `id` | StringName | yes | — | |
| `display_name` | String | yes | — | |
| `max_hp` | int | yes | `20` | |
| `speed` | int | no | `8` | Unused under strict phases (ADR-0010). |
| `intents` | Array[IntentData] | yes | — | Telegraphed actions (Slay-the-Spire style). |
| `intent_pattern` | StringName | no | `random_weighted` | `random_weighted` \| `sequence`. |
| `sprite` | Texture2D | no | null | Placeholder allowed. |

### IntentData
| Field | Type | Req | Default | Notes |
|-------|------|-----|---------|-------|
| `id` | StringName | yes | — | |
| `telegraph` | StringName | yes | `attack` | Icon shown to player: `attack` \| `block` \| `buff` \| `debuff`. |
| `target` | TargetSpec | yes | — | |
| `effects` | Array[Effect] | yes | — | Reuses the §2.2 Effect model. |
| `weight` | int | no | `1` | Selection weight for `random_weighted`. |

```gdscript
class_name EnemyData extends Resource
@export var id: StringName
@export var display_name: String
@export var max_hp: int = 20
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

A single skirmish. **Positionless (ADR-0013): no grid, terrain, or spawn
coordinates** — an encounter is a flat roster of enemy ids plus the win
condition. The party (and its carried HP / run deck) comes from the caller
(RunState in the run layer, ADR-0012). Run/map structure that *sequences*
encounters is a separate schema (`run-structure.md`).

| Field | Type | Req | Default | Notes |
|-------|------|-----|---------|-------|
| `id` | StringName | yes | — | |
| `display_name` | String | yes | — | |
| `enemies` | Array[StringName] | yes | — | Enemy ids, resolved to EnemyData at assembly. |
| `win_condition` | StringName | yes | `defeat_all` | `defeat_all` \| `survive_turns`. |
| `win_param` | int | no | `0` | Turns to survive (for `survive_turns`). |
| `rewards` | Array[StringName] | no | `[]` | Card/relic ids granted on win (run layer; may be stubbed in prototype). |

**JSON authoring example:**
```json
{
  "id": "skirmish_01",
  "display_name": "Ambush at the Ford",
  "enemies": ["grunt", "archer", "brute"],
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
| `hp_per_con` | int | `2` | HP granted per point of CON; a character's `max_hp` = CON × this (ADR-0014). |

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
- **New encounter:** §6 fields; reference existing enemy ids (positionless — no grid/spawns).
- Keep all balance numbers in the data. Never edit a script to tune a value.

---

## 11. Prototype scope vs deferred

**In scope for the First Playable Prototype:** TargetSpec (positionless kinds); Effect types `damage`/`block`/`heal`/`apply_status`/`draw`/`gain_energy`; statuses `block`/`poison`/`stun`/`strength`/`weak`; CardData, CharacterData (×2), EnemyData, EncounterData, BattleConfig.

**Deferred:** run/map node schema, rewards/relics schema, card upgrade trees, advanced effect types (§2.3 deferred list). Positional concepts (grid, terrain, `move`/`push`, per-effect `target_override`, line/area shapes) were **removed** under ADR-0013, not deferred.

## 12. Open schema questions

- Block/armor model: does block carry over turns or reset? (affects StatusData defaults — prototype resets each turn)
- Energy: strictly shared, or any per-character reserve? (currently strictly shared)
- Multi-unit targeting is resolved by the `all_allies` / `all_enemies` target kinds (§2.1), not by per-effect overrides — path confirmed (ADR-0013).
