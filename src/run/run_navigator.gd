class_name RunNavigator
extends RefCounted
## Pure run-flow logic over a generated map (run-structure.md §3, P2·10): which
## nodes are reachable from the current position, travelling to a node, marking it
## cleared, and resolving which encounter/event a node uses. Holds NO UI — MapView
## renders this and calls the resolvers; keeping the brain here makes the run flow
## testable headlessly.
##
## Position model: `run.position` is the node currently being (or last) resolved;
## `run.cleared` lists finished node ids. From the start (`position == ""`) the
## reachable set is the map's entry row; after a node is cleared the reachable set
## is that node's forward edges (minus anything already cleared). The run is
## complete once the boss node is cleared.

var db: ContentDatabase
var run: RunState


func _init(database: ContentDatabase, run_state: RunState) -> void:
	db = database
	run = run_state


# --- Position / traversal ---------------------------------------------------

func map() -> MapGraph:
	return run.map


## True before any node has been entered (position is still the empty start).
func at_start() -> bool:
	return run.position == &""


## The node currently at `run.position`, or null at the start / if missing.
func current_node() -> MapNode:
	if run.map == null:
		return null
	var v: Variant = run.map.nodes.get(run.position, null)
	return v if v is MapNode else null


## Nodes the player may travel to next: the entry row at the start, otherwise the
## current node's forward edges. Cleared nodes are excluded. Empty once the run is
## complete (or the map is malformed).
func reachable() -> Array[MapNode]:
	var out: Array[MapNode] = []
	if run.map == null:
		return out
	var ids: Array[StringName] = []
	if at_start():
		ids = run.map.start
	else:
		var node := current_node()
		if node != null:
			ids = node.next
	for id in ids:
		if run.cleared.has(id):
			continue
		var v: Variant = run.map.nodes.get(id, null)
		if v is MapNode:
			out.append(v)
	return out


## True if `node_id` is currently reachable.
func can_travel_to(node_id: StringName) -> bool:
	for n in reachable():
		if n.id == node_id:
			return true
	return false


## Move to `node_id` (must be reachable). Sets it as the current position so its
## resolution can run; does NOT mark it cleared. Returns false if not reachable.
func travel_to(node_id: StringName) -> bool:
	if not can_travel_to(node_id):
		return false
	run.position = node_id
	return true


## Mark the current node cleared (call after its encounter/event/rest resolves
## successfully). Idempotent. After this, reachable() returns the node's edges.
func complete_current() -> void:
	if run.position != &"" and not run.cleared.has(run.position):
		run.cleared.append(run.position)


## True once the boss node has been cleared — the act is won.
func is_complete() -> bool:
	return run.map != null and run.map.boss != &"" and run.cleared.has(run.map.boss)


func is_boss(node: MapNode) -> bool:
	return node != null and node.node_type == &"boss"


# --- Content selection for a node -------------------------------------------

## The encounter id a combat/elite/boss `node` should run: its explicit `payload`
## if set, else a deterministic pick from the encounter pool for its node type
## (seeded by the run seed + node id, so a resume picks the same fight). "" if no
## encounter is available.
func encounter_for(node: MapNode) -> StringName:
	if node == null:
		return &""
	if node.payload != &"":
		return node.payload
	var pool: Array[StringName] = db.get_encounters_for_type(node.node_type)
	return _seeded_pick(pool, node.id)


## The event id an event `node` should present: its `payload` if set, else a
## deterministic pick from all loaded events. "" if none exist.
func event_for(node: MapNode) -> StringName:
	if node == null:
		return &""
	if node.payload != &"":
		return node.payload
	var ids: Array[StringName] = []
	for key: Variant in db.events.keys():
		ids.append(StringName(String(key)))
	ids.sort_custom(func(a: StringName, b: StringName) -> bool: return String(a) < String(b))
	return _seeded_pick(ids, node.id)


# --- Internals --------------------------------------------------------------

## Deterministic choice from `options`, seeded by the run seed + `salt` (a node
## id), so the same node always resolves to the same pick within a run.
func _seeded_pick(options: Array[StringName], salt: StringName) -> StringName:
	if options.is_empty():
		return &""
	var rng := RandomNumberGenerator.new()
	rng.seed = run.seed ^ hash(salt)
	return options[rng.randi_range(0, options.size() - 1)]
