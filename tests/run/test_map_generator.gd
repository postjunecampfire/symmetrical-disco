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
