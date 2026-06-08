class_name TargetSpec
extends Resource
## How an action chooses what it affects (data-schemas.md §2.1).
##
## Positionless (ADR-0013): targeting is by KIND, not location. There is no range,
## shape, or radius — the single `target_type` discriminator fully describes the
## affected set. Valid values:
##   self        — the acting unit.
##   ally        — one chosen friendly unit.
##   all_allies  — every living unit on the actor's team.
##   enemy       — one chosen opposing unit.
##   all_enemies — every living unit on the opposing team (AoE).
##   random_enemy— one random living opposing unit.

@export var target_type: StringName = &"enemy"
