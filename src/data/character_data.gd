class_name CharacterData
extends Resource
## A playable party unit (data-schemas.md §4).
##
## Positionless (ADR-0013): no move_range. `speed` is retained but unused under
## strict phases (ADR-0010).
##
## Stats (ADR-0014): STR -> physical damage, DEX -> block, CON -> max HP,
## INT -> magic damage. `attack_stat` selects which stat powers this character's
## attacks (`str` for martials, `int` for casters). `max_hp` is derived from CON
## (`constitution * BattleConfig.hp_per_con`) by the loader; it is kept as a field
## so a runtime Combatant can read it directly.

@export var id: StringName = &""
@export var display_name: String = ""
@export var max_hp: int = 30
@export var speed: int = 10

@export var strength: int = 0
@export var dexterity: int = 0
@export var constitution: int = 0
@export var intelligence: int = 0
## Which stat powers this character's attacks: `str` (physical) or `int` (magic).
@export var attack_stat: StringName = &"str"

@export var innate_actions: Array[StringName] = [&"strike", &"defend"]
@export var starting_deck: Array[StringName] = []
@export var tags: Array[StringName] = []
@export var sprite: Texture2D
## Ascension (ADR-0022): a flat stat_mult STEP added to every card this member
## plays (set on the synthesized member sheet at Act 15; 0 = not ascended).
@export var ascension_mult: float = 0.0
