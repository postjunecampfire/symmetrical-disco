class_name IntentData
extends Resource
## A telegraphed enemy action (data-schemas.md §5, IntentData table).

@export var id: StringName = &""
@export var telegraph: StringName = &"attack"
@export var target: TargetSpec
@export var effects: Array[Effect] = []
@export var weight: int = 1
