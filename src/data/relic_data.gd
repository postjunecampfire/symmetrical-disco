class_name RelicData
extends Resource
## A light, persistent run modifier (run-structure.md §7, ADR-0012, P2·12). A relic
## is a small trigger+effect pair (mirroring the combat Effect registry): RelicEngine
## fires its `effect` at its `trigger` when a fight is assembled/played.
##
## Trigger registry (v1): combat_start | turn_start | passive | on_kill.
## Effect registry (v1):
##   gain_block   (combat_start) — +amount block to each living party member.
##   add_strength (combat_start) — +amount Strength to each living party member.
##   max_hp_up    (passive)      — +amount max HP (and current) to each member.
##   gain_energy  (turn_start)   — +amount energy each player turn.
##   draw_extra   (turn_start)   — draw +amount cards each player turn.
##   floor_reduction (passive)   — lower the derived-deck auto-fill floor by
##                                 `amount` (ADR-0029; clamped at
##                                 BattleConfig.derived_deck_floor_min). Consumed
##                                 at DECK DERIVATION (RunController -> SkillLoadout
##                                 via RelicEngine.floor_reduction_total), not in combat.
## Extend by adding a handler in RelicEngine, like the combat EffectResolver.
## (on_kill is a reserved trigger; no v1 effect maps to it yet.)

## Recognised triggers and effects (the loader validates against these; RelicEngine
## dispatches on them). Kept on the data class so the contract lives in one place.
const TRIGGERS: Array[StringName] = [&"combat_start", &"turn_start", &"passive", &"on_kill"]
const EFFECTS: Array[StringName] = [
	&"gain_block", &"add_strength", &"max_hp_up", &"gain_energy", &"draw_extra",
	&"floor_reduction",
]

@export var id: StringName = &""
@export var display_name: String = ""
@export var description: String = ""
@export var rarity: StringName = &"common"
@export var trigger: StringName = &"combat_start"
@export var effect: StringName = &"gain_block"
@export var amount: int = 0
@export var icon: Texture2D
