class_name MapGenConfig
extends Resource
## Data-driven knobs for map generation (run-structure.md §4). Authored content
## lives in /data; these defaults mirror the documented v1 defaults so the shell
## is usable on its own. This is a data shell only — generation logic lives in a
## separate P2 task.

## Act depth (excludes the boss row).
@export var rows: int = 8
## Nodes-per-row range.
@export var width_min: int = 2
@export var width_max: int = 3
## How often paths split / merge (0..1).
@export var branchiness: float = 0.5
## Relative node-type frequency by row band (rest rarer early, elite later).
@export var type_weights: Dictionary = {
	&"combat": 6,
	&"elite": 2,
	&"rest": 2,
	&"event": 2,
}
## Structural promises (e.g. a rest immediately before the boss).
@export var guarantees: Dictionary = {
	&"rest_before_boss": true,
}
