class_name MapGraph
extends Resource
## The generated run map (run-structure.md §3): a branching single-act graph of
## MapNodes connected by forward edges, with explicit entry rows and a single
## terminal boss node.

## node_id (StringName) -> MapNode.
@export var nodes: Dictionary = {}
## Entry node ids (row 0).
@export var start: Array[StringName] = []
## Terminal boss node id.
@export var boss: StringName = &""


## Plain-Dictionary form for JSON. Each MapNode is serialized via its own
## to_dict(); keys are plain Strings.
func to_dict() -> Dictionary:
	var nodes_out: Dictionary = {}
	for key: Variant in nodes.keys():
		var node_v: Variant = nodes[key]
		if node_v is MapNode:
			var node: MapNode = node_v
			nodes_out[String(key)] = node.to_dict()
	var start_out: Array = []
	for entry: StringName in start:
		start_out.append(String(entry))
	return {
		"nodes": nodes_out,
		"start": start_out,
		"boss": String(boss),
	}


## Reconstruct a typed MapGraph (with typed MapNodes) from its plain-Dictionary
## form. Tolerant of missing keys.
static func from_dict(d: Dictionary) -> MapGraph:
	var graph := MapGraph.new()
	var rebuilt: Dictionary = {}
	var nodes_v: Variant = d.get("nodes", {})
	if nodes_v is Dictionary:
		var nodes_in: Dictionary = nodes_v
		for key: Variant in nodes_in.keys():
			var node_v: Variant = nodes_in[key]
			if node_v is Dictionary:
				var node_d: Dictionary = node_v
				rebuilt[StringName(String(key))] = MapNode.from_dict(node_d)
	graph.nodes = rebuilt
	var start_in: Array[StringName] = []
	var start_v: Variant = d.get("start", [])
	if start_v is Array:
		var arr: Array = start_v
		for item: Variant in arr:
			start_in.append(StringName(String(item)))
	graph.start = start_in
	graph.boss = StringName(String(d.get("boss", "")))
	return graph
