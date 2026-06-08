class_name EncounterData
extends Resource
## A single tactical skirmish (data-schemas.md §6).
##
## Positionless (ADR-0013): an encounter is just a roster of enemies plus the
## win condition — no grid, terrain, or spawn coordinates. The party comes from
## the caller (RunState in the run layer); enemies are listed by id and resolved
## against the ContentDatabase at assembly.

@export var id: StringName = &""
@export var display_name: String = ""
@export var enemies: Array[StringName] = []
@export var win_condition: StringName = &"defeat_all"
@export var win_param: int = 0
@export var rewards: Array[StringName] = []
