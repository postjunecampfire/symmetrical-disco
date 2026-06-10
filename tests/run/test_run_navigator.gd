extends "res://addons/gut/test.gd"
## GUT suite for RunNavigator (P2·10): reachable-node logic, travel/clear flow,
## completion, and content selection (encounter/event for a node). Uses a small
## hand-built map for deterministic structure and the real /data for the encounter
## pool + events.

const RunNavigatorScript := preload("res://src/run/run_navigator.gd")
const RunStateScript := preload("res://src/run/run_state.gd")
const MapGraphScript := preload("res://src/run/map_graph.gd")
const MapNodeScript := preload("res://src/run/map_node.gd")
const ContentDatabaseScript := preload("res://src/data/content_database.gd")

var _db: ContentDatabase


func before_each() -> void:
	_db = ContentDatabaseScript.new()
	_db.load_from_dir("res://data")


## A tiny linear-ish map:  start -> {a_combat} ; a_combat -> {b_event} ;
## b_event -> {boss}. (One entry node to keep traversal assertions crisp.)
func _node(id: StringName, type: StringName, row: int, nxt: Array) -> MapNode:
	var n := MapNodeScript.new()
	n.id = id
	n.node_type = type
	n.row = row
	var edges: Array[StringName] = []
	for e in nxt:
		edges.append(StringName(String(e)))
	n.next = edges
	return n


func _map() -> MapGraph:
	var g := MapGraphScript.new()
	g.nodes = {
		&"a_combat": _node(&"a_combat", &"combat", 0, [&"b_event"]),
		&"b_event": _node(&"b_event", &"event", 1, [&"n_boss"]),
		&"n_boss": _node(&"n_boss", &"boss", 2, []),
	}
	g.start = [&"a_combat"] as Array[StringName]
	g.boss = &"n_boss"
	return g


func _run() -> RunState:
	var run := RunStateScript.new()
	run.seed = 123
	run.party = [&"fighter", &"mage"] as Array[StringName]
	run.map = _map()
	run.position = &""
	run.cleared = [] as Array[StringName]
	return run


func _nav(run: RunState) -> RunNavigator:
	return RunNavigatorScript.new(_db, run)


# --- Reachability + traversal -----------------------------------------------

func test_reachable_at_start_is_the_entry_row() -> void:
	var nav := _nav(_run())
	assert_true(nav.at_start(), "position empty == at start")
	var r := nav.reachable()
	assert_eq(r.size(), 1, "one entry node")
	assert_eq(r[0].id, &"a_combat", "entry node is the start row")


func test_travel_then_clear_advances_the_frontier() -> void:
	var run := _run()
	var nav := _nav(run)
	assert_true(nav.travel_to(&"a_combat"), "can enter a reachable node")
	assert_eq(run.position, &"a_combat", "position updated")
	nav.complete_current()
	assert_true(run.cleared.has(&"a_combat"), "node marked cleared")

	var r := nav.reachable()
	assert_eq(r.size(), 1, "now the combat node's edge is reachable")
	assert_eq(r[0].id, &"b_event", "frontier advanced to the next node")


func test_cannot_travel_to_unreachable_node() -> void:
	var nav := _nav(_run())
	assert_false(nav.travel_to(&"n_boss"), "the boss is not reachable from the start")
	assert_false(nav.can_travel_to(&"b_event"), "a far node is not reachable yet")


func test_cleared_nodes_are_excluded_from_reachable() -> void:
	var run := _run()
	run.position = &"a_combat"
	run.cleared = [&"a_combat", &"b_event"] as Array[StringName]
	var nav := _nav(run)
	# From a_combat, next is b_event, but it's cleared -> excluded.
	var r := nav.reachable()
	assert_eq(r.size(), 0, "an already-cleared edge is not offered again")


# --- Completion -------------------------------------------------------------

func test_is_complete_only_after_boss_cleared() -> void:
	var run := _run()
	var nav := _nav(run)
	assert_false(nav.is_complete(), "not complete at the start")
	run.cleared = [&"a_combat", &"b_event", &"n_boss"] as Array[StringName]
	assert_true(nav.is_complete(), "complete once the boss is cleared")


func test_is_boss_flags_the_boss_node() -> void:
	var nav := _nav(_run())
	assert_true(nav.is_boss(_node(&"x", &"boss", 0, [])), "boss type detected")
	assert_false(nav.is_boss(_node(&"x", &"combat", 0, [])), "non-boss not flagged")


# --- Content selection ------------------------------------------------------

func test_encounter_for_uses_payload_when_set() -> void:
	var nav := _nav(_run())
	var n := _node(&"c", &"combat", 0, [])
	n.payload = &"skirmish_01"
	assert_eq(nav.encounter_for(n), &"skirmish_01", "explicit payload wins")


func test_encounter_for_picks_from_pool_by_type() -> void:
	var nav := _nav(_run())
	var combat := nav.encounter_for(_node(&"c", &"combat", 0, []))
	var pool := _db.get_encounters_for_type(&"combat")
	assert_true(pool.has(combat), "combat node draws a combat-pool encounter: %s" % combat)

	var boss := nav.encounter_for(_node(&"n_boss", &"boss", 0, []))
	assert_true(_db.get_encounters_for_type(&"boss").has(boss), "boss node draws a boss encounter")


func test_encounter_for_is_deterministic_per_node() -> void:
	var a := _nav(_run()).encounter_for(_node(&"same_id", &"combat", 0, []))
	var b := _nav(_run()).encounter_for(_node(&"same_id", &"combat", 0, []))
	assert_eq(a, b, "same run seed + node id -> same encounter pick")


func test_event_for_picks_a_loaded_event() -> void:
	var nav := _nav(_run())
	var ev := nav.event_for(_node(&"e", &"event", 0, []))
	assert_true(_db.get_event(ev) != null, "event node resolves to a real event: %s" % ev)


# --- M3 tier banding (EventData.tiers, docs/systems/events.md) ----------------

func test_event_for_respects_tier_bands() -> void:
	# Act 1 == tier 1: sample many node salts; no pick may carry a band that
	# excludes tier 1 (e.g. evt_echoing_stairwell is tiers [5,6]).
	var run := _run()
	run.act = 1
	var nav := _nav(run)
	for i in 40:
		var picked := nav.event_for(_node(StringName("salt_%d" % i), &"event", 0, []))
		var ev: EventData = _db.get_event(picked)
		assert_not_null(ev, "pick resolves: %s" % picked)
		if ev == null:
			continue
		assert_true(ev.tiers.is_empty() or ev.tiers.has(1),
			"act 1 (tier 1) must never draw off-band event '%s' (tiers %s)" % [picked, ev.tiers])


func test_event_for_payload_bypasses_tier_band() -> void:
	var run := _run()
	run.act = 1  # tier 1, but the authored payload is a tier 5-6 event
	var nav := _nav(run)
	var n := _node(&"fixed", &"event", 0, [])
	n.payload = &"evt_echoing_stairwell"
	assert_eq(nav.event_for(n), &"evt_echoing_stairwell", "explicit payload wins over banding")


# --- Resume: navigator works off a SAVED-then-LOADED run (save/resume wiring) -

func test_navigator_resumes_from_a_saved_run() -> void:
	const PATH := "user://test_resume_nav.json"
	var run := _run()
	# Mid-run: entered a_combat and cleared it; frontier should be b_event.
	run.position = &"a_combat"
	run.cleared = [&"a_combat"] as Array[StringName]
	assert_true(run.save_to(PATH), "saved mid-run state")

	var loaded: RunState = RunStateScript.load_from(PATH)
	assert_not_null(loaded, "loaded the saved run")
	var nav := RunNavigatorScript.new(_db, loaded)
	assert_eq(nav.current_node().id, &"a_combat", "position survived the round-trip")
	var r := nav.reachable()
	assert_eq(r.size(), 1, "frontier restored")
	assert_eq(r[0].id, &"b_event", "resumes at the correct next node")
	DirAccess.remove_absolute(PATH)
