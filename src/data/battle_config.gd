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
