class_name EventChoice
extends Resource
## One option the player can take at an event node (run-structure.md §6). A label
## plus the ordered list of typed outcomes applied when it is chosen.

@export var label: String = ""
@export var outcomes: Array[EventOutcome] = []
