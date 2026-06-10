class_name RaceData
extends Resource
## A playable race — the BASE STAT TEMPLATE of a party member (ADR-0021 part 1;
## supersedes the small-modifier model of ADR-0015).
##
## The model is inverted from ADR-0015: the race now carries the member's low,
## near-flat base stat line (a "normal person"), and the CLASS (CharacterData)
## is the small overlay bump on top. Composition stays additive
## (class + race + allocated), so the engine path is unchanged — only which
## layer holds the big numbers flipped. Race CON contributes to max HP via
## hp_per_con exactly like class/allocated CON; the custom card is granted to
## that member's run deck at creation.
##
## NOTE: gd field names keep the historical `*_mod` suffix to avoid call-site
## churn; the JSON keys are plain stat names (strength, dexterity, …) with the
## legacy `*_mod` keys still accepted by the loader.

@export var id: StringName = &""
@export var display_name: String = ""
@export var str_mod: int = 0
@export var dex_mod: int = 0
@export var con_mod: int = 0
@export var int_mod: int = 0
## A neutral card granted to a character of this race at creation.
@export var custom_card: StringName = &""
## The classless origin kit (ADR-0024): neutral commons a member of this race
## starts with (plus custom_card). Recruit candidates ship the same kit.
@export var starting_kit: Array[StringName] = [&"quick_stab", &"field_dressing", &"bulwark"]
