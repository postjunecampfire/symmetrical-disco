class_name Effect
extends Resource
## The atomic action (data-schemas.md §2.2). A card or intent is a list of these.
##
## Positionless (ADR-0013): there is no per-effect retargeting. Every effect in a
## card/intent applies to that card/intent's resolved target set; `target_type`
## lives on the owning TargetSpec, not here.

@export var type: StringName = &""
@export var amount: int = 0
@export var status: StringName = &""
@export var stacks: int = 0
@export var params: Dictionary = {}
