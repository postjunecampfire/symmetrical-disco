extends GutTest
## GUT tests for MapGenerator (P2·03).
##
## Generates maps from MapGenConfig + a seed and asserts the structural
## invariants from run-structure.md §3: every node reachable from a start node;
## edges are strictly forward (target row = source row + 1, so no cycles);
## exactly one boss that is terminal and reachable; a sane node-type
## distribution; and full determinism (same seed -> identical graph, different
## seeds usually differ).

const _SEEDS: Array[int] = [1, 7, 42, 1000, 8675309, -13]


# --- Helpers ---

func _config() -> MapGenConfig:
	# Documented v1 defaults are fine; instantiating fresh keeps tests isolated
	# from any authored /data overrides.
	return MapGenConfig.new()


func _generate(gen_seed: int) -> MapGraph:
	var gen := MapGenerator.new()
	return gen.generate(_config(), gen_seed)


## Breadth-first set of node ids reachable from the graph's start set.
func _reachable(graph: MapGraph) -> Dictionary:
	var visited: Dictionary = {}
	var frontier: Array[StringName] = []
	frontier.append_array(graph.start)
	while not frontier.is_empty():
		var id: StringName = frontier.pop_back()
		if visited.has(id):
			continue
		visited[id] = true
		var node: MapNode = graph.nodes[id]
		for nx: StringName in node.next:
			if not visited.has(nx):
				frontier.append(nx)
	return visited


func _type_counts(graph: MapGraph) -> Dictionary:
	var counts: Dictionary = {}
	for key: Variant in graph.nodes.keys():
		var node: MapNode = graph.nodes[key]
		var t: StringName = node.node_type
		counts[t] = int(counts.get(t, 0)) + 1
	return counts


# --- Structure: reachability ---

func test_every_node_reachable_from_start() -> void:
	for gen_seed: int in _SEEDS:
		var graph: MapGraph = _generate(gen_seed)
		assert_false(graph.start.is_empty(), "seed %d: start set is non-empty" % gen_seed)
		var visited: Dictionary = _reachable(graph)
		assert_eq(
			visited.size(),
			graph.nodes.size(),
			"seed %d: every node reachable from a start node" % gen_seed
		)


func test_start_set_is_exactly_row_zero() -> void:
	var graph: MapGraph = _generate(42)
	for key: Variant in graph.nodes.keys():
		var node: MapNode = graph.nodes[key]
		if node.row == 0:
			assert_true(
				graph.start.has(node.id),
				"row-0 node %s is in the start set" % String(node.id)
			)
	for start_id: StringName in graph.start:
		var start_node: MapNode = graph.nodes[start_id]
		assert_eq(start_node.row, 0, "start node %s is on row 0" % String(start_id))


# --- Structure: edges strictly forward (=> acyclic) ---

func test_edges_are_strictly_forward() -> void:
	for gen_seed: int in _SEEDS:
		var graph: MapGraph = _generate(gen_seed)
		for key: Variant in graph.nodes.keys():
			var node: MapNode = graph.nodes[key]
			for nx: StringName in node.next:
				assert_true(
					graph.nodes.has(nx),
					"seed %d: edge target %s exists" % [gen_seed, String(nx)]
				)
				var target: MapNode = graph.nodes[nx]
				assert_eq(
					target.row,
					node.row + 1,
					"seed %d: edge %s->%s steps forward exactly one row"
						% [gen_seed, String(node.id), String(nx)]
				)


func test_every_non_boss_node_has_a_forward_edge() -> void:
	# Forward-only + every node has an out-edge => every path leads to the boss.
	for gen_seed: int in _SEEDS:
		var graph: MapGraph = _generate(gen_seed)
		for key: Variant in graph.nodes.keys():
			var node: MapNode = graph.nodes[key]
			if node.id == graph.boss:
				continue
			assert_false(
				node.next.is_empty(),
				"seed %d: non-boss node %s has an outgoing edge"
					% [gen_seed, String(node.id)]
			)


# --- Structure: exactly one boss, terminal and reachable ---

func test_exactly_one_boss_terminal_and_reachable() -> void:
	for gen_seed: int in _SEEDS:
		var graph: MapGraph = _generate(gen_seed)
		var counts: Dictionary = _type_counts(graph)
		assert_eq(int(counts.get(&"boss", 0)), 1, "seed %d: exactly one boss node" % gen_seed)

		assert_true(graph.nodes.has(graph.boss), "seed %d: boss id resolves" % gen_seed)
		var boss: MapNode = graph.nodes[graph.boss]
		assert_eq(boss.node_type, &"boss", "seed %d: graph.boss is a boss node" % gen_seed)
		assert_true(boss.next.is_empty(), "seed %d: boss is terminal (no out-edges)" % gen_seed)

		# Boss sits one row beyond the deepest normal row.
		var max_normal_row: int = -1
		for key: Variant in graph.nodes.keys():
			var node: MapNode = graph.nodes[key]
			if node.node_type != &"boss":
				max_normal_row = maxi(max_normal_row, node.row)
		assert_eq(
			boss.row, max_normal_row + 1, "seed %d: boss row is beyond all normal rows" % gen_seed
		)

		var visited: Dictionary = _reachable(graph)
		assert_true(visited.has(graph.boss), "seed %d: boss is reachable from start" % gen_seed)


# --- Structure: node-type distribution is sane ---

func test_node_type_distribution_is_sane() -> void:
	for gen_seed: int in _SEEDS:
		var graph: MapGraph = _generate(gen_seed)
		var counts: Dictionary = _type_counts(graph)

		var combat: int = int(counts.get(&"combat", 0))
		var elite: int = int(counts.get(&"elite", 0))
		var rest: int = int(counts.get(&"rest", 0))
		var event: int = int(counts.get(&"event", 0))
		var boss: int = int(counts.get(&"boss", 0))

		assert_eq(boss, 1, "seed %d: exactly one boss" % gen_seed)
		assert_gt(elite, 0, "seed %d: at least one elite exists" % gen_seed)
		assert_gt(rest, 0, "seed %d: at least one rest exists" % gen_seed)

		# Combat is the dominant (plurality) node type.
		assert_gt(combat, elite, "seed %d: combat outnumbers elite" % gen_seed)
		assert_gt(combat, rest, "seed %d: combat outnumbers rest" % gen_seed)
		assert_gt(combat, event, "seed %d: combat outnumbers event" % gen_seed)


func test_rest_before_boss_guarantee_holds() -> void:
	# Default config guarantees rest_before_boss: every path into the boss must
	# pass through a rest node, i.e. every node that links to the boss is a rest.
	var graph: MapGraph = _generate(42)
	var found_pre_boss: bool = false
	for key: Variant in graph.nodes.keys():
		var node: MapNode = graph.nodes[key]
		if node.next.has(graph.boss):
			found_pre_boss = true
			assert_eq(
				node.node_type,
				&"rest",
				"pre-boss node %s is a rest (rest_before_boss)" % String(node.id)
			)
	assert_true(found_pre_boss, "at least one node links into the boss")


# --- Determinism ---

func test_same_seed_produces_identical_graph() -> void:
	for gen_seed: int in _SEEDS:
		var a: MapGraph = _generate(gen_seed)
		var b: MapGraph = _generate(gen_seed)
		var sa: String = JSON.stringify(a.to_dict())
		var sb: String = JSON.stringify(b.to_dict())
		assert_eq(sa, sb, "seed %d: regeneration is byte-identical" % gen_seed)


# --- Selective fog (ADR-0023) ---

func test_fog_hides_events_and_spares_visible_types() -> void:
	# Every event is a blind "?" node; elites/rests/boss/start-row are never hidden.
	for gen_seed: int in _SEEDS:
		var graph: MapGraph = _generate(gen_seed)
		var start_ids: Dictionary = {}
		for sid: StringName in graph.start:
			start_ids[sid] = true
		for key: Variant in graph.nodes.keys():
			var node: MapNode = graph.nodes[key]
			if node.node_type == &"event":
				assert_true(node.hidden, "seed %d: event %s is hidden" % [gen_seed, String(node.id)])
			if node.node_type == &"elite" or node.node_type == &"rest" or node.node_type == &"boss":
				assert_false(
					node.hidden,
					"seed %d: %s node %s stays visible" % [gen_seed, String(node.node_type), String(node.id)]
				)
			if start_ids.has(node.id):
				assert_false(node.hidden, "seed %d: start node %s is visible" % [gen_seed, String(node.id)])


func test_different_seeds_usually_differ() -> void:
	var signatures: Dictionary = {}
	for gen_seed: int in _SEEDS:
		var graph: MapGraph = _generate(gen_seed)
		var sig: String = JSON.stringify(graph.to_dict())
		signatures[sig] = true
	assert_gt(
		signatures.size(),
		1,
		"distinct seeds produce more than one distinct graph (got %d unique of %d)"
			% [signatures.size(), _SEEDS.size()]
	)


func test_null_config_returns_empty_graph() -> void:
	var gen := MapGenerator.new()
	var graph: MapGraph = gen.generate(null, 1)
	assert_not_null(graph, "null config yields an empty graph, not a crash")
	assert_eq(graph.nodes.size(), 0, "empty graph has no nodes")
	assert_eq(graph.start.size(), 0, "empty graph has no start set")


# --- Late-row bias (ADR-0019) --------------------------------------------------

func test_late_row_bias_tilts_last_third_toward_combat_and_elite() -> void:
	var plain := MapGenConfig.new()
	var biased := MapGenConfig.new()
	biased.late_row_bias = &"very_high"
	var plain_hard: int = 0
	var biased_hard: int = 0
	for s in range(30):
		plain_hard += _hard_late_nodes(MapGenerator.new().generate(plain, 5000 + s))
		biased_hard += _hard_late_nodes(MapGenerator.new().generate(biased, 5000 + s))
	assert_true(
		biased_hard > plain_hard,
		"very_high late bias yields more late combat/elite than none (%d vs %d over 30 seeds)" % [biased_hard, plain_hard]
	)


func test_unknown_late_row_bias_reads_as_none() -> void:
	var plain := MapGenConfig.new()
	var odd := MapGenConfig.new()
	odd.late_row_bias = &"nonsense_key"
	for s in range(5):
		var a: MapGraph = MapGenerator.new().generate(plain, 7000 + s)
		var b: MapGraph = MapGenerator.new().generate(odd, 7000 + s)
		assert_eq(a.to_dict(), b.to_dict(), "unknown bias key behaves exactly like none (seed %d)" % s)


## Count combat+elite nodes in the last third of NORMAL rows (boss row excluded;
## the forced pre-boss rest row is identical across configs so it cancels out).
func _hard_late_nodes(graph: MapGraph) -> int:
	var max_row: int = 0
	for key: Variant in graph.nodes.keys():
		var n: MapNode = graph.nodes[key]
		if n.node_type != &"boss":
			max_row = maxi(max_row, n.row)
	var rows: int = max_row + 1
	var cutoff: int = int(ceil(float(rows) * 2.0 / 3.0))
	var count: int = 0
	for key: Variant in graph.nodes.keys():
		var n: MapNode = graph.nodes[key]
		if n.node_type == &"boss" or n.row < cutoff:
			continue
		if n.node_type == &"combat" or n.node_type == &"elite":
			count += 1
	return count


# --- Shop / treasure placement (ADR-0023) -------------------------------------

func test_shop_and_treasure_guarantees_place_one_each() -> void:
	# With the act-1 authored config (shop/treasure guaranteed), every generated
	# map must contain at least one merchant and one treasure node.
	var db := ContentDatabase.new()
	db.load_from_dir("res://data")
	var act1: ActConfig = db.get_act(1)
	assert_not_null(act1, "act curve loaded")
	for seed_i in range(6):
		var graph: MapGraph = MapGenerator.new().generate(act1.map, 1000 + seed_i)
		var shops: int = 0
		var chests: int = 0
		for key: Variant in graph.nodes.keys():
			var node: MapNode = graph.nodes[key]
			if node.node_type == &"shop":
				shops += 1
			elif node.node_type == &"treasure":
				chests += 1
		assert_gt(shops, 0, "seed %d: at least one merchant on the map" % seed_i)
		assert_gt(chests, 0, "seed %d: at least one treasure on the map" % seed_i)
