class_name RaceData
extends Resource
## A playable race (ADR-0015): a small stat modifier plus one custom card.
##
## Race is a LIGHT modifier — flavor plus a nudge — applied on top of a
## character's class/stats at creation, not a primary build axis. The stat mods
## are added to the character's stats (CON also raises derived max HP); the
## custom card is granted to that character's run deck.
##
## Placeholders (Human / Elf / Orc) live in /data/races. Replace/extend freely.

@export var id: StringName = &""
@export var display_name: String = ""
@export var str_mod: int = 0
@export var dex_mod: int = 0
@export var con_mod: int = 0
@export var int_mod: int = 0
## A neutral card granted to a character of this race at creation.
@export var custom_card: StringName = &""
