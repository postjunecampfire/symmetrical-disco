class_name Effect
extends Resource
## The atomic action (data-schemas.md §2.2). A card or intent is a list of these.

@export var type: StringName = &""
@export var amount: int = 0
@export var status: StringName = &""
@export var stacks: int = 0
@export var target_override: TargetSpec
@export var params: Dictionary = {}
