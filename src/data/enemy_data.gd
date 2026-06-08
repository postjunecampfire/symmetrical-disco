class_name EnemyData
extends Resource
## An enemy unit (data-schemas.md §5).
##
## Positionless (ADR-0013): no move_range. `speed` is retained but unused for
## initiative under strict phases (ADR-0010).

@export var id: StringName = &""
@export var display_name: String = ""
@export var max_hp: int = 20
@export var speed: int = 8
@export var intents: Array[IntentData] = []
@export var intent_pattern: StringName = &"random_weighted"
@export var sprite: Texture2D
