class_name MapGenerator
extends RefCounted
## Procedural generator for the run map (run-structure.md §3-§5).
##
## Builds a branching, single-act, forward-only graph: `config.rows` normal rows
## (each `width_min..width_max` nodes wide) connected by forward edges, capped by
## a single terminal boss node in a row beyond the last normal row. Node types
## are drawn from `config.type_weights` with documented biases (rest rarer early,
## elite weighted toward later rows) and honour `config.guarantees`.
##
## Deterministic: the same `gen_seed` always yields an identical MapGraph. All
## randomness flows through one seeded RandomNumberGenerator.

const _COMBAT: StringName = &"combat"
const _ELITE: StringName = &"elite"
const _REST: StringName = &"rest"
const _EVENT: StringName = &"event"
const _BOSS: StringName = &"boss"

const _BOSS_ID: StringName = &"n_boss"


## Generate a MapGraph from `config`, seeded by `gen_seed`. Returns an empty
## graph if `config` is null.
func generate(config: MapGenConfig, gen_seed: int) -> MapGraph:
	var graph := MapGraph.new()
	if config == null:
		return graph

	var rng := RandomNumberGenerator.new()
	rng.seed = gen_seed

	var rows: int = maxi(1, config.rows)
	var w_min: int = maxi(1, mini(config.width_min, config.width_max))
	var w_max: int = maxi(w_min, config.width_max)

	# 1) Lay out node ids per row (row_ids[r] is an Array[StringName]).
	var row_ids: Array = []
	for r in range(rows):
		var count: int = rng.randi_range(w_min, w_max)
		var ids: Array[StringName] = []
		for i in range(count):
			ids.append(StringName("n_%d_%d" % [r, i]))
		row_ids.append(ids)

	# 2) Create a MapNode per id (types assigned later).
	var nodes: Dictionary = {}
	for r in range(rows):
		var ids_r: Array[StringName] = row_ids[r]
		for id: StringName in ids_r:
			var node := MapNode.new()
			node.id = id
			node.row = r
			nodes[id] = node

	# Terminal boss node, one row beyond the last normal row.
	var boss := MapNode.new()
	boss.id = _BOSS_ID
	boss.node_type = _BOSS
	boss.row = rows
	boss.next = [] as Array[StringName]
	nodes[_BOSS_ID] = boss

	# 3) Forward edges between adjacent normal rows.
	for r in range(rows - 1):
		var cur: Array[StringName] = row_ids[r]
		var nxt: Array[StringName] = row_ids[r + 1]
		_connect_rows(cur, nxt, config.branchiness, rng, nodes)

	# Every node in the last normal row connects to the boss.
	var last: Array[StringName] = row_ids[rows - 1]
	for id: StringName in last:
		var node: MapNode = nodes[id]
		node.next = [_BOSS_ID] as Array[StringName]

	# 4) Assign node types.
	var rest_before_boss: bool = bool(config.guarantees.get(&"rest_before_boss", false))
	for r in range(rows):
		var ids_r: Array[StringName] = row_ids[r]
		for id: StringName in ids_r:
			var node: MapNode = nodes[id]
			if r == 0:
				# Row 0 is the start set: always combat (a clean on-ramp).
				node.node_type = _COMBAT
			elif rest_before_boss and r == rows - 1:
				# Guarantee a rest immediately before the boss: the whole final
				# normal row is rest, so every path passes through one.
				node.node_type = _REST
			else:
				node.node_type = _weighted_type(config.type_weights, r, rows, rng)

	# Guarantee a sane distribution: at least one rest and one elite exist.
	_ensure_type_present(nodes, row_ids, rows, _REST, rest_before_boss, rng)
	_ensure_type_present(nodes, row_ids, rows, _ELITE, rest_before_boss, rng)

	# 4b) Selective fog (ADR-0023): mark some nodes as "blind" (render as "?").
	_apply_fog(nodes, row_ids, rows, rng)

	# 5) Assemble the graph.
	graph.nodes = nodes
	var start_ids: Array[StringName] = row_ids[0]
	graph.start = start_ids
	graph.boss = _BOSS_ID
	return graph


## Selective fog (ADR-0023): mark some nodes HIDDEN so they render as "?" until the
## player arrives. Every `event` is hidden (the "?" surprises) and a deterministic
## ~third of mid-run combats are hidden too, so "some encounters are blind." The
## start row, boss, elites and rests stay visible. Determinism is preserved because
## the same seeded RNG drives the per-combat coin flip.
func _apply_fog(
	nodes: Dictionary, row_ids: Array, rows: int, rng: RandomNumberGenerator
) -> void:
	for r in range(1, rows):
		var ids_r: Array[StringName] = row_ids[r]
		for id: StringName in ids_r:
			var node: MapNode = nodes[id]
			if node.node_type == _EVENT:
				node.hidden = true
			elif node.node_type == _COMBAT and rng.randf() < 0.34:
				node.hidden = true


## Wire forward edges from `cur` row into `nxt` row. Guarantees every `cur` node
## has at least one outgoing edge and every `nxt` node has at least one incoming
## edge (so the graph stays fully connected and forward-only).
func _connect_rows(
	cur: Array[StringName],
	nxt: Array[StringName],
	branchiness: float,
	rng: RandomNumberGenerator,
	nodes: Dictionary
) -> void:
	var cur_n: int = cur.size()
	var nxt_n: int = nxt.size()
	var covered: Dictionary = {}  # nxt id -> true once it has an incoming edge.

	for i in range(cur_n):
		var node: MapNode = nodes[cur[i]]
		var edges: Array[StringName] = []

		# Primary target: proportional position in the next row (keeps edges
		# local so the act reads as a tidy braid rather than a tangle).
		var t: int = _map_index(i, cur_n, nxt_n, rng)
		edges.append(nxt[t])
		covered[nxt[t]] = true

		# Optional branch to an adjacent next-row node, governed by branchiness.
		if nxt_n > 1 and rng.randf() < branchiness:
			var dir: int = 1 if rng.randf() < 0.5 else -1
			var t2: int = clampi(t + dir, 0, nxt_n - 1)
			if t2 != t and not edges.has(nxt[t2]):
				edges.append(nxt[t2])
				covered[nxt[t2]] = true

		node.next = edges

	# Cover any orphaned next-row node by linking the nearest current node.
	for j in range(nxt_n):
		if covered.has(nxt[j]):
			continue
		var src_i: int = _map_index(j, nxt_n, cur_n, rng)
		var src: MapNode = nodes[cur[src_i]]
		var src_edges: Array[StringName] = src.next
		if not src_edges.has(nxt[j]):
			src_edges.append(nxt[j])
		src.next = src_edges
		covered[nxt[j]] = true


## Proportionally map index `i` of a `from_n`-wide row to an index in a
## `to_n`-wide row. Single-node source rows pick a uniformly random target.
func _map_index(i: int, from_n: int, to_n: int, rng: RandomNumberGenerator) -> int:
	if to_n <= 1:
		return 0
	if from_n <= 1:
		return rng.randi_range(0, to_n - 1)
	var frac: float = float(i) / float(from_n - 1)
	return clampi(roundi(frac * float(to_n - 1)), 0, to_n - 1)


## Weighted node-type draw for a normal (non-start, non-boss) node. Applies the
## documented row biases: elite scales up with depth, rest is rarer early, combat
## keeps full weight so it stays the dominant type.
func _weighted_type(
	weights: Dictionary, row: int, rows: int, rng: RandomNumberGenerator
) -> StringName:
	var denom: float = float(maxi(rows - 1, 1))
	var depth: float = float(row) / denom  # 0.0 (early) .. 1.0 (late)

	var combat_w: float = _weight_of(weights, _COMBAT, 6.0)
	var elite_w: float = _weight_of(weights, _ELITE, 2.0) * depth
	var rest_w: float = _weight_of(weights, _REST, 2.0) * (0.25 + 0.75 * depth)
	var event_w: float = _weight_of(weights, _EVENT, 2.0) * (0.5 + 0.5 * depth)

	var total: float = combat_w + elite_w + rest_w + event_w
	if total <= 0.0:
		return _COMBAT

	var roll: float = rng.randf() * total
	if roll < combat_w:
		return _COMBAT
	roll -= combat_w
	if roll < elite_w:
		return _ELITE
	roll -= elite_w
	if roll < rest_w:
		return _REST
	return _EVENT


## Read a node-type weight from the (Variant-valued) config dictionary as a float,
## falling back to `fallback` when absent.
func _weight_of(weights: Dictionary, key: StringName, fallback: float) -> float:
	if weights.has(key):
		var v: Variant = weights[key]
		return float(v)
	return fallback


## Force at least one node of `wanted` to exist if none was assigned. Picks
## deterministically from rows after the start row (excluding the forced rest row
## when `rest_before_boss` is set), so guarantees never collide.
func _ensure_type_present(
	nodes: Dictionary,
	row_ids: Array,
	rows: int,
	wanted: StringName,
	rest_before_boss: bool,
	rng: RandomNumberGenerator
) -> void:
	if _has_type(nodes, wanted):
		return

	var candidates: Array[StringName] = []
	for r in range(1, rows):
		if rest_before_boss and r == rows - 1:
			continue
		var ids_r: Array[StringName] = row_ids[r]
		candidates.append_array(ids_r)

	# Degenerate maps (very few rows): fall back to any non-start node.
	if candidates.is_empty():
		for r in range(1, rows):
			var ids_r2: Array[StringName] = row_ids[r]
			candidates.append_array(ids_r2)
	if candidates.is_empty():
		return

	var pick: StringName = candidates[rng.randi_range(0, candidates.size() - 1)]
	var node: MapNode = nodes[pick]
	node.node_type = wanted


## True if any node in the graph already carries `wanted` as its type.
func _has_type(nodes: Dictionary, wanted: StringName) -> bool:
	for key: Variant in nodes.keys():
		var node_v: Variant = nodes[key]
		if node_v is MapNode:
			var node: MapNode = node_v
			if node.node_type == wanted:
				return true
	return false
