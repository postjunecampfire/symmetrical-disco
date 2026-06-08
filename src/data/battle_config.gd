class_name BattleConfig
extends Resource
## Global battle tunables (data-schemas.md §7).

@export var energy_per_turn: int = 3
@export var draw_per_turn: int = 5
@export var max_hand: int = 10
@export var reshuffle_discard: bool = true
## HP granted per point of CON (ADR-0014: CON -> max HP). A character's max_hp is
## derived as `constitution * hp_per_con`.
@export var hp_per_con: int = 2
## HP a downed unit revives at for the next encounter (ADR-0011, run layer).
@export var revive_hp: int = 8
## Fixed HP restored to each surviving unit after a won combat (ADR-0011).
@export var post_combat_heal: int = 5
## HP restored to each living party member by the "heal" choice at a rest node
## (run-structure.md §5, P2·07). Tunable; larger than post_combat_heal by design.
@export var rest_heal: int = 12

# --- Leveling (ADR-0015, P3·05) ---------------------------------------------
## Stat points a character may allocate on each level-up (ADR-0015 default 3).
@export var stat_points_per_level: int = 3
## XP awarded to each surviving party member for winning a combat.
@export var xp_per_combat: int = 10
## XP required to advance from level 1 to level 2 (the curve's base step).
@export var xp_curve_base: int = 30
## Extra XP added to each successive level's requirement: the XP to go from
## level L to L+1 is `xp_curve_base + xp_curve_step * (L - 1)` (a linear ramp).
@export var xp_curve_step: int = 20
## Levels per class promotion (P3·06): a character may take its Nth promotion once
## it reaches `promotion_level * N`. Default 20 (≈2–3 acts to the first).
@export var promotion_level: int = 20
