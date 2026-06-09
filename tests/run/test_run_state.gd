extends GutTest
## GUT tests for RunState + mid-run save/resume (P2·02).
##
## Builds a RunState in code with a small hand-built MapGraph (incl. a boss),
## round-trips it through save_to()/load_from(), and asserts every field
## survives. Uses a dedicated user:// path that is cleaned up around each test so
## the real run save (user://saves/run.json) is never touched.

const TEST_SAVE_PATH: String = "user://saves/test_run_state.json"


func before_each() -> void:
	_remove_test_save()


func after_each() -> void:
	_remove_test_save()


func _remove_test_save() -> void:
	if FileAccess.file_exists(TEST_SAVE_PATH):
		DirAccess.remove_absolute(TEST_SAVE_PATH)


# --- Fixture builders ---

func _make_node(id: StringName, type: StringName, row: int, next: Array[StringName]) -> MapNode:
	var node := MapNode.new()
	node.id = id
	node.node_type = type
	node.row = row
	node.next = next
	return node


## A 4-node single-act map: combat -> rest -> elite -> boss.
func _make_map() -> MapGraph:
	var graph := MapGraph.new()
	var start_node: MapNode = _make_node(&"n_start", &"combat", 0, [&"n_rest"] as Array[StringName])
	var rest_node: MapNode = _make_node(&"n_rest", &"rest", 1, [&"n_elite"] as Array[StringName])
	var elite_node: MapNode = _make_node(&"n_elite", &"elite", 2, [&"n_boss"] as Array[StringName])
	var boss_node: MapNode = _make_node(&"n_boss", &"boss", 3, [] as Array[StringName])
	boss_node.payload = &"the_warden"
	graph.nodes = {
		&"n_start": start_node,
		&"n_rest": rest_node,
		&"n_elite": elite_node,
		&"n_boss": boss_node,
	}
	graph.start = [&"n_start"] as Array[StringName]
	graph.boss = &"n_boss"
	return graph


func _make_run() -> RunState:
	var state := RunState.new()
	state.seed = 987654
	state.party = [&"knight", &"mage"] as Array[StringName]
	state.party_hp = {&"knight": 28, &"mage": 15}
	state.downed = [&"mage"] as Array[StringName]
	state.run_deck = [&"strike", &"strike", &"shield_bash", &"frost_nova"] as Array[StringName]
	state.relics = [&"lucky_coin"] as Array[StringName]
	state.map = _make_map()
	state.position = &"n_rest"
	state.cleared = [&"n_start"] as Array[StringName]
	# Race selection (ADR-0015) + leveling state (P3·05).
	state.party_races = {&"knight": &"orc", &"mage": &"elf"}
	state.party_level = {&"knight": 3, &"mage": 1}
	state.party_xp = {&"knight": 17, &"mage": 5}
	state.unspent_points = {&"knight": 2, &"mage": 0}
	state.allocated_stats = {
		&"knight": {&"str": 4, &"dex": 0, &"con": 2, &"int": 0},
		&"mage": {&"str": 0, &"dex": 0, &"con": 0, &"int": 3},
	}
	return state


# --- Round-trip ---

func test_save_and_load_round_trips_every_field() -> void:
	var original: RunState = _make_run()
	assert_true(original.save_to(TEST_SAVE_PATH), "save_to should succeed")
	assert_true(FileAccess.file_exists(TEST_SAVE_PATH), "save file should exist on disk")

	var loaded: RunState = RunState.load_from(TEST_SAVE_PATH)
	assert_not_null(loaded, "load_from should return a RunState")
	assert_is(loaded, RunState)

	# Scalars.
	assert_eq(loaded.seed, 987654, "seed round-trips")
	assert_eq(loaded.position, &"n_rest", "position round-trips")

	# Arrays.
	assert_eq(loaded.party, [&"knight", &"mage"] as Array[StringName], "party round-trips")
	assert_eq(loaded.downed, [&"mage"] as Array[StringName], "downed round-trips")
	assert_eq(
		loaded.run_deck,
		[&"strike", &"strike", &"shield_bash", &"frost_nova"] as Array[StringName],
		"run_deck round-trips (order + duplicates preserved)"
	)
	assert_eq(loaded.relics, [&"lucky_coin"] as Array[StringName], "relics round-trips")
	assert_eq(loaded.cleared, [&"n_start"] as Array[StringName], "cleared round-trips")

	# HP dictionary: keys are StringName, values int.
	assert_eq(loaded.party_hp.size(), 2, "party_hp has both entries")
	assert_eq(int(loaded.party_hp[&"knight"]), 28, "knight hp round-trips")
	assert_eq(int(loaded.party_hp[&"mage"]), 15, "mage hp round-trips")

	# Race selection round-trips (StringName -> StringName).
	assert_eq(loaded.party_races[&"knight"], &"orc", "party_races round-trips")
	assert_eq(loaded.party_races[&"mage"], &"elf", "party_races round-trips (both)")

	# Leveling dictionaries (ADR-0015 / P3·05): keys StringName, values int / nested.
	assert_eq(int(loaded.party_level[&"knight"]), 3, "party_level round-trips")
	assert_eq(int(loaded.party_xp[&"knight"]), 17, "party_xp round-trips")
	assert_eq(int(loaded.unspent_points[&"knight"]), 2, "unspent_points round-trips")
	var knight_alloc: Dictionary = loaded.allocated_stats[&"knight"]
	assert_eq(int(knight_alloc[&"str"]), 4, "allocated STR round-trips")
	assert_eq(int(knight_alloc[&"con"]), 2, "allocated CON round-trips")
	assert_eq(int(loaded.allocated_stats[&"mage"][&"int"]), 3, "allocated INT round-trips for mage")


func test_map_graph_round_trips_nodes_edges_and_boss() -> void:
	var original: RunState = _make_run()
	original.save_to(TEST_SAVE_PATH)
	var loaded: RunState = RunState.load_from(TEST_SAVE_PATH)
	assert_not_null(loaded, "load_from should return a RunState")

	var map: MapGraph = loaded.map
	assert_not_null(map, "map round-trips")
	assert_is(map, MapGraph)
	assert_eq(map.nodes.size(), 4, "all four nodes restored")
	assert_eq(map.start, [&"n_start"] as Array[StringName], "start row round-trips")
	assert_eq(map.boss, &"n_boss", "boss id round-trips")

	# Node identity, type, row, edges.
	var start_node: MapNode = map.nodes[&"n_start"]
	assert_is(start_node, MapNode)
	assert_eq(start_node.id, &"n_start", "node id round-trips")
	assert_eq(start_node.node_type, &"combat", "node type round-trips")
	assert_eq(start_node.row, 0, "node row round-trips")
	assert_eq(start_node.next, [&"n_rest"] as Array[StringName], "forward edge round-trips")

	var elite_node: MapNode = map.nodes[&"n_elite"]
	assert_eq(elite_node.node_type, &"elite", "elite type round-trips")
	assert_eq(elite_node.next, [&"n_boss"] as Array[StringName], "elite -> boss edge round-trips")

	var boss_node: MapNode = map.nodes[&"n_boss"]
	assert_eq(boss_node.node_type, &"boss", "boss node type round-trips")
	assert_eq(boss_node.payload, &"the_warden", "boss payload round-trips")
	assert_eq(boss_node.next, [] as Array[StringName], "boss has no forward edges")


# --- Graceful degradation ---

func test_load_from_missing_path_returns_null() -> void:
	var loaded: RunState = RunState.load_from("user://saves/does_not_exist_42.json")
	assert_null(loaded, "missing file returns null, not a crash")


func test_load_from_malformed_file_returns_null() -> void:
	var file: FileAccess = FileAccess.open(TEST_SAVE_PATH, FileAccess.WRITE)
	assert_not_null(file, "test setup: should be able to write malformed file")
	file.store_string("{ this is not valid json ]]")
	file.close()

	var loaded: RunState = RunState.load_from(TEST_SAVE_PATH)
	assert_null(loaded, "malformed JSON returns null, not a crash")


func test_empty_run_round_trips() -> void:
	var state := RunState.new()
	assert_true(state.save_to(TEST_SAVE_PATH), "default/empty run saves")
	var loaded: RunState = RunState.load_from(TEST_SAVE_PATH)
	assert_not_null(loaded, "empty run loads back")
	assert_eq(loaded.seed, 0, "default seed")
	assert_eq(loaded.party.size(), 0, "empty party")
	assert_null(loaded.map, "no map serializes back as null")


# --- Act (ADR-0019) ----------------------------------------------------------

func test_act_round_trips_and_defaults_to_one() -> void:
	var run := RunState.new()
	run.act = 3
	var copy := RunState.from_dict(run.to_dict())
	assert_eq(copy.act, 3, "act survives the save/load round trip")
	assert_eq(RunState.from_dict({}).act, 1, "a pre-act save (missing key) defaults to act 1")
