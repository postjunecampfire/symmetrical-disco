class_name TargetSpec
extends Resource
## How an action chooses what it affects on the grid (data-schemas.md §2.1).

@export var target_type: StringName = &"enemy"
@export var range: int = 1
@export var shape: StringName = &"single"
@export var radius: int = 0
