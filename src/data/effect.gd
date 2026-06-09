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
## ADR-0020 scaling ladder: how hard `damage`/`block` amounts scale the owner's
## stat — `amount + floor(stat * stat_mult)`. 1.0 (default) is today's flat
## class-A behavior; ~1.5 = hybrid (class B); 2.0+ = pure multiplier (class C,
## guardrailed in data). Ignored when the card doesn't scale at all (neutral,
## ADR-0016) and by every non-damage/block effect type.
@export var stat_mult: float = 1.0
