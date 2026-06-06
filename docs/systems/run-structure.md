# Run Structure — Data Contracts (run/map layer)

**Status:** Draft (v1 scope)
**Owners:** Michael; Claude
**Depends on:** [ADR-0012](../decisions/0012-run-structure-and-map.md) (run structure & map), [ADR-0011](../decisions/0011-death-downed-and-hp-attrition.md) (HP attrition / death), [ADR-0001](../decisions/0001-card-driven-tactical-roguelite.md). Extends [data-schemas.md](data-schemas.md) (combat-layer contracts — unchanged).

> This is the **contract for the run/map layer** that wraps the existing, tested combat. The combat schema ([data-schemas.md](data-schemas.md)) is untouched; this document adds the entities *around* a fight: the run state, the map, node types, rewards, rest, events, and relics. Same rules as data-schemas.md — IDs are `snake_case` `StringName`, content is data (Godot `Resource`/JSON), no balance magic numbers in code, the loader validates references. Changing a shape here is an interface change — flag it.

---

## 1. How the run wraps combat

A **run** is a traversal of a generated **map** of **nodes**. Most nodes resolve to something between fights; **combat/elite/boss** nodes hand off to the existing combat layer:

```
RunController ── picks node ──► NodeType
   combat/elite/boss ─► EncounterAssembler.build(encounter, db, party, run_deck, relics, carried_hp) ─► EncounterBattle ─► win → reward ; TPK → run end
   rest              ─► heal a chunk OR upgrade a card
   event             ─► choice → outcome (HP / card / relic deltas)
```

The combat layer needs **no rewrite**: a combat node passes the **RunState's party + carried HP + run deck (+ active relics)** into `EncounterAssembler`. Relic effects apply through additive hooks at combat assembly/turn boundaries (see §8).

---

## 2. RunState

The persistent state of an in-progress run. Serializable to `user://` for mid-run save/resume.

| Field | Type | Notes |
|-------|------|-------|
| `seed` | int | Run RNG seed (map gen, draws, rewards are derived from it). |
| `party` | Array[StringName] | Character ids (2–3, [ADR-0004](../decisions/0004-shared-deck-character-tagged-cards.md)). |
| `party_hp` | Dictionary | `character_id -> current_hp` (carried across nodes, [ADR-0011](../decisions/0011-death-downed-and-hp-attrition.md)). |
| `downed` | Array[StringName] | Character ids currently downed (revive next encounter at low HP). |
| `run_deck` | Array[StringName] | Card ids in the run deck (starting decks + drafted cards). |
| `relics` | Array[StringName] | Relic ids acquired this run (§7). |
| `map` | MapGraph | The generated map (§3). |
| `position` | StringName | Current node id. |
| `cleared` | Array[StringName] | Resolved node ids. |

```gdscript
class_name RunState extends Resource
@export var seed: int = 0
@export var party: Array[StringName] = []
@export var party_hp: Dictionary = {}            # character_id -> int
@export var downed: Array[StringName] = []
@export var run_deck: Array[StringName] = []
@export var relics: Array[StringName] = []
@export var map: MapGraph
@export var position: StringName = &""
@export var cleared: Array[StringName] = []
```

**Save/resume:** serialize RunState to `user://saves/run.json` (or `.tres`); a run is resumable from the current `position`.

---

## 3. Map — MapNode & MapGraph

A branching, single-act graph (Slay-the-Spire style): rows of nodes connected by forward edges; the player picks one of the reachable next nodes.

### MapNode
| Field | Type | Notes |
|-------|------|-------|
| `id` | StringName | Unique within the map. |
| `node_type` | StringName | `combat` \| `elite` \| `rest` \| `event` \| `boss`. |
| `row` | int | Depth (0 = start row). |
| `next` | Array[StringName] | Ids of nodes reachable from here (forward edges). |
| `payload` | StringName | Optional: encounter id / event id (else chosen from a pool at resolve time). |

### MapGraph
| Field | Type | Notes |
|-------|------|-------|
| `nodes` | Dictionary | `node_id -> MapNode`. |
| `start` | Array[StringName] | Entry node ids (row 0). |
| `boss` | StringName | Terminal boss node id. |

```gdscript
class_name MapNode extends Resource
@export var id: StringName
@export var node_type: StringName = &"combat"
@export var row: int = 0
@export var next: Array[StringName] = []
@export var payload: StringName = &""

class_name MapGraph extends Resource
@export var nodes: Dictionary = {}      # StringName -> MapNode
@export var start: Array[StringName] = []
@export var boss: StringName = &""
```

**Invariants** (map gen must guarantee, and tests must check): every node reachable from a `start` node; every path leads forward (no cycles); the only row beyond the last is the single `boss`; node-type distribution within the configured weights.

---

## 4. Map generation parameters (MapGenConfig)

Data-driven knobs (in `/data`, tunable — [ADR-0003](../decisions/0003-data-driven-content-architecture.md)).

| Field | Type | Default (v1) | Notes |
|-------|------|--------------|-------|
| `rows` | int | 8 | Act depth (excl. boss row). |
| `width_min` / `width_max` | int | 2 / 3 | Nodes per row range. |
| `branchiness` | float | 0.5 | How often paths split/merge. |
| `type_weights` | Dictionary | `{combat:6, elite:2, rest:2, event:2}` | Relative frequency by row band (rest rarer early, elite later). |
| `guarantees` | Dictionary | e.g. `{rest_before_boss: true}` | Structural promises. |

---

## 5. Node behaviors (v1)

- **combat** — resolve an encounter (from `payload` or a pool, §9 of data-schemas / P2·09) via `EncounterAssembler` using RunState. Win → **card reward** (§6). TPK → run ends.
- **elite** — a harder encounter; reward is a **card reward + a relic** (§7).
- **rest** — choose **heal** (data-driven amount/%) OR **upgrade a card** (apply a card's `upgrade_of` variant in `run_deck`).
- **event** — present an EventData (§6) choice; apply its outcome. Minimal in v1.
- **boss** — the terminal encounter; win → run complete (v1 victory); TPK → run ends. Reward: relic (+ future cross-run unlock, deferred).

After every combat-type node, apply the **post-combat partial heal** and resolve **downed** units (revive next encounter at low HP) per [ADR-0011](../decisions/0011-death-downed-and-hp-attrition.md).

---

## 6. Rewards & Events

### CardRewardConfig / card pool
After a combat, offer **pick-1-of-N** from a **character-tagged pool** (only cards playable by the run's party, plus neutral).

| Field | Type | Notes |
|-------|------|-------|
| `choices` | int | N options (v1 default 3). |
| `pool` | Array[StringName] | Eligible card ids (filtered by party `character_tag` + `neutral`). |
| `rarity_weights` | Dictionary | `common/uncommon/rare` draft odds. |

The picked card id is appended to `RunState.run_deck`. Skipping (taking nothing) is allowed.

### EventData (minimal, v1)
| Field | Type | Notes |
|-------|------|-------|
| `id` | StringName | Unique. |
| `title` / `body` | String | Display text. |
| `choices` | Array[EventChoice] | 2–3 options. |

`EventChoice`: `{ label: String, outcomes: Array[Outcome] }` where an `Outcome` is a small typed delta: `{ kind: heal|damage_party|add_card|remove_card|add_relic|nothing, amount?: int, id?: StringName }`. Broad event scripting is **deferred** ([ADR-0012](../decisions/0012-run-structure-and-map.md)).

---

## 7. RelicData (light, v1)

Persistent run modifiers that fire at defined hooks. Data-driven with a small **trigger + effect** model (mirrors the combat Effect registry philosophy).

| Field | Type | Notes |
|-------|------|-------|
| `id` | StringName | Unique. |
| `display_name` | String | |
| `description` | String | |
| `rarity` | StringName | `common` \| `uncommon` \| `rare` \| `boss`. |
| `trigger` | StringName | When it fires (see registry below). |
| `effect` | StringName | What it does (see registry below). |
| `amount` | int | Magnitude. |
| `icon` | Texture2D | Placeholder allowed. |

**Trigger registry (v1):** `combat_start`, `turn_start`, `passive` (modifies a stat/config), `on_kill`.
**Effect registry (v1):** `gain_energy` (turn_start: +amount energy), `gain_block` (combat_start: +amount block to party), `draw_extra` (turn_start: draw +amount), `add_strength` (combat_start: +amount strength), `max_hp_up` (passive). Extend by adding a handler, like the combat EffectResolver.

```gdscript
class_name RelicData extends Resource
@export var id: StringName
@export var display_name: String
@export var description: String = ""
@export var rarity: StringName = &"common"
@export var trigger: StringName = &"combat_start"
@export var effect: StringName = &"gain_block"
@export var amount: int = 0
@export var icon: Texture2D
```

**Acquisition:** elites and the boss grant a relic; some events may. **Application:** when a combat is assembled, a `RelicEngine` applies each active relic's effect at its trigger (combat_start at assembly, turn_start each player turn, passive folded into stats). This is **additive** — implemented via hooks around the existing `EncounterBattle`, not by editing `BattleState`'s core.

---

## 8. Combat integration (how a fight gets the run context)

`EncounterAssembler.build(...)` is extended (additively) to accept run context so a combat node is fully driven by RunState:
- **party + carried HP:** spawn each party Combatant at `party_hp[id]` (downed units revived at the data-driven low HP).
- **run deck:** assemble the shared Deck from `run_deck` (not just starting decks).
- **relics:** a `RelicEngine` applies `combat_start` effects after assembly and `turn_start` effects at each player-turn start; `passive` relics fold into config/stats.
- On combat end, write surviving HP back to `RunState.party_hp`, mark downed, apply post-combat heal.

The existing `BattleState` / `EncounterBattle` test suites stay green — these are new wrapper hooks, not changes to the resolved combat rules.

---

## 9. Run-level telemetry (extends the logger)

New event types for the existing `TelemetryLogger`:
`node_entered` (id, type, row), `card_reward` (offered ids, picked id or skip), `rest_choice` (heal|upgrade, detail), `event_choice` (event id, choice, outcomes), `relic_gained` (id, source), `run_end` (extended: outcome, nodes visited, death node id, final deck size, relics). This lets us measure path choices, draft behavior, attrition across the run, and where runs die.

---

## 10. v1 scope vs deferred

**In v1:** RunState + save/resume; branching single-act map + generation; run controller; combat/elite/rest/event/boss nodes; card-reward draft; rest (heal/upgrade); minimal events; **light relics**; an encounter pool (+elite, +boss); map/run UI; run-level telemetry.

**Deferred:** shop & currency; cross-death meta-progression; multi-act maps; broad relic/event depth; advanced map structures.

## 11. Open questions (tunable, set during balancing)

- Map size / type distribution / branchiness; reward choice count `N`; rarity odds.
- Rest heal amount; post-combat heal; downed revive HP.
- Relic drop sources/odds; the initial relic set.
- Whether the boss win = full v1 victory or leads to a second act (deferred).
