class_name CharacterData
extends Resource
## A playable party unit (data-schemas.md §4).

@export var id: StringName = &""
@export var display_name: String = ""
@export var max_hp: int = 30
@export var move_range: int = 3
@export var speed: int = 10
@export var innate_actions: Array[StringName] = [&"strike", &"defend"]
@export var starting_deck: Array[StringName] = []
@export var tags: Array[StringName] = []
@export var sprite: Texture2D
