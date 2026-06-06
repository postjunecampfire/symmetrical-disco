class_name EncounterData
extends Resource
## A single tactical skirmish (data-schemas.md §6).
##
## terrain and enemy_spawns are arrays of plain Dictionaries matching the
## TerrainCell / Spawn shapes in §6:
##   TerrainCell: { "pos": Vector2i, "terrain": StringName }
##   Spawn:       { "enemy": StringName, "pos": Vector2i }

@export var id: StringName = &""
@export var display_name: String = ""
@export var grid_size: Vector2i = Vector2i(6, 6)
@export var terrain: Array[Dictionary] = []
@export var player_spawns: Array[Vector2i] = []
@export var enemy_spawns: Array[Dictionary] = []
@export var win_condition: StringName = &"defeat_all"
@export var win_param: int = 0
@export var rewards: Array[StringName] = []
