class_name MapNode
extends Resource
## A single node in the run map graph (run-structure.md §3).
##
## Nodes form a branching, single-act, forward-only graph. `next` lists the ids
## of the nodes reachable from this one (forward edges only — no cycles).

@export var id: StringName = &""
## `combat` | `elite` | `rest` | `event` | `boss`.
@export var node_type: StringName = &"combat"
## Depth in the map (0 = start row).
@export var row: int = 0
## Ids of nodes reachable from here (forward edges).
@export var next: Array[StringName] = []
## Optional: encounter id / event id (else chosen from a pool at resolve time).
@export var payload: StringName = &""
## Selective fog of war (ADR-0023): when true the node renders as "?" (Unknown)
## until the player arrives/clears it — a deliberately "blind" encounter. The
## generator hides events and a subset of mid-run combats; elites/rests/boss/start
## stay visible. A relic or class boon may pre-reveal it (set hidden = false).
@export var hidden: bool = false


## Plain-Dictionary form for JSON (StringName -> String).
func to_dict() -> Dictionary:
	var next_out: Array = []
	for edge: StringName in next:
		next_out.append(String(edge))
	return {
		"id": String(id),
		"node_type": String(node_type),
		"row": row,
		"next": next_out,
		"payload": String(payload),
		"hidden": hidden,
	}


## Reconstruct a typed MapNode from its plain-Dictionary form. Tolerant of
## missing keys (falls back to the same defaults as a fresh node).
static func from_dict(d: Dictionary) -> MapNode:
	var node := MapNode.new()
	node.id = StringName(String(d.get("id", "")))
	node.node_type = StringName(String(d.get("node_type", "combat")))
	var row_v: Variant = d.get("row", 0)
	node.row = int(row_v)
	node.payload = StringName(String(d.get("payload", "")))
	node.hidden = bool(d.get("hidden", false))
	var next_in: Array[StringName] = []
	var next_v: Variant = d.get("next", [])
	if next_v is Array:
		var arr: Array = next_v
		for item: Variant in arr:
			next_in.append(StringName(String(item)))
	node.next = next_in
	return node
