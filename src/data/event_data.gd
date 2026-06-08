class_name EventData
extends Resource
## A minimal, data-driven event node (run-structure.md §6, ADR-0012): display text
## plus 2–3 choices, each carrying a list of typed outcome deltas. Resolved by
## EventResolver against the RunState. Authored in data/events/*.json.

@export var id: StringName = &""
@export var title: String = ""
@export var body: String = ""
@export var choices: Array[EventChoice] = []
