class_name RelicData
extends Resource
## A light, persistent run modifier (run-structure.md §7, ADR-0012, P2·12). A relic
## is a small trigger+effect pair (mirroring the combat Effect registry): RelicEngine
## fires its `effect` at its `trigger` when a fight is assembled/played — or, for
## run-layer effects, a static RelicEngine query sums/reads it where the run system
## consumes it (the `floor_reduction` pattern).
##
## Trigger registry (M3):
##   combat_start      — once at assembly (gain_block / add_strength).
##   turn_start        — each player turn (gain_energy / draw_extra).
##   passive           — assembly-time or RUN-LAYER queries (max_hp_up,
##                       floor_reduction, the economy/sight/derivation effects).
##   on_kill           — whenever an ENEMY dies (gain_block / gain_energy / gain_gold).
##   on_curse_drawn    — whenever a player draws a curse card (gain_energy /
##                       gain_block, credited to the DRAWER).
##   hp_threshold      — the FIRST time a member falls below half HP each combat
##                       (gain_block / add_strength, credited to that member).
##   on_status_applied — whenever a status lands on an ENEMY (amplify_burn /
##                       amplify_bleed / amplify_poison add `amount` extra stacks).
##   on_card_played    — play-count synergy: from the RelicEngine.COMBO_THRESHOLD'th
##                       card each player turn, `damage` cards deal +amount
##                       (combo_damage).
##
## Effect registry (M3) — combat effects:
##   gain_block   (combat_start: party / on_kill: party / on_curse_drawn: drawer /
##                 hp_threshold: that member) — +amount Block.
##   add_strength (combat_start: party / hp_threshold: that member) — +amount Strength.
##   max_hp_up    (passive)      — +amount max HP (and current) to each member.
##   gain_energy  (turn_start / on_kill: first pool; on_curse_drawn: drawer) — +amount energy.
##   draw_extra   (turn_start)   — draw +amount cards each player turn.
##   gain_gold    (on_kill)      — bank +amount run gold (credited by finish_combat).
##   amplify_burn / amplify_bleed / amplify_poison (on_status_applied) — +amount
##                 extra stacks whenever that status lands on an enemy.
##   combo_damage (on_card_played) — +amount damage on 3rd+ cards each turn.
## Run-layer effects (all trigger `passive`, consumed via static RelicEngine queries):
##   floor_reduction         — lower the derived-deck auto-fill floor by `amount`
##                             (ADR-0029; clamped at BattleConfig.derived_deck_floor_min).
##   extra_copy_rare         — each RARE skill in a loadout derives +amount copies.
##   extra_copy_first        — each member's FIRST active skill derives +amount copies.
##   upgrade_basics          — auto-fill basics derive as their upgraded variants.
##   gold_on_win             — +amount run gold after each won combat.
##   gold_on_rest            — +amount run gold at each rest node.
##   gold_pile_bonus         — treasure gold piles are +amount% larger.
##   shop_discount           — shop prices -amount% (summed, capped in RelicEngine).
##   curse_removal_discount  — the shop curse-removal service -amount% (after
##                             shop_discount).
##   reveal_map              — hidden ("?") map nodes render revealed.
##   reveal_boss             — the act's boss encounter shows on the map header.
## Extend by adding a handler/query in RelicEngine, like the combat EffectResolver.

## Recognised triggers and effects (the loader validates against these; RelicEngine
## dispatches on them). Kept on the data class so the contract lives in one place.
const TRIGGERS: Array[StringName] = [
	&"combat_start", &"turn_start", &"passive", &"on_kill",
	&"on_curse_drawn", &"hp_threshold", &"on_status_applied", &"on_card_played",
]
const EFFECTS: Array[StringName] = [
	&"gain_block", &"add_strength", &"max_hp_up", &"gain_energy", &"draw_extra",
	&"floor_reduction",
	&"gain_gold", &"amplify_burn", &"amplify_bleed", &"amplify_poison",
	&"combo_damage",
	&"extra_copy_rare", &"extra_copy_first", &"upgrade_basics",
	&"gold_on_win", &"gold_on_rest", &"gold_pile_bonus",
	&"shop_discount", &"curse_removal_discount",
	&"reveal_map", &"reveal_boss",
]

@export var id: StringName = &""
@export var display_name: String = ""
@export var description: String = ""
@export var rarity: StringName = &"common"
@export var trigger: StringName = &"combat_start"
@export var effect: StringName = &"gain_block"
@export var amount: int = 0
@export var icon: Texture2D
