class_name StatusData
extends Resource
## Reusable status-effect definition (data-schemas.md §2.4).

@export var id: StringName = &""
@export var display_name: String = ""
@export var stacking: StringName = &"intensity"
@export var decays_each_turn: bool = true
@export var icon: Texture2D
