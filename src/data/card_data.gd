class_name CardData
extends Resource
## A playable action / card (data-schemas.md §3).

@export var id: StringName = &""
@export var display_name: String = ""
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
